import Foundation
import PipCore

enum PipRuntime {
    static func store() -> CredentialStore {
        let location = PipKeychainLocation.from(infoDictionary: Bundle.main.infoDictionary ?? [:])
        return CredentialStore(
            keychain: SecurityKeychain(service: location.service, accessGroup: location.accessGroup)
        )
    }

    static var source: ShareSource {
        #if os(iOS)
        .ios
        #else
        .macos
        #endif
    }
}
