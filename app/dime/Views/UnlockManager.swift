//
//  UnlockManager.swift
//  dime
//
//  Created by Rafael Soh on 15/9/22.
//

import Foundation
import StoreKit

class UnlockManager: NSObject, ObservableObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
    enum RequestState {
        case loading
        case loaded
        case failed
    }

    var canMakePayments: Bool {
        SKPaymentQueue.canMakePayments()
    }

    private enum StoreError: Error {
        case invalidIdentifiers, missingProduct
    }

    @Published var requestState = RequestState.loading
    @Published var purchaseCount: Int
    @Published var failedTransaction = false

    private let dataController: DataController
    private let productIDs: Set<String> = ["com.rafaelsoh.dime.smalltip", "com.rafaelsoh.dime.mediumtip", "com.rafaelsoh.dime.largetip"]
    private var request: SKProductsRequest?

    var loadedProducts = [SKProduct]()

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        DispatchQueue.main.async { [self] in
            for transaction in transactions {
                switch transaction.transactionState {
                case .purchased, .restored:

                    self.purchaseCount += 1
                    self.dataController.tipCounter = purchaseCount
                    queue.finishTransaction(transaction)

                case .failed:
                    self.failedTransaction = true
                    queue.finishTransaction(transaction)
                    revertBool()
                default:
                    break
                }
            }
        }
    }

    func productsRequest(_: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.request = nil
            self.loadedProducts = response.products

            if response.invalidProductIdentifiers.isEmpty == false {
                print("ALERT: Received invalid product identifiers: \(response.invalidProductIdentifiers)")
            }

            self.requestState = self.loadedProducts.isEmpty ? .failed : .loaded
        }
    }

    func request(_: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            print("ALERT: Failed to load products: \(error.localizedDescription)")
            self.request = nil
            self.requestState = .failed
        }
    }

    func loadProductsIfNeeded() {
        guard requestState != .loaded, request == nil else { return }

        requestState = .loading
        let request = SKProductsRequest(productIdentifiers: productIDs)
        request.delegate = self
        self.request = request
        request.start()
    }

    func buy(product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    func revertBool() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.failedTransaction = false
        }
    }

    func restore() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    init(dataController: DataController) {
        // Store the data controller we were sent.
        self.dataController = dataController

        // This is required because we inherit from NSObject.
        purchaseCount = dataController.tipCounter

        super.init()

        // Start watching the payment queue.
        SKPaymentQueue.default().add(self)

        loadProductsIfNeeded()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }
}
