import Foundation
import CryptoKit


enum Utils {
    static func genExternalID(_ fullName: String) -> String {
        return getHash(fullName)
    }

    // --- String/Formatting Methods ---

    static func toIndentedString(_ o: Any?) -> String {
        guard let obj = o else { return "null" }
        // Use Swift's String interpolation and description
        return String(describing: obj).replacingOccurrences(of: "\n", with: "\n    ")
    }

    static func urlTrim(_ url: String) -> String {
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    // --- Hashing Methods ---

    static func getHash(_ value: String) -> String {
        guard let data = value.data(using: .utf8) else {
            print("Error: Could not convert string to UTF8 data for hashing.")
            return value 
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined().uppercased()
    }
}