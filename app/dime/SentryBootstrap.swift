//
//  SentryBootstrap.swift
//  dime
//
//  Starts Sentry before the persistent store loads. Debug builds and unit tests do not send events.
//

import Foundation
import Sentry

enum SentryBootstrap {
    /// Public client DSN. An auth token is not part of this value and must not be committed.
    static let dsn = "https://5fdecbeabf0c674b906c7205c6160707@o4512495284846592.ingest.us.sentry.io/4512495286812672"

    private static let keptAutomaticBreadcrumbCategories: Set<String> = [
        "app.lifecycle",
        "device.event",
        "ui.lifecycle"
    ]

    static func start() {
        // Hosted tests launch the app. Leave the SDK uninitialized so swizzling stays out of the suite.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            options.sendDefaultPii = false
            options.enableScopePersistence = false
            options.initialScope = { scope in
                scope.setUser(nil)
                return scope
            }

            let bundle = Bundle.main
            let identifier = bundle.bundleIdentifier ?? "com.rafaelsoh.dime"
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            options.releaseName = "\(identifier)@\(version)+\(build)"

            #if DEBUG
            // Debug launches stay off so local development does not consume the free event quota.
            options.enabled = false
            options.environment = "debug"
            #else
            options.enabled = true
            options.environment = "production"
            #endif

            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2
            options.enableWatchdogTerminationTracking = true
            options.enablePersistingTracesWhenCrashing = true
            options.tracesSampleRate = NSNumber(value: 0.1)
            options.enableAutoPerformanceTracing = true
            options.enableUIViewControllerTracing = true
            options.enableSwizzling = true

            // Screenshots, view hierarchies, and session replay contain amounts, notes, and names.
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.beforeCaptureScreenshot = { _ in false }
            options.beforeCaptureViewHierarchy = { _ in false }
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0

            // These automatic integrations copy user-entered text into spans or breadcrumbs:
            // Core Data predicates, file paths, network bodies, and control labels.
            options.enableUserInteractionTracing = false
            options.enableCoreDataTracing = false
            options.enableFileIOTracing = false
            options.enableDataSwizzling = false
            options.enableFileManagerSwizzling = false
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false

            options.beforeBreadcrumb = { crumb in
                scrub(breadcrumb: crumb)
            }
            options.beforeSend = { event in
                scrub(event: event)
            }
        }

        DataIntegrityLog.flushPending()
    }

    static func scrub(event: Event) -> Event {
        event.user = nil
        event.request = nil
        event.serverName = nil

        if var context = event.context {
            for (section, values) in context {
                var values = values
                for key in ["name", "id", "vendor_id", "device_app_hash", "email", "username", "ip_address"] {
                    values.removeValue(forKey: key)
                }
                context[section] = values
            }
            context.removeValue(forKey: "User Interaction")
            context.removeValue(forKey: "view_hierarchy")
            event.context = context
        }

        event.breadcrumbs = event.breadcrumbs?.compactMap { scrub(breadcrumb: $0) }
        return event
    }

    static func scrub(breadcrumb crumb: Breadcrumb) -> Breadcrumb? {
        if crumb.category == "data.integrity" {
            return crumb
        }

        guard keptAutomaticBreadcrumbCategories.contains(crumb.category) else {
            return nil
        }

        if let message = crumb.message, !isSafeAutomaticMessage(message) {
            return nil
        }

        if let keys = crumb.data?.keys {
            for key in Array(keys) {
                crumb.setData(value: nil, key: key)
            }
        }
        return crumb
    }

    /// View-controller class names and lifecycle words. Digits and quotes are rejected so a label
    /// that includes an amount or a note cannot ride along.
    private static func isSafeAutomaticMessage(_ message: String) -> Bool {
        guard message.count <= 180 else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._ <>:-")
        return message.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
