//
//  MoneySummingEquivalenceTests.swift
//  dimeTests
//

import CoreData
@testable import dime
import XCTest

// Every total now goes through CurrencyConverter. With amounts that have no currency or the main one, each
// must give exactly what the code it replaced gave; that code is kept below as `legacy…`.
final class MoneySummingEquivalenceTests: XCTestCase {
    private let dataController = DataController.shared
    private var inserted: [NSManagedObject] = []
    private var category: dime.Category!

    override func setUpWithError() throws {
        let context = dataController.container.viewContext
        let mainCurrency = CurrencyConverter.mainCurrency(in: UserDefaults(suiteName: CurrencyConverter.appGroup))
        let amounts = [0.1, 0.2, 0.3, 1_234_567.89, 4.5, 1e-7, 99_999_999.99, 19.99, 0.07, 3]

        category = Category(context: context)
        category.id = UUID()
        category.name = "Equivalence"
        category.emoji = "🧮"
        category.order = 99
        inserted.append(category)

        for index in 0 ..< 240 {
            let transaction = Transaction(context: context)
            transaction.id = UUID()
            transaction.amount = amounts[index % amounts.count] * Double(index % 7 + 1)
            transaction.currencyCode = index % 3 == 0 ? mainCurrency : nil
            transaction.income = index % 4 == 0
            transaction.date = Date.now.addingTimeInterval(-Double(index) * 37_000 - 60)
            transaction.day = Calendar.current.startOfDay(for: transaction.wrappedDate)
            transaction.month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: transaction.wrappedDate))
            transaction.category = index % 2 == 0 ? category : nil
            inserted.append(transaction)
        }

        let start = Calendar.current.date(byAdding: .day, value: -20, to: Date.now)
        let mainBudget = MainBudget(context: context)
        mainBudget.amount = 1_800.25
        mainBudget.type = 3
        mainBudget.startDate = start
        inserted.append(mainBudget)

        let budget = Budget(context: context)
        budget.id = UUID()
        budget.amount = 320.4
        budget.type = 3
        budget.startDate = start
        budget.category = category
        inserted.append(budget)

        try context.save()
    }

    override func tearDownWithError() throws {
        let context = dataController.container.viewContext
        inserted.forEach(context.delete)
        inserted = []
        try context.save()
    }

    func testLogTotalsAreUnchanged() {
        for type in 1 ... 5 {
            XCTAssertEqual(dataController.getLogViewTotalSpent(type: type).bitPattern, dataController.legacyGetLogViewTotalSpent(type: type).bitPattern)
            XCTAssertEqual(dataController.getLogViewTotalIncome(type: type).bitPattern, dataController.legacyGetLogViewTotalIncome(type: type).bitPattern)
            XCTAssertEqual(dataController.getLogViewTotalNet(type: type).value.bitPattern, dataController.legacyGetLogViewTotalNet(type: type).value.bitPattern)
            XCTAssertEqual(dataController.getLogViewTotalNet(type: type).positive, dataController.legacyGetLogViewTotalNet(type: type).positive)
            XCTAssertTrue(dataController.logViewNetTotal(type: type).report.isComplete)
            XCTAssertFalse(dataController.logViewNetTotal(type: type).report.isApproximate)
        }
    }

    // The log header now loads its totals from one fetch on a background context.
    @MainActor
    func testLogSummaryFromABackgroundContextMatchesTheLogTotals() async {
        for type in 1 ... 5 {
            for lineGraph in [nil, 1, 2, 3] as [Int?] {
                let summary = await dataController.loadLogInsightsSummary(type: type, lineGraph: lineGraph)

                XCTAssertEqual(summary.net.value, dataController.logViewNetTotal(type: type).value, accuracy: 0.0001)
                XCTAssertEqual(summary.spent.value, dataController.getLogViewTotalSpent(type: type), accuracy: 0.0001)
                XCTAssertEqual(summary.income.value, dataController.getLogViewTotalIncome(type: type), accuracy: 0.0001)
                XCTAssertEqual(summary.net.report, dataController.logViewNetTotal(type: type).report)

                switch lineGraph {
                case 1: XCTAssertEqual(summary.lineGraph, dataController.getLineGraphDataNet(type: type))
                case 2: XCTAssertEqual(summary.lineGraph, dataController.getLineGraphData(income: true, type: type))
                case 3: XCTAssertEqual(summary.lineGraph, dataController.getLineGraphData(income: false, type: type))
                default: XCTAssertTrue(summary.lineGraph.isEmpty)
                }
            }
        }
    }

    func testShortcutInsightsAreUnchanged() {
        for type in 1 ... 3 {
            for timeframe in 1 ... 5 {
                for income in [nil, true, false] as [Bool?] {
                    for categories in [[], [category!]] {
                        XCTAssertEqual(
                            dataController.getShortcutInsights(type: type, timeframe: timeframe, optionalIncome: income, categories: categories).bitPattern,
                            dataController.legacyGetShortcutInsights(type: type, timeframe: timeframe, optionalIncome: income, categories: categories).bitPattern
                        )
                    }
                }
            }
        }
    }

    // Half the fixtures have no category; the breakdown must still account for every one of them.
    func testCategoryBreakdownIncludesUncategorised() {
        let converter = CurrencyConverter.current()
        let expenses = inserted.compactMap { $0 as? Transaction }.filter { !$0.income }
        let totals = InsightsCategoryTotal.make(from: expenses, using: converter)
        let uncategorised = totals.first { $0.slice == .uncategorised(income: false) }

        XCTAssertNotNil(uncategorised)
        XCTAssertEqual(uncategorised?.slice.name, Uncategorised.name)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.amount }, expenses.total(using: converter).value, accuracy: 0.01)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.share }, 1, accuracy: 0.0001)
    }

    func testLineGraphsAreUnchanged() {
        for type in 1 ... 4 {
            XCTAssertEqual(dataController.getLineGraphDataNet(type: type), dataController.legacyGetLineGraphDataNet(type: type))
            XCTAssertEqual(dataController.getLineGraphData(income: true, type: type), dataController.legacyGetLineGraphData(income: true, type: type))
            XCTAssertEqual(dataController.getLineGraphData(income: false, type: type), dataController.legacyGetLineGraphData(income: false, type: type))
        }
    }

    func testBudgetsAreUnchanged() throws {
        let mainBudget = try XCTUnwrap(inserted.compactMap { $0 as? MainBudget }.first)
        let budget = try XCTUnwrap(inserted.compactMap { $0 as? Budget }.first)

        XCTAssertEqual(dataController.getBudgetLeftover(overallBudget: mainBudget).bitPattern, dataController.legacyGetBudgetLeftover(overallBudget: mainBudget).bitPattern)
        XCTAssertEqual(dataController.getBudgetLeftover(budget: budget).bitPattern, dataController.legacyGetBudgetLeftover(budget: budget).bitPattern)

        let widget = dataController.fetchRequestForMainBudgetWidget()
        let legacyWidget = dataController.legacyFetchRequestForMainBudgetWidget()
        XCTAssertEqual(widget.totalSpent.bitPattern, legacyWidget.totalSpent.bitPattern)
        XCTAssertEqual(widget.budgetAmount, legacyWidget.budgetAmount)
    }

    func testInsightsAreUnchanged() {
        let calendar = Calendar(identifier: .gregorian)
        let starts = [
            (1, calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date.now))!),
            (1, calendar.date(byAdding: .day, value: -40, to: calendar.startOfDay(for: Date.now))!),
            (2, calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now))!),
            (2, calendar.date(byAdding: .month, value: -3, to: calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now))!)!),
            (3, calendar.date(from: calendar.dateComponents([.year], from: Date.now))!),
            (3, calendar.date(byAdding: .year, value: -1, to: calendar.date(from: calendar.dateComponents([.year], from: Date.now))!)!)
        ]

        for (type, date) in starts {
            for income in [true, false] {
                let new = dataController.getInsights(type: type, date: date, income: income)
                let old = dataController.legacyGetInsights(type: type, date: date, income: income)
                XCTAssertEqual(new.amount.bitPattern, old.amount.bitPattern)
                XCTAssertEqual(new.maximum.bitPattern, old.maximum.bitPattern)
                XCTAssertEqual(new.average.bitPattern, old.average.bitPattern)
                XCTAssertEqual(new.numberOfDays, old.numberOfDays)
                XCTAssertEqual(new.dates, old.dates)
                XCTAssertEqual(new.dateDictionary, old.dateDictionary)
                XCTAssertTrue(new.report.isComplete)
            }

            let summary = dataController.getInsightsSummary(type: type, date: date)
            let legacySummary = dataController.legacyGetInsightsSummary(type: type, date: date)
            XCTAssertEqual(summary.spent.bitPattern, legacySummary.spent.bitPattern)
            XCTAssertEqual(summary.income.bitPattern, legacySummary.income.bitPattern)
            XCTAssertEqual(summary.net.bitPattern, legacySummary.net.bitPattern)
            XCTAssertEqual(summary.average.bitPattern, legacySummary.average.bitPattern)
        }
    }

    func testTransactionTotalsMatchReduce() {
        let transactions = inserted.compactMap { $0 as? Transaction }
        let converter = CurrencyConverter.current()

        XCTAssertEqual(transactions.total(using: converter).value.bitPattern, transactions.reduce(0) { $0 + $1.amount }.bitPattern)
        XCTAssertEqual(transactions.total(using: converter, signed: true).value.bitPattern, dayTotalLegacy(transactions).bitPattern)
        XCTAssertEqual(dayTotal(dayTransaction: transactions).bitPattern, dayTotalLegacy(transactions).bitPattern)
    }

    private func dayTotalLegacy(_ transactions: [Transaction]) -> Double {
        var total = 0.0

        transactions.forEach { transaction in
            if transaction.income {
                total += transaction.amount
            } else {
                total -= transaction.amount
            }
        }

        return total
    }
}

