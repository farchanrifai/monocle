import Foundation
import OSLog

/// Operation names/counts only: never log notes, amounts, or category/card names.
enum BackendDiagnostics {
    static let logger = Logger(subsystem: "com.farchan.ankka", category: "Backend")
    static let signposter = OSSignposter(logger: logger)

    static func measure<T>(_ name: StaticString, count: Int = 0, _ operation: () throws -> T) rethrows -> T {
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID(), "records=\(count)")
        defer { signposter.endInterval(name, interval) }
        do { return try operation() }
        catch { logger.error("Backend operation failed"); throw error }
    }

    static func widgetPublicationFailed() { logger.error("Widget publication failed; durable ledger remains committed") }
}
