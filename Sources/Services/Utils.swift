import Foundation
import CryptoKit
import os.log
import XCTest



enum Utils {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "Utils")

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
            logger.error("Error: Could not convert string to UTF8 data for hashing.")
            return value 
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined().uppercased()
    }
    
    /// Generates external key in format "scheme/testClass/testMethod" for XCTestCase
    static func genExternalKey(from testCase: XCTestCase, originalTestName: String) -> String {
        // Get scheme/target name from bundle
        let bundle = Bundle(for: type(of: testCase))
        var schemeName = bundle.bundleIdentifier ?? "UnknownScheme"
        // if schemeName contains ".", take only the part after the first "."
        schemeName = schemeName.components(separatedBy: ".").last ?? schemeName

        // Get test class name
        let className = String(describing: type(of: testCase))
        
        // Get test method name (testCase.name contains the full method name)
        var methodName = originalTestName
        // if methodName contains "-[\(className) ", take only the part after it and remove the "]"
        methodName = methodName.components(separatedBy: "-[\(className) ").last?.replacingOccurrences(of: "]", with: "") ?? methodName

        // Combine all parts with '/' separator
        return "\(schemeName)/\(className)/\(methodName)"
    }
}
