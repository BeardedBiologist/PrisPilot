import Foundation
import Observation
import AuthenticationServices

@Observable
@MainActor
final class AuthStore {
    var state: AuthState = .unknown
    var signInError: String?

    static let shared = AuthStore()

    private let userIDKey    = "auth.apple.userID"
    private let userEmailKey = "auth.apple.email"
    private let userNameKey  = "auth.apple.displayName"

    private init() {}

    // Called on app launch to restore a previous session.
    func checkExistingCredential() async {
        guard let savedID = UserDefaults.standard.string(forKey: userIDKey) else {
            state = .signedOut
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            provider.getCredentialState(forUserID: savedID) { credState, _ in
                cont.resume(returning: credState)
            }
        }
        if credentialState == .authorized {
            state = .signedIn(restoredUser(id: savedID))
        } else {
            clearSaved()
            state = .signedOut
        }
    }

    // Called from SignInWithAppleButton onCompletion on success.
    func handleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let nameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { part -> String? in
                guard let p = part, !p.isEmpty else { return nil }
                return p
            }
        let displayName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

        UserDefaults.standard.set(credential.user, forKey: userIDKey)
        // Apple only sends email and full name on the very first sign-in.
        // Persist whatever we receive so subsequent launches can restore it.
        if let email = credential.email { UserDefaults.standard.set(email, forKey: userEmailKey) }
        if let name = displayName { UserDefaults.standard.set(name, forKey: userNameKey) }

        state = .signedIn(restoredUser(id: credential.user))
        signInError = nil
    }

    // Called from SignInWithAppleButton onCompletion on failure.
    func handleSignInError(_ error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
        signInError = error.localizedDescription
    }

    func signOut() {
        clearSaved()
        state = .signedOut
        signInError = nil
    }

#if DEBUG
    // Bypasses real Apple Sign-In for UI development without the entitlement.
    func signInWithMockAccount() {
        let id = "mock.debug.user"
        UserDefaults.standard.set(id, forKey: userIDKey)
        UserDefaults.standard.set("dev@prispilot.no", forKey: userEmailKey)
        UserDefaults.standard.set("Dev User", forKey: userNameKey)
        state = .signedIn(restoredUser(id: id))
        signInError = nil
    }
#endif

    private func restoredUser(id: String) -> AuthUser {
        AuthUser(
            id: id,
            email: UserDefaults.standard.string(forKey: userEmailKey),
            displayName: UserDefaults.standard.string(forKey: userNameKey),
            createdAt: Date()
        )
    }

    private func clearSaved() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
    }
}
