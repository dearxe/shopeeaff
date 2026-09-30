import Foundation
import Security

protocol AuthProvider: Sendable {
    func authorization() throws -> String?
}
struct KeychainAuthProvider: AuthProvider {
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "LinkAff.Backend",
         kSecAttrAccount as String: account]
    }
    func authorization() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else { throw StorageError.keychain(status) }
        return "Bearer \(secret)"
    }
    func save(_ secret: String) throws {
        var attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            attributes.merge(query) { _, new in new }
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw StorageError.keychain(inserted) }
        } else if status != errSecSuccess { throw StorageError.keychain(status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.keychain(status) }
    }
}
enum StorageError: Error, LocalizedError {
    case keychain(OSStatus)
    var errorDescription: String? { "ไม่สามารถเข้าถึงรหัสเชื่อมต่อใน Keychain ได้" }
}
@MainActor
final class LocalStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LinkAff", isDirectory: true)
    }
    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
    func read<T: Decodable>(_ type: T.Type, name: String, fallback: T) throws -> T {
        guard FileManager.default.fileExists(atPath: file(name).path) else { return fallback }
        return try JSONDecoder().decode(type, from: Data(contentsOf: file(name)))
    }
    func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file(name), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}