private extension DataController {
    func legacyGetShortcutInsights(type: Int, timeframe: Int, optionalIncome: Bool?, categories: [dime.Category]) -> Double {
        let fetchRequest = fetchRequestForLogView(type: timeframe, optionalIncome: optionalIncome, categoryFilters: categories)
        let allTransactions = results(for: fetchRequest)

        if type == 1 {
            var total = 0.0

            allTransactions.forEach { transaction in
                if transaction.income {
                    total += transaction.amount
                } else {
                    total -= transaction.amount
                }
            }

            return total
        } else {
            var total = 0.0

            allTransactions.forEach { transaction in
                total += transaction.amount
            }

            return total
        }
    }

    func legacyGetLogViewTotalSpent(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: false)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func legacyGetLogViewTotalIncome(type: Int) -> Double {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: true)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            total += transaction.amount
        }

        return total
    }

    func legacyGetLogViewTotalNet(type: Int) -> (value: Double, positive: Bool) {
        let fetchRequest = fetchRequestForLogView(type: type, optionalIncome: nil)
        let allTransactions = results(for: fetchRequest)

        var total = 0.0

        allTransactions.forEach { transaction in
            if transaction.income {
                total += transaction.amount
            } else {
                total -= transaction.amount
            }
        }

        if total >= 0 {
            return (total, true)
        } else {
            return (abs(total), false)
        }
    }

    func legacyGetLineGraphDataNet(type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: nil)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate < changingDate {
                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                } else {
                    let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                    holdingDataPoints.append(newData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                    while transaction.wrappedDate > changingDate {
                        let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: totalForDay)
                        holdingDataPoints.append(anotherNewData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                    }

                    if transaction.income {
                        totalForDay += transaction.amount
                    } else {
                        totalForDay -= transaction.amount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: totalForDay)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func legacyGetLineGraphData(income: Bool, type: Int) -> [LineGraphDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)

        let fetchRequest = fetchRequestForLineGraph(optionalIncome: income)
        let transactions = results(for: fetchRequest)

        var holdingDataPoints = [LineGraphDataPoint]()
        var totalForDay = 0.0

        if type < 3 {
            let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastWeek)!

            for transaction in transactions {
                if transaction.wrappedDate > lastWeek {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)
            totalForDay = 0

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: totalForDay)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 3 {
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: today)!
            var changingDate = Calendar.current.date(byAdding: .second, value: 86399, to: lastMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > lastMonth {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let newData = LineGraphDataPoint(date: changingDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < today {
                changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!

                while changingDate < today {
                    let anotherNewData = LineGraphDataPoint(date: changingDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .day, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        } else if type == 4 {
            let dateComponents = calendar.dateComponents([.month, .year], from: Date.now)
            let thisMonth = calendar.date(from: dateComponents)!
            let thisMonthLastYear = calendar.date(byAdding: .year, value: -1, to: thisMonth)!
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: thisMonth)!
            var changingDate = calendar.date(byAdding: .year, value: -1, to: nextMonth)!

            for transaction in transactions {
                if transaction.wrappedDate > thisMonthLastYear {
                    if transaction.wrappedDate < changingDate {
                        totalForDay += transaction.wrappedAmount
                    } else {
                        let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                        let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
                        holdingDataPoints.append(newData)
                        changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        totalForDay = 0

                        while transaction.wrappedDate > changingDate {
                            let newDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                            let anotherNewData = LineGraphDataPoint(date: newDataDate, amount: 0)
                            holdingDataPoints.append(anotherNewData)
                            changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                        }

                        totalForDay += transaction.wrappedAmount
                    }
                }
            }

            let dataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
            let newData = LineGraphDataPoint(date: dataDate, amount: totalForDay)
            holdingDataPoints.append(newData)

            if changingDate < nextMonth {
                changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!

                while changingDate < nextMonth {
                    let anotherDataDate = calendar.date(byAdding: .day, value: -1, to: changingDate)!
                    let anotherNewData = LineGraphDataPoint(date: anotherDataDate, amount: 0)
                    holdingDataPoints.append(anotherNewData)
                    changingDate = Calendar.current.date(byAdding: .month, value: 1, to: changingDate)!
                }

                let finalDate = LineGraphDataPoint(date: today, amount: 0)
                holdingDataPoints.append(finalDate)
            }
        }

        return holdingDataPoints
    }

    func legacyGetBudgetLeftover(budget: Budget? = nil, overallBudget: MainBudget? = nil) -> Double {
        let itemRequest: NSFetchRequest<Transaction>
        let budgetAmount: Double

        if let unwrappedOverallBudget = overallBudget {
            itemRequest = fetchRequestForMainBudgetTransactions(budget: unwrappedOverallBudget)
            budgetAmount = unwrappedOverallBudget.amount
        } else if let unwrappedBudget = budget {
            itemRequest = fetchRequestForBudgetTransactions(budget: unwrappedBudget)
            budgetAmount = unwrappedBudget.amount
        } else {
            itemRequest = Transaction.fetchRequest()
            budgetAmount = 0
        }

        let transactions = results(for: itemRequest)

        var totalSpent = 0.0

        transactions.forEach { transaction in
            totalSpent += transaction.wrappedAmount
        }

        return budgetAmount - totalSpent
    }

    func legacyGetInsights(type: Int, date: Date, income: Bool) -> (amount: Double, maximum: Double, average: Double, numberOfDays: Int, dates: [Date], dateDictionary: [Date: Double]) {
        let currentItemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date, income: income)
        let currentTransactions = results(for: currentItemRequest)

        var iterativeDate = date

        if type == 1 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            // calendar initialization
            var calendar = Calendar(identifier: .gregorian)

            calendar.firstWeekday = UserDefaults(suiteName: "group.com.rafaelsoh.dime")!.integer(forKey: "firstWeekday")
            calendar.minimumDaysInFirstWeek = 4

            var dictionary = [Date: Double]()
            var totalForWeek = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var weekAverage = 0.0

            for _ in 1 ... 7 {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForWeek += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: Date.now)

            let currentWeek = calendar.date(from: dateComponents)!

            if currentWeek == date {
//                let fromDate = Calendar.current.startOfDay(for: currentWeek)
//                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numberOfDays = Calendar.current.dateComponents([.day], from: currentWeek, to: Date.now)

                weekAverage = totalForWeek / Double((numberOfDays.day! + 1))
            } else {
                weekAverage = totalForWeek / 7
            }

            return (totalForWeek, maximum, weekAverage, numberOfDays, dates, dictionary)
        } else if type == 2 {
            // tracking dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)
            let range = calendar.range(of: .day, in: .month, for: iterativeDate)!

            var dictionary = [Date: Double]()
            var totalForMonth = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... range.count {
                nextDate = calendar.date(byAdding: .day, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForMonth += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                monthAverage = totalForMonth / Double((numDays.day! + 1))
            } else {
                monthAverage = totalForMonth / Double(range.count)
            }

            return (totalForMonth, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else if type == 3 {
            // trackin dates
            var dates = [Date]()
            var nextDate = date

            let calendar = Calendar(identifier: .gregorian)

            var dictionary = [Date: Double]()
            var totalForYear = 0.0
            var maximum = 0.0
            var numberOfDays = 0
            var monthAverage = 0.0

            for _ in 1 ... 12 {
                nextDate = calendar.date(byAdding: .month, value: 1, to: iterativeDate)!

                let holding = currentTransactions.filter {
                    $0.wrappedDate >= iterativeDate && $0.wrappedDate < nextDate
                }

                var total = 0.0

                holding.forEach { transaction in
                    total += transaction.wrappedAmount
                }

                totalForYear += total

                dictionary[iterativeDate] = total

                if total > maximum {
                    maximum = total
                }

                if total != 0 {
                    numberOfDays += 1
                }

                dates.append(iterativeDate)
                iterativeDate = nextDate
            }

            let dateComponents = calendar.dateComponents([.year], from: Date.now)

            let currentYear = calendar.date(from: dateComponents)!

            if currentYear == date {
                let fromDate = Calendar.current.startOfDay(for: currentYear)
                let toDate = Calendar.current.startOfDay(for: Date.now)
                let numDays = Calendar.current.dateComponents([.month], from: fromDate, to: toDate)

                monthAverage = totalForYear / Double((numDays.month! + 1))
            } else {
                monthAverage = totalForYear / 12
            }

            return (totalForYear, maximum, monthAverage, numberOfDays, dates, dictionary)
        } else {
            return (0, 0, 0, 0, [Date](), [Date: Double]())
        }
    }

    func legacyGetInsightsSummary(type: Int, date: Date) -> (spent: Double, income: Double, net: Double, positive: Bool, average: Double) {
        let itemRequest: NSFetchRequest<Transaction> = fetchRequestForInsights(type: type, date: date)
        let currentTransactions = results(for: itemRequest)

        var holdingSpent = 0.0
        var holdingIncome = 0.0

        currentTransactions.forEach { transaction in
            if transaction.income {
                holdingIncome += transaction.amount
            } else {
                holdingSpent += transaction.amount
            }
        }

        let net = holdingIncome - holdingSpent
        let absoluteNet: Double
        let positive: Bool

        if net < 0 {
            absoluteNet = abs(net)
            positive = false
        } else {
            absoluteNet = net
            positive = true
        }

        let calendar = Calendar.current

        if type == 1 {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .weekOfYear) {
                let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numberOfDays.day! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 7)
            }
        } else if type == 2 {
            let next = calendar.date(byAdding: .month, value: 1, to: date) ?? Date.now

            if next > Date.now {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            } else {
                let numDays = Calendar.current.dateComponents([.day], from: date, to: next)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
            }
//            if calendar.isDate(date, equalTo: Date.now, toGranularity: .month) {
//                let numDays = Calendar.current.dateComponents([.day], from: date, to: Date.now)
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.day! + 1))
//            } else {
//
//                let range = calendar.range(of: .day, in: .month, for: date)!
//                let numDays = range.count
//
//                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays))
//            }
        } else {
            if calendar.isDate(date, equalTo: Date.now, toGranularity: .year) {
                let numDays = Calendar.current.dateComponents([.month], from: date, to: Date.now)

                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / Double(numDays.month! + 1))
            } else {
                return (holdingSpent, holdingIncome, absoluteNet, positive, abs(net) / 12)
            }
        }
    }

    func legacyFetchRequestForMainBudgetWidget() -> (found: Bool, totalSpent: Double, budgetAmount: Double, percentage: Double, type: Int, startDate: Date) {
        let holding = results(for: fetchRequestForMainBudget())

        if let budget = holding.first {
            let itemRequest = fetchRequestForMainBudgetTransactions(budget: budget)
//
            let transactions = results(for: itemRequest)

            var holdingTotal = 0.0
            transactions.forEach { transaction in
                holdingTotal += transaction.wrappedAmount
            }

            let percentageOfDays: Double

            let calendar = Calendar.current

            if budget.type == 1 {
                let components = calendar.dateComponents([.minute], from: budget.startDate!, to: Date.now)
                percentageOfDays = Double(components.minute!) / 1440
            } else {
                let components1 = calendar.dateComponents([.day], from: budget.startDate!, to: budget.endDate)
                let numberOfDays = components1.day!

                let components2 = calendar.dateComponents([.day], from: budget.startDate!, to: Date.now)
                let numberOfDaysPast = components2.day!

                percentageOfDays = Double(numberOfDaysPast) / Double(numberOfDays)
            }

            return (true, holdingTotal, budget.amount, percentageOfDays, Int(budget.type), budget.startDate!)

        } else {
            return (false, 0, 0, 0, 0, Date.now)
        }
    }
}
