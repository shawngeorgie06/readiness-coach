import AuthenticationServices
import Foundation

struct AppleCredential {
    let identityToken: String
    let fullName: String?
}

/// Extracts an identity token and Apple-provided first-time name.
enum AppleSignIn {
    static func credential(from authorization: ASAuthorization) -> AppleCredential? {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = apple.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return nil }

        let name = [apple.fullName?.givenName, apple.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return AppleCredential(identityToken: token, fullName: name.isEmpty ? nil : name)
    }
}
