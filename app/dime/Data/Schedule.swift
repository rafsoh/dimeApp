//
//  Schedule.swift
//  dime
//
//  Date math for recurring transactions and budget periods.
//  Foundation only, so it can be unit tested without Core Data (see Package.swift).
//

import Foundation

/// Recurrence of a transaction: `type` 1 = days, 2 = weeks, 3 = months; `coefficient` = how many of them.
enum RecurrenceRule {
    /// The next occurrence after `date`, or nil when the rule is invalid
    /// (unknown type, or an interval that would not move the date forward).
    static func nextDate(after date: Date, type: Int, coefficient: Int, calendar: Calendar = .current) -> Date? {
        guard coefficient > 0 else { return nil }

        let next: Date?
        switch type {
        case 1:
            next = calendar.date(byAdding: .day, value: coefficient, to: date)
        case 2:
            next = calendar.date(byAdding: .day, value: coefficient * 7, to: date)
        case 3:
            next = calendar.date(byAdding: .month, value: coefficient, to: date)
        default:
            next = nil
        }

        guard let next, next > date else { return nil }
        return next
    }
}

/// Budget periods: `type` 1 = day, 2 = week, 3 = month, 4 = year.
enum BudgetPeriod {
    /// Safety net so corrupt data can never spin forever (100 years of daily periods).
    static let maxSteps = 36_500

    /// End of the period that starts at `start`, or nil for an unknown type.
    static func end(of start: Date, type: Int, calendar: Calendar = .current) -> Date? {
        let end: Date?
        switch type {
        case 1:
            end = calendar.date(byAdding: .day, value: 1, to: start)
        case 2:
            end = calendar.date(byAdding: .day, value: 7, to: start)
        case 3:
            end = calendar.date(byAdding: .month, value: 1, to: start)
        case 4:
            end = calendar.date(byAdding: .year, value: 1, to: start)
        default:
            end = nil
        }

        guard let end, end > start else { return nil }
        return end
    }

    /// Moves `start` forward whole periods until the period contains `now`.
    /// Unknown types and periods already covering `now` are returned unchanged.
    static func currentStart(from start: Date, type: Int, now: Date = .now, calendar: Calendar = .current) -> Date {
        var current = start
        var steps = 0

        while let next = end(of: current, type: type, calendar: calendar), next <= now, steps < maxSteps {
            current = next
            steps += 1
        }

        return current
    }
}
