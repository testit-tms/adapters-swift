import Foundation
import os.log

class ConfigManager {
    private let properties: [String: String]
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "ConfigManager")

    init(properties: [String: String]) {
        self.properties = properties
        Self.logger.debug("ConfigManager initialized with properties: \(properties)")
    }

    func getAdapterConfig() -> AdapterConfig {
        // Creates a new AdapterConfig instance using the properties
        return AdapterConfig(properties: self.properties)
    }

    func getClientConfiguration() -> ClientConfiguration {
        // Creates a new ClientConfiguration instance using the properties
        return ClientConfiguration(properties: self.properties)
    }
}
