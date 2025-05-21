import Foundation



struct AdapterConfig: Codable {
    // private(set) allows setting within the struct (e.g., in init) 
    // but read-only access from outside.
    private(set) var mode: AdapterMode = .useFilter
    var automaticCreationTestCases: Bool = false
    var tmsIntegration: Bool = true

    // CodingKeys for Decodable conformance
    private enum CodingKeys: String, CodingKey {
        case mode
        case automaticCreationTestCases
        case tmsIntegration
    }

    // Manual Decodable initializer
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode mode, falling back to default if missing or invalid
        self.mode = (try? container.decodeIfPresent(AdapterMode.self, forKey: .mode)) ?? .useFilter
        // Decode booleans, falling back to defaults if missing
        self.automaticCreationTestCases = (try? container.decodeIfPresent(Bool.self, forKey: .automaticCreationTestCases)) ?? false
        self.tmsIntegration = (try? container.decodeIfPresent(Bool.self, forKey: .tmsIntegration)) ?? true
    }

    // Initializer to load from a dictionary (e.g., from environment variables or a config file)
    init(properties: [String: String]) {
        // Load mode
        if let modeValueString = properties[AppProperties.ADAPTER_MODE],
           let modeValueInt = Int(modeValueString),
           let parsedMode = AdapterMode(rawValue: modeValueInt) {
            self.mode = parsedMode
        } else {
            self.mode = .useFilter // Default value on error or missing key
        }

        // Load automaticCreationTestCases
        if let creationValue = properties[AppProperties.AUTOMATIC_CREATION_TEST_CASES] {
            self.automaticCreationTestCases = (creationValue.lowercased() == "true")
        } else {
            self.automaticCreationTestCases = false // Default value
        }

        // Load tmsIntegration
        if let integrationValue = properties[AppProperties.TMS_INTEGRATION] {
            // Enable unless explicitly set to "false"
            self.tmsIntegration = (integrationValue.lowercased() != "false")
        } else {
            self.tmsIntegration = true // Default value
        }
    }
    
    // Default initializer if no properties are provided
    init() {
        self.mode = .useFilter
        self.automaticCreationTestCases = false
        self.tmsIntegration = true
    }

    // Provide computed properties instead of get/should methods for Swift style
    var shouldAutomaticCreationTestCases: Bool {
        return automaticCreationTestCases
    }

    var shouldEnableTmsIntegration: Bool {
        return tmsIntegration
    }
}

extension AdapterConfig: CustomStringConvertible {
    var description: String {
        var builder = "class AdapterConfig {\n"
        builder += "    mode: \(self.mode)\n"
        builder += "    automaticCreationTestCases: \(self.automaticCreationTestCases)\n"
        builder += "    tmsIntegration: \(self.tmsIntegration)\n"
        builder += "}"
        return builder
    }
} 