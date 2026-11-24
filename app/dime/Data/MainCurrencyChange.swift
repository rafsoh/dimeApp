//
//  MainCurrencyChange.swift
//  dime
//

import CoreData
import Foundation
import os
import WidgetKit

struct MainCurrencyChangePlan: Codable, Equatable {
    enum Kind: String, Codable {
        /// The transactions were in the new currency all along: those labelled with the old one are relabelled
        /// and those without a currency follow the main currency, as changing it always did.
        case relabel
        /// The transactions stay in the old currency: those without one are labelled with it before the main
        /// currency changes, so they're converted from then on.
        case convert
    }

    let kind: Kind
    let oldCurrency: String
    let newCurrency: String

    var predicate: NSPredicate {
        switch kind {
        case .relabel:
            return NSPredicate(format: "%K ==[c] %@", #keyPath(Transaction.currencyCode), oldCurrency)
        case .convert:
            return NSPredicate(format: "%K == nil", #keyPath(Transaction.currencyCode))
        }
    }

    var target: String {
        switch kind {
        case .relabel:
            return newCurrency
        case .convert:
            return oldCurrency
        }
    }
}

// Changes nothing but `currencyCode`, a batch at a time. Changed rows stop matching the plan's predicate, so
// running it again after an interruption carries on where it stopped and changes nothing once it's done.
enum MainCurrencyChanger {
    enum ChangeError: Error {
        case notConverging
    }

    static func count(_ plan: MainCurrencyChangePlan, in context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = plan.predicate
        return try context.count(for: request)
    }

    /// Call on the context's queue. Returns how many transactions were changed.
    static func apply(_ plan: MainCurrencyChangePlan, in context: NSManagedObjectContext, batchSize: Int = 500, maximumBatches: Int = .max) throws -> Int {
        let expected = try count(plan, in: context)
        // Sync can add matching transactions while this runs, but never this many.
        let batchLimit = expected / batchSize + 10
        var changed = 0
        var batches = 0

        while batches < maximumBatches {
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = plan.predicate
            request.fetchLimit = batchSize
            let batch = try context.fetch(request)

            guard !batch.isEmpty else {
                break
            }

            guard batches < batchLimit else {
                throw ChangeError.notConverging
            }

            for transaction in batch {
                transaction.currencyCode = plan.target
            }

            try context.save()
            context.reset()
            changed += batch.count
            batches += 1
        }

        return changed
    }
}

final class MainCurrencyChangeManager: ObservableObject {
    enum ChangeError: Error {
        case busy
        case waitingForICloud
        case backupFailed
        case failed
    }

    static let shared = MainCurrencyChangeManager(dataController: .shared, backupManager: .shared)
    static let pendingPlanKey = "pendingMainCurrencyChange"

    @Published private(set) var isWorking = false

    private let dataController: DataController
    private let backupManager: BackupManager
    private let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")
    private let logger = Logger(subsystem: "com.rafaelsoh.dime", category: "MainCurrencyChange")

    init(dataController: DataController, backupManager: BackupManager) {
        self.dataController = dataController
        self.backupManager = backupManager
    }

    /// A change that was interrupted. It's finished before the main currency moves on.
    var pendingPlan: MainCurrencyChangePlan? {
        defaults?.data(forKey: Self.pendingPlanKey).flatMap { try? JSONDecoder().decode(MainCurrencyChangePlan.self, from: $0) }
    }

    func change(to newCurrency: String, kind: MainCurrencyChangePlan.Kind, completion: @escaping (Result<Int, ChangeError>) -> Void) {
        let plan = MainCurrencyChangePlan(kind: kind, oldCurrency: dataController.currencyConverter.mainCurrency, newCurrency: newCurrency.uppercased())

        guard plan.oldCurrency != plan.newCurrency else {
            completion(.success(0))
            return
        }

        guard !isWorking, pendingPlan == nil else {
            completion(.failure(.busy))
            return
        }

        // Transactions still arriving from iCloud would miss the change, as with restoring a backup.
        guard dataController.isDataCurrentWithICloud else {
            completion(.failure(.waitingForICloud))
            return
        }

        let affected = (try? MainCurrencyChanger.count(plan, in: dataController.container.viewContext)) ?? -1
        logger.notice("Changing the main currency from \(plan.oldCurrency, privacy: .public) to \(plan.newCurrency, privacy: .public) (\(plan.kind.rawValue, privacy: .public)): \(affected) transactions to change")

        guard affected != 0 else {
            finish(plan, changed: 0)
            completion(.success(0))
            return
        }

        isWorking = true

        backupManager.backUpNow { [weak self] succeeded in
            guard let self else {
                return
            }

            guard succeeded else {
                self.isWorking = false
                self.logger.error("Not changing the main currency: backing up first failed")
                completion(.failure(.backupFailed))
                return
            }

            if let data = try? JSONEncoder().encode(plan) {
                self.defaults?.set(data, forKey: Self.pendingPlanKey)
            }

            self.run(plan, completion: completion)
        }
    }

    func resumeIfNeeded() {
        guard let plan = pendingPlan, !isWorking, dataController.isDataCurrentWithICloud else {
            return
        }

        logger.notice("Resuming the change of the main currency from \(plan.oldCurrency, privacy: .public) to \(plan.newCurrency, privacy: .public)")
        run(plan, completion: nil)
    }

    private func run(_ plan: MainCurrencyChangePlan, completion: ((Result<Int, ChangeError>) -> Void)?) {
        isWorking = true
        let context = dataController.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        context.perform { [logger] in
            // Sync and recurring transactions can add matching rows while a pass runs, and the main currency
            // must not move on while any are left.
            let result = Result { () throws -> Int in
                var changed = 0

                for _ in 0 ..< 3 {
                    changed += try MainCurrencyChanger.apply(plan, in: context)

                    if try MainCurrencyChanger.count(plan, in: context) == 0 {
                        return changed
                    }
                }

                throw MainCurrencyChanger.ChangeError.notConverging
            }

            DispatchQueue.main.async {
                self.isWorking = false

                switch result {
                case let .success(changed):
                    logger.notice("Changed the currency of \(changed) transactions")
                    self.finish(plan, changed: changed)
                    completion?(.success(changed))
                case let .failure(error):
                    logger.error("Changing the main currency stopped and will resume: \(String(describing: error), privacy: .public)")
                    completion?(.failure(.failed))
                }
            }
        }
    }

    private func finish(_ plan: MainCurrencyChangePlan, changed: Int) {
        defaults?.set(plan.newCurrency, forKey: "currency")
        NSUbiquitousKeyValueStore.default.set(plan.newCurrency, forKey: "currency")

        // After relabelling, the old code no longer means anything the user spends in.
        let recent = CurrencyPreferences.recentCurrencies(in: defaults).filter { plan.kind == .convert || $0 != plan.oldCurrency }
        defaults?.set(CurrencyPreferences.recording(plan.newCurrency, in: recent), forKey: CurrencyPreferences.recentCurrenciesKey)

        defaults?.removeObject(forKey: Self.pendingPlanKey)
        logger.notice("The main currency is now \(plan.newCurrency, privacy: .public); \(changed) transactions changed")

        dataController.objectWillChange.send()
        dataController.refreshExchangeRates()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
