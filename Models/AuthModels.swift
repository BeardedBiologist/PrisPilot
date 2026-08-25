import Foundation

struct AuthUser: Equatable {
    let id: String
    var email: String?
    var displayName: String?
    var createdAt: Date

    var initials: String {
        if let name = displayName, !name.isEmpty {
            let words = name.split(separator: " ")
            return words.compactMap { $0.first.map(String.init) }.prefix(2).joined().uppercased()
        }
        return email?.prefix(1).uppercased() ?? "?"
    }
}

enum AuthState: Equatable {
    case unknown
    case signedOut
    case signedIn(AuthUser)

    var user: AuthUser? {
        if case .signedIn(let u) = self { return u }
        return nil
    }

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
