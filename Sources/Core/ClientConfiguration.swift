import Foundation
import os.log

struct ClientConfiguration: Codable { // Add Codable conformance
    private let privateToken_: String // Private backing property
    let projectId: String
    let url: String
    let configurationId: String
    var testRunId: String 
    let testRunName: String
    let certValidation: Bool
    var automaticUpdationLinksToTestCases: Bool
    let mode: String

    // Public computed property for token access
    var privateToken: String {
        return privateToken_
    }

    // Initializer from properties dictionary
    init(properties: [String: String]) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "ClientConfiguration")
        logger.debug("Initializing ClientConfiguration from properties: \(properties)")

        // Extract values using AppProperties keys, providing defaults similar to Kotlin
        let rawToken = properties[AppProperties.PRIVATE_TOKEN] ?? "null"
        self.privateToken_ = (rawToken.lowercased() == "null") ? "" : rawToken // Store empty if "null"

        self.projectId = properties[AppProperties.PROJECT_ID] ?? "null"
        self.url = Utils.urlTrim(properties[AppProperties.URL] ?? "null") // Use Utils.urlTrim
        self.configurationId = properties[AppProperties.CONFIGURATION_ID] ?? "null"
        self.testRunId = properties[AppProperties.TEST_RUN_ID] ?? "null"
        self.testRunName = properties[AppProperties.TEST_RUN_NAME] ?? "null"
        self.mode = properties[AppProperties.ADAPTER_MODE] ?? "null"

        // Parse certValidation, defaulting to true
        let certValidationStr = properties[AppProperties.CERT_VALIDATION] ?? "true" // Default to "true" if null
        self.certValidation = (certValidationStr.lowercased() == "true")

        // Parse automaticUpdationLinksToTestCases, defaulting to false
        let autoUpdateLinksStr = properties[AppProperties.AUTOMATIC_UPDATION_LINKS_TO_TEST_CASES] ?? "false" // Default to "false" if null
        self.automaticUpdationLinksToTestCases = (autoUpdateLinksStr.lowercased() == "true")
        
        // Construct description manually to avoid capturing mutating self in logger's closure
        let descriptionString = "ClientConfiguration(" +
                                 "url='\(self.url)\', " +
                                 "privateToken=\'**********\', " + // Mask token
                                 "projectId=\'\(self.projectId)\', " +
                                 "configurationId=\'\(self.configurationId)\', " +
                                 "testRunId=\'\(self.testRunId)\', " +
                                 "testRunName=\'\(self.testRunName)\', " +
                                 "certValidation=\(self.certValidation), " +
                                 "automaticUpdationLinksToTestCases=\(self.automaticUpdationLinksToTestCases)" +
                                 "mode=\(self.mode)" +
                                 ")"
        logger.debug("Initialized ClientConfiguration instance: \(descriptionString)")
    }
    
    // Remove the default init() as it's no longer represented in the Kotlin code
    // init() { ... }

    // MARK: - Codable Implementation (handling private property)
    enum CodingKeys: String, CodingKey {
        // Map public names, use private name for token's backing property
        case privateToken_ = "privateToken"
        case projectId, url, configurationId, testRunId, testRunName, certValidation, automaticUpdationLinksToTestCases, mode
    }
    
    // Custom Encoder if needed to mask token, otherwise default is fine
    // Custom Decoder needed if privateToken_ needs specific handling
}

// MARK: - CustomStringConvertible
extension ClientConfiguration: CustomStringConvertible {
    var description: String {
        return "ClientConfiguration(" +
               "url=\'\(url)\', " +
               "privateToken=\'**********\', " + // Mask token
               "projectId=\'\(projectId)\', " +
               "configurationId=\'\(configurationId)\', " +
               "testRunId=\'\(testRunId)\', " +
               "testRunName=\'\(testRunName)\', " +
               "certValidation=\(certValidation), " +
               "automaticUpdationLinksToTestCases=\(automaticUpdationLinksToTestCases)" +
               "mode=\(self.mode)" +
               ")"
    }
} 