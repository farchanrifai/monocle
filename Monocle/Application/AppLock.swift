import Foundation
import LocalAuthentication
import Observation

@MainActor
protocol DeviceAuthenticating {
    func authenticate(reason: String) async -> Result<Void, AppLockError>
}

@MainActor
final class DeviceAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Result<Void, AppLockError> {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .failure(.unavailable)
        }
        let authenticated = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        return authenticated ? .success(()) : .failure(.failed)
    }
}

enum AppLockError: LocalizedError, Equatable, Sendable {
    case unavailable
    case failed
    case settingsCouldNotSave(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Device authentication is unavailable. Set a device passcode before turning on app lock."
        case .failed: "Authentication was not completed."
        case let .settingsCouldNotSave(message): "Your app-lock preference could not be saved: \(message)"
        }
    }
}

/// Separates an app-switcher privacy shield from a real authentication requirement.
/// A quick return can therefore honour the selected grace period without exposing a snapshot.
@MainActor @Observable
final class AppLockController {
    private let authenticator: any DeviceAuthenticating
    private(set) var timeout: AppLockTimeout?
    private(set) var needsAuthentication: Bool
    private(set) var isAuthenticating = false
    private(set) var privacyShieldVisible = false
    private var suspendedAt: Date?

    init(timeout: AppLockTimeout?, authenticator: any DeviceAuthenticating = DeviceAuthenticator()) {
        self.timeout = timeout
        self.authenticator = authenticator
        needsAuthentication = timeout != nil
    }

    var blocksContent: Bool { privacyShieldVisible || needsAuthentication }

    func suspend(now: Date = .now) {
        guard timeout != nil else { return }
        suspendedAt = now
        privacyShieldVisible = true
    }

    func resume(now: Date = .now) {
        guard let timeout else { return }
        privacyShieldVisible = false
        guard let suspendedAt else { return }
        if now.timeIntervalSince(suspendedAt) >= timeout.interval { needsAuthentication = true }
        self.suspendedAt = nil
    }

    func unlock() async -> Result<Void, AppLockError> {
        guard timeout != nil else { return .success(()) }
        guard !isAuthenticating else { return .failure(.failed) }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: "Unlock your spending records.")
        isAuthenticating = false
        if case .success = result { needsAuthentication = false }
        return result
    }

    func enable(timeout: AppLockTimeout) async -> Result<Void, AppLockError> {
        guard !isAuthenticating else { return .failure(.failed) }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: "Confirm app lock for your spending records.")
        isAuthenticating = false
        if case .success = result {
            self.timeout = timeout
            needsAuthentication = false
            privacyShieldVisible = false
            suspendedAt = nil
        }
        return result
    }

    func disable() {
        timeout = nil
        needsAuthentication = false
        privacyShieldVisible = false
        suspendedAt = nil
    }

    func restorePersistedConfiguration(_ timeout: AppLockTimeout?) {
        self.timeout = timeout
        needsAuthentication = false
        privacyShieldVisible = false
        suspendedAt = nil
    }
}
