import Foundation
import os.log // Using os.log for better logging than print

// Using an enum to encapsulate property loading logic and constants
enum AppProperties {

    // MARK: - Property Keys
    static let URL = "url"
    static let PRIVATE_TOKEN = "privateToken"
    static let PROJECT_ID = "projectId"
    static let CONFIGURATION_ID = "configurationId"
    static let TEST_RUN_ID = "testRunId"
    static let TEST_RUN_NAME = "testRunName"
    static let ADAPTER_MODE = "adapterMode"
    static let AUTOMATIC_CREATION_TEST_CASES = "automaticCreationTestCases"
    static let AUTOMATIC_UPDATION_LINKS_TO_TEST_CASES = "automaticUpdationLinksToTestCases"
    static let CERT_VALIDATION = "certValidation"
    static let TMS_INTEGRATION = "testIt" // Key for enabling/disabling integration

    static let PROPERTIES_FILE = "testit.properties"
    static let TMS_CONFIG_FILE_ENV_VAR = "TMS_CONFIG_FILE"
    
    // Define logger
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "AppProperties")

    // MARK: - Environment/CLI Variable Mappings
    private static let envVarsNames: [String: [String: String]] = [
        "env": [
            URL: "TMS_URL",
            PRIVATE_TOKEN: "TMS_PRIVATE_TOKEN",
            PROJECT_ID: "TMS_PROJECT_ID",
            CONFIGURATION_ID: "TMS_CONFIGURATION_ID",
            TEST_RUN_ID: "TMS_TEST_RUN_ID",
            TEST_RUN_NAME: "TMS_TEST_RUN_NAME",
            ADAPTER_MODE: "TMS_ADAPTER_MODE",
            AUTOMATIC_CREATION_TEST_CASES: "TMS_AUTOMATIC_CREATION_TEST_CASES",
            CERT_VALIDATION: "TMS_CERT_VALIDATION",
            TMS_INTEGRATION: "TMS_TEST_IT"
        ],
        "cli": [
            URL: "tmsUrl",
            PRIVATE_TOKEN: "tmsPrivateToken",
            PROJECT_ID: "tmsProjectId",
            CONFIGURATION_ID: "tmsConfigurationId",
            TEST_RUN_ID: "tmsTestRunId",
            TEST_RUN_NAME: "tmsTestRunName",
            ADAPTER_MODE: "tmsAdapterMode",
            AUTOMATIC_CREATION_TEST_CASES: "tmsAutomaticCreationTestCases",
            CERT_VALIDATION: "tmsCertValidation",
            TMS_INTEGRATION: "tmsTestIt"
        ]
    ]

    public static private(set) var configuration: [String: String]? // Пример: словарь


    // Вариант 1: Метод для инициализации из конкретного бандла
    public static func initialize(from bundle: Bundle) {
        guard configuration == nil else { return } // Инициализируем только один раз

        guard let propertiesURL = bundle.url(forResource: PROPERTIES_FILE.deletingPathExtension, // "testit"
                                             withExtension: PROPERTIES_FILE.pathExtension) else { // "properties"
            print("AppProperties: Файл \(PROPERTIES_FILE) не найден в бандле: \(bundle.bundleIdentifier ?? "N/A")")
            // Возможно, установить дефолтную конфигурацию или выбросить ошибку
            configuration = [:] // Или nil
            return
        }

        do {
            let propertiesContent = try String(contentsOf: propertiesURL, encoding: .utf8)
            print("AppProperties: Конфигурация успешно загружена из \(propertiesURL.path)")
            // Здесь парсинг propertiesContent в словарь configuration
            // TODO: Реализовать парсинг .properties файла
            configuration = loadPropertiesFromString(content: propertiesContent) // Замените на реальный парсер
        } catch {
            print("AppProperties: Ошибка чтения файла \(PROPERTIES_FILE): \(error)")
            configuration = [:] // Или nil
        }
    }

    public static func initialize(propertiesString: String) {
         guard configuration == nil else { return }
         print("AppProperties: Инициализация из переданной строки.")
         // Здесь парсинг propertiesString в словарь configuration
        configuration = loadPropertiesFromString(content: propertiesString) // Замените на реальный парсер
    }

    // MARK: - Loading Logic
    static func loadProperties() -> [String: String] {
        
        var properties: [String: String] = configuration!
  
  
        let initialToken = properties[PRIVATE_TOKEN]
        if let token = initialToken, !token.isEmpty, token.lowercased() != "null" {
            // logger.warning("The configuration file specifies a private token. It is not safe. Use TMS_PRIVATE_TOKEN environment variable")
        }

        // 2. Load from Environment Variables (using env mapping)
        let envProperties = ProcessInfo.processInfo.environment
        if let envVarMap = envVarsNames["env"] {
             properties.merge(loadPropertiesFromSource(source: envProperties, mapping: envVarMap)) { (_, new) in new }
        }
       
        // 3. Load from Command Line Arguments (placeholder using cli mapping)
        // Full CLI parsing requires a library or manual parsing of CommandLine.arguments.
        // This example simulates loading if they were pre-parsed into a dictionary.
        let cliArgs = parseCommandLineArgs() // Placeholder function
        if let cliVarMap = envVarsNames["cli"] {
            properties.merge(loadPropertiesFromSource(source: cliArgs, mapping: cliVarMap)) { (_, new) in new }
        }

        // 4. Validate properties if TMS integration is enabled
        if properties[TMS_INTEGRATION]?.lowercased() != "false" {
            return validateProperties(properties)
        } else {
            logger.info("TMS integration is disabled via '\(TMS_INTEGRATION)' property.")
            return properties // Return unvalidated properties if integration is off
        }
    }

    // Placeholder for CLI parsing - replace with actual implementation
    private static func parseCommandLineArgs() -> [String: String] {
        logger.debug("Command line argument parsing is not fully implemented in this translation.")
        // Example: Check CommandLine.arguments or use a library like Swift Argument Parser
        return [:] 
    }

    // Assumes simple key=value format, one per line. Comments (# or !) ignored.
    private static func loadPropertiesFromString(content: String) -> [String: String] {
        var properties: [String: String] = [:]
    
        
        let lines = content.split { $0.isNewline }
        
        logger.info("Loading properties from configuration")
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty || trimmedLine.starts(with: "#") || trimmedLine.starts(with: "!") {
                continue // Skip empty lines and comments
            }
            
            if let separatorIndex = trimmedLine.firstIndex(of: "=") {
                let key = String(trimmedLine[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmedLine[trimmedLine.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                     // Only set if value is not empty, merging strategy prefers later sources
                    if properties[key] == nil {
                         properties[key] = value
                    }
                }
            }
        }
        
        return properties
    }

    // Generic helper to load properties from a source dictionary using a key mapping
    private static func loadPropertiesFromSource(source: [String: String], mapping: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        
        for (propKey, sourceKey) in mapping {
            guard let value = source[sourceKey], !value.isEmpty, value.lowercased() != "null" else {
                continue
            }

            // Validate specific properties during loading from source
            switch propKey {
            case URL:
                if let _ = Foundation.URL(string: value) {
                    result[propKey] = value
                } else {
                     logger.warning("Ignoring invalid URL found in source for key '\(sourceKey)': \(value)")
                }
            case PRIVATE_TOKEN:
                result[propKey] = value // No format validation here
            case PROJECT_ID, CONFIGURATION_ID, TEST_RUN_ID:
                if let _ = UUID(uuidString: value) {
                    result[propKey] = value
                } else {
                    logger.warning("Ignoring invalid UUID found in source for key '\(sourceKey)': \(value)")
                }
            case ADAPTER_MODE:
                 if let intValue = Int(value), (0...2).contains(intValue) { // Assuming modes 0, 1, 2
                     result[propKey] = value
                 } else {
                     logger.warning("Ignoring invalid AdapterMode found in source for key '\(sourceKey)': \(value)")
                 }
             case AUTOMATIC_CREATION_TEST_CASES, AUTOMATIC_UPDATION_LINKS_TO_TEST_CASES, CERT_VALIDATION, TMS_INTEGRATION:
                 let lowerValue = value.lowercased()
                 if lowerValue == "true" || lowerValue == "false" {
                    result[propKey] = lowerValue
                 } else {
                      logger.warning("Ignoring invalid boolean value found in source for key '\(sourceKey)': \(value)")
                 }
            case TEST_RUN_NAME:
                 result[propKey] = value // No format validation here
            default:
                logger.warning("Unknown property key '\(propKey)' in mapping.")
            }
        }
        return result
    }

    // MARK: - Validation
    static func validateProperties(_ properties: [String: String]) -> [String: String] {
        var validatedProperties = properties // Work on a copy
        var errors: [String] = []
        logger.debug("Validating loaded properties...")

        // Validate URL (required)
        if let urlString = validatedProperties[URL] { 
            if Foundation.URL(string: urlString) == nil {
                 logger.error("Invalid URL: \(urlString)")
                 errors.append("Invalid URL: \(urlString)")
            }
        } else {
             logger.error("Missing required property: URL (\(URL))")
             errors.append("Missing required property: URL (\(URL))")
        }

        // Validate Token (required)
        let token = validatedProperties[PRIVATE_TOKEN]
        if token == nil || token!.isEmpty || token!.lowercased() == "null" {
            logger.error("Invalid or missing private token (\(PRIVATE_TOKEN)).")
            errors.append("Invalid or missing private token (\(PRIVATE_TOKEN)).")
        }

        // Validate Project ID (required)
        if let projId = validatedProperties[PROJECT_ID] {
            if UUID(uuidString: projId) == nil {
                logger.error("Invalid projectId: \(projId)")
                errors.append("Invalid projectId: \(projId)")
            }
        } else {
             logger.error("Missing required property: Project ID (\(PROJECT_ID))")
             errors.append("Missing required property: Project ID (\(PROJECT_ID))")
        }

        // Validate Configuration ID (required)
        if let configId = validatedProperties[CONFIGURATION_ID] {
            if UUID(uuidString: configId) == nil {
                 logger.error("Invalid configurationId: \(configId)")
                 errors.append("Invalid configurationId: \(configId)")
            }
        } else {
            logger.error("Missing required property: Configuration ID (\(CONFIGURATION_ID))")
            errors.append("Missing required property: Configuration ID (\(CONFIGURATION_ID))")
        }

        // Validate Adapter Mode and Test Run ID relationship
        let adapterModeStr = validatedProperties[ADAPTER_MODE]
        let adapterMode = Int(adapterModeStr ?? "0") ?? 0 // Default to 0 if invalid/missing
        if !(0...2).contains(adapterMode) {
             logger.warning("Invalid adapterMode: \(adapterModeStr ?? "nil"). Using default value: 0")
             validatedProperties[ADAPTER_MODE] = "0" // Correct invalid value
        }
        
        let testRunId = validatedProperties[TEST_RUN_ID]
        if let runId = testRunId { // If TestRunID exists
             if UUID(uuidString: runId) == nil { // And it's invalid...
                 if adapterMode == 0 || adapterMode == 1 { // Error only if mode requires it
                     logger.error("Invalid testRunId: \(runId)")
                     errors.append("Invalid testRunId: \(runId)")
                 }
             } else { // And it's valid...
                  if adapterMode == 2 { // Error if mode is 2 (should auto-create)
                     logger.error("Adapter works in mode 2. Config should not contain test run id (\(TEST_RUN_ID)).")
                     errors.append("Adapter works in mode 2. Config should not contain test run id (\(TEST_RUN_ID)).")
                 }
             }
        } else { // If TestRunID does NOT exist
             if adapterMode == 0 || adapterMode == 1 { // Error if mode requires it
                 logger.error("Missing required property for adapter mode \(adapterMode): Test Run ID (\(TEST_RUN_ID))")
                 errors.append("Missing required property for adapter mode \(adapterMode): Test Run ID (\(TEST_RUN_ID))")
            }
        }

        // Validate Booleans (provide defaults if invalid)
        validateBooleanProperty(key: AUTOMATIC_CREATION_TEST_CASES, properties: &validatedProperties, default: "false")
        validateBooleanProperty(key: AUTOMATIC_UPDATION_LINKS_TO_TEST_CASES, properties: &validatedProperties, default: "false")
        validateBooleanProperty(key: CERT_VALIDATION, properties: &validatedProperties, default: "true")
        validateBooleanProperty(key: TMS_INTEGRATION, properties: &validatedProperties, default: "true")
        
        // Report errors
        if !errors.isEmpty {
            let errorString = errors.joined(separator: "\n")
            logger.critical("Invalid configuration provided:\n\(errorString)")
            // In a real app, you might throw a custom error here instead of fatalError
            fatalError("Invalid configuration provided:\n\(errorString)") 
        }
        
        logger.debug("Property validation complete.")
        return validatedProperties
    }
    
    // Helper for validating boolean properties
    private static func validateBooleanProperty(key: String, properties: inout [String: String], default defaultValue: String) {
         if let value = properties[key] {
            let lowerValue = value.lowercased()
            if lowerValue != "true" && lowerValue != "false" {
                 logger.warning("Invalid boolean value for \"\(key)\": \(value). Using default value: \(defaultValue)")
                 properties[key] = defaultValue
            }
        } else {
            // If missing entirely, consider setting the default?
             logger.info("Property \"\(key)\" not found, assuming default: \(defaultValue)")
            properties[key] = defaultValue
        }
    }

    // MARK: - Helpers
    static func getConfigFileName() -> String {
        // Try reading from environment variable
        return ProcessInfo.processInfo.environment[TMS_CONFIG_FILE_ENV_VAR] ?? PROPERTIES_FILE
    }
} 

// Расширение должно работать после импорта Foundation
fileprivate extension String {
    var deletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }
    var pathExtension: String {
        return (self as NSString).pathExtension
    }
}
