import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / Touch ID / passcode lock.
@MainActor
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var lastError: String?

    init(enabled: Bool) {
        isLocked = enabled
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode".
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lock() {
        isLocked = true
    }

    func disable() {
        isLocked = false
    }

    /// Asks for Face ID (falling back to the device passcode). Returns true on success.
    @discardableResult
    func authenticate(reason: String = "Unlock to see your budget") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device: nothing to protect with, so don't lock the user out.
            isLocked = false
            lastError = "Set a passcode on your iPhone to use the app lock."
            return true
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isLocked = false
                lastError = nil
            }
            return success
        } catch {
            lastError = nil
            return false
        }
    }
}
