import Foundation
import os.log
import AdaptersApi

// Updated TmsApiClient implementation based on Kotlin code
class TmsApiClient: ApiClient {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "TmsApiClient")
    private static let AUTH_PREFIX = "PrivateToken"
    private static let INCLUDE_STEPS = true
    private static let INCLUDE_LABELS = true
    private static let INCLUDE_LINKS = true
    private static let MAX_TRIES = 10
    private static let WAITING_TIME_MS: UInt64 = 100 // Milliseconds

    private let clientConfiguration: ClientConfiguration

    // Lock for synchronized methods
    private let lock = NSLock()

    init(configuration: ClientConfiguration) {
        Self.logger.debug("Initializing TmsApiClient with configuration...")
        self.clientConfiguration = configuration
        
        // Check if the non-optional url is valid
        guard !configuration.url.isEmpty, configuration.url.lowercased() != "null" else {
            Self.logger.critical("Cannot initialize TmsApiClient: Base URL is missing or invalid in configuration.")
            fatalError("Cannot initialize TmsApiClient: Base URL is missing or invalid in configuration.")
        }

        // Use the validated URL
        let baseUrl = configuration.url
        AdaptersApiAPI.basePath = baseUrl
        AdaptersApiAPI.customHeaders["Authorization"] = TmsApiClient.AUTH_PREFIX + " " + self.clientConfiguration.privateToken
        AdaptersApiAPI.apiResponseQueue = DispatchQueue.global(qos: .background)
        
        Self.logger.debug("TmsApiClient initialized.")
    }

    // MARK: - ApiClient Protocol Implementation

    func createTestRun() async throws -> TestRunApiResult {
        Self.logger.debug("TmsApiClient: createTestRun...")
        guard let projectId = UUID(uuidString: clientConfiguration.projectId) else {
            Self.logger.error("Cannot create test run: Invalid Project ID format \"\(self.clientConfiguration.projectId)\"")
            throw TmsApiClientError.invalidConfiguration("Invalid Project ID format")
        }
        
        let model = CreateEmptyTestRunApiModel(projectId: projectId)
        Self.logger.debug("Creating new test run: \(String(describing: model))")
        
        // 1. Create Empty Test Run
        let createResponse: TestRunApiResult = try await withCheckedThrowingContinuation { continuation in
            _ = TestRunsAPI.adaptersTestRunsPost(createEmptyTestRunApiModel: model) { [weak self] data, error in
                guard let _ = self else {
                    Self.logger.error("adaptersTestRunsPost callback: self is nil during createTestRun")
                    continuation.resume(throwing: TmsApiClientError.internalError("Self was deallocated during adaptersTestRunsPost callback"))
                    return
                }
                
                if let error = error {
                    Self.logger.error("Error response from adaptersTestRunsPost: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    Self.logger.error("adaptersTestRunsPost returned no data and no error.")
                    continuation.resume(throwing: TmsApiClientError.missingApiResponseData("adaptersTestRunsPost returned no data and no error"))
                }
            }
        }
        
        Self.logger.debug("Successfully created test run, ID: \(createResponse.id.uuidString). Now starting it.")

        // 2. Start Test Run
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = TestRunsAPI.adaptersTestRunsIdStartPost(id: createResponse.id) { [weak self] _, error in
                guard let _ = self else {
                    Self.logger.error("adaptersTestRunsIdStartPost callback: self is nil during createTestRun")
                    continuation.resume(throwing: TmsApiClientError.internalError("Self was deallocated during adaptersTestRunsIdStartPost callback"))
                    return
                }
                
                if let error = error {
                    Self.logger.error("Error starting test run: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        
        Self.logger.debug("Test run created and started: \(createResponse.id.uuidString)")
        return createResponse
    }

    func getTestRun(uuid: String) throws -> TestRunApiResult {
        Self.logger.debug("TmsApiClient: getTestRun...")
        lock.lock()
        defer { lock.unlock() }
        
        guard let runUUID = UUID(uuidString: uuid) else {
             Self.logger.error("Cannot get test run: Invalid UUID format \"\(uuid)\"")
             throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var testRunResult: TestRunApiResult?
        
        _ = TestRunsAPI.adaptersTestRunsIdGet(id: runUUID) { data, error in
            if let error = error {
                Self.logger.error("Error getting test run: \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                testRunResult = data
            } else {
                Self.logger.error("adaptersTestRunsIdGet returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("adaptersTestRunsIdGet returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to get test run: \(error.localizedDescription)")
            throw error
        }
        
        guard let result = testRunResult else {
            Self.logger.error("adaptersTestRunsIdGet response was nil after operation")
            throw TmsApiClientError.missingApiResponseData("adaptersTestRunsIdGet response was nil after operation")
        }
        
        return result
    }

    func updateTestRun(uuid: String, name: String) throws {
        Self.logger.debug("TmsApiClient: updateTestRun... with uuid: \(uuid), name: \(name)")
        
        // Get current test run to preserve other properties
        let currentTestRun = try getTestRun(uuid: uuid)
        
        // Create a mutable copy and update name
        var updatedTestRun = currentTestRun
        updatedTestRun.name = name
        
        // Build update model using Converter
        let updateModel = Converter.buildUpdateEmptyTestRunApiModel(updatedTestRun)
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = TestRunsAPI.adaptersTestRunsPut(updateEmptyTestRunApiModel: updateModel) { _, error in
            if let error = error {
                Self.logger.error("Error updating test run: \(error.localizedDescription)")
                operationError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to update test run: \(error.localizedDescription)")
            throw error
        }
        
        Self.logger.debug("Updated test run \(uuid) name to: \(name)")
    }

    func completeTestRun(uuid: String) throws {
        Self.logger.debug("TmsApiClient: completeTestRun...")
        lock.lock()
        defer { lock.unlock() }
        
         guard let runUUID = UUID(uuidString: uuid) else {
             Self.logger.error("Cannot complete test run: Invalid UUID format \"\(uuid)\"")
             throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = TestRunsAPI.adaptersTestRunsIdCompletePost(id: runUUID) { _, error in
            if let error = error {
                Self.logger.error("Error completing test run: \(error.localizedDescription)")
                operationError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to complete test run: \(error.localizedDescription)")
            throw error
        }
        
         Self.logger.debug("Completed test run: \(uuid)")
    }

    func getTestFromTestRun(testRunUuid: String, configurationId: String) throws -> [String] {
        Self.logger.debug("TmsApiClient: getTestFromTestRun...")

        guard let runUUID = UUID(uuidString: testRunUuid) else {
            Self.logger.error("Cannot get tests from run: Invalid Test Run UUID format \"\(testRunUuid)\"")
            throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
         guard let configUUID = UUID(uuidString: configurationId) else {
            Self.logger.error("Cannot get tests from run: Invalid Configuration ID format \"\(configurationId)\"")
            throw TmsApiClientError.invalidUUIDFormat("Invalid Configuration ID format")
        }
        
        let filter = TestResultsFilterApiModel(
            configurationIds: [configUUID],
            testRunIds: [runUUID]
        )
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var searchResults: [TestResultShortResponse]?

        _ = AdaptersApi.TestResultsAPI.adaptersTestResultsSearchPost(
            skip: nil,
            take: nil,
            orderBy: nil,
            searchField: nil,
            searchValue: nil,
            testResultsFilterApiModel: filter,
            apiResponseQueue: AdaptersApiAPI.apiResponseQueue
        ) { data, error in
            if let error = error {
                Self.logger.error("Error searching test results for getTestFromTestRun: \(error.localizedDescription)")
                operationError = error
            } else {
                searchResults = data ?? []
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to search test results for getTestFromTestRun: \(error.localizedDescription)")
            throw error
        }
        
        guard let results = searchResults, !results.isEmpty else {
            return []
        }
        
        return results.compactMap { $0.autotestExternalId }
    }

    func updateAutoTest(model: AutoTestUpdateApiModel) throws {
        Self.logger.debug("TmsApiClient: updateAutoTest... with externalId: \(model.externalId)")
        
        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()
        
        // Log each property of AutoTestUpdateApiModel
        Self.logger.debug("AutoTestUpdateApiModel details - id: \(escapedModel.id?.uuidString ?? "nil"), externalId: \(escapedModel.externalId), projectId: \(escapedModel.projectId.uuidString), name: \(escapedModel.name), namespace: \(escapedModel.namespace ?? "nil"), classname: \(escapedModel.classname ?? "nil"), title: \(escapedModel.title ?? "nil"), description: \(escapedModel.description ?? "nil"), isFlaky: \(escapedModel.isFlaky?.description ?? "nil"), externalKey: \(escapedModel.externalKey ?? "nil")")
        Self.logger.debug("AutoTestUpdateApiModel links: \(String(describing: escapedModel.links))")
        Self.logger.debug("AutoTestUpdateApiModel steps: \(String(describing: escapedModel.steps))")
        Self.logger.debug("AutoTestUpdateApiModel setup: \(String(describing: escapedModel.setup))")
        Self.logger.debug("AutoTestUpdateApiModel teardown: \(String(describing: escapedModel.teardown))")
        Self.logger.debug("AutoTestUpdateApiModel labels: \(String(describing: escapedModel.labels))")
        Self.logger.debug("AutoTestUpdateApiModel tags: \(String(describing: escapedModel.tags))")

        lock.lock()
        defer { lock.unlock() }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = AutoTestsAPI.adaptersAutoTestsPut(autoTestUpdateApiModel: escapedModel, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { _, error in
            if let error = error {
                Self.logger.error("Error updating autotest: \(error.localizedDescription)")
                operationError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to update autotest: \(error.localizedDescription)")
            throw error
        }
        
        Self.logger.debug("Updated autotest: \(model.externalId)")
    }

    func createAutoTest(model: AutoTestCreateApiModel) throws -> String {
        Self.logger.debug("TmsApiClient: createAutoTest... with externalId: \(model.externalId)")

        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()

        lock.lock()
        defer { lock.unlock() }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var createdAutoTestApiResult: AutoTestApiResult?
        
        _ = AutoTestsAPI.adaptersAutoTestsPost(autoTestCreateApiModel: escapedModel, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error creating autotest: \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                createdAutoTestApiResult = data
            } else {
                Self.logger.error("adaptersAutoTestsPost returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("adaptersAutoTestsPost returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to create autotest: \(error.localizedDescription)")
            throw error
        }
        
        guard let createdTest = createdAutoTestApiResult else {
            Self.logger.error("adaptersAutoTestsPost response was nil after operation")
            throw TmsApiClientError.missingApiResponseData("adaptersAutoTestsPost response was nil after operation")
        }
        
        let createdId = createdTest.id
        
        Self.logger.debug("Created autotest: \(model.externalId) with ID: \(createdId.uuidString)")
        return createdId.uuidString
    }

    func getAutoTestByExternalId(externalId: String) throws -> AutoTestApiResult? {
        Self.logger.debug("TmsApiClient: getAutoTestByExternalId... with externalId: \(externalId)")

        lock.lock()
        defer { lock.unlock() }
        
        guard let projectUUID = UUID(uuidString: clientConfiguration.projectId) else {
            Self.logger.error("Cannot get autotest by external ID: Invalid Project ID format \"\(self.clientConfiguration.projectId)\"")
             throw TmsApiClientError.invalidConfiguration("Invalid Project ID format")
        }
        
        let projectIds: Set<UUID> = [projectUUID]
        let externalIds: Set<String> = [externalId]
        
        let filter = AutoTestFilterApiModel(
            projectIds: projectIds,
            externalIds: externalIds,
            isDeleted: false
        )
        let includes = AutoTestSearchIncludeApiModel(includeSteps: Self.INCLUDE_STEPS, includeLinks: Self.INCLUDE_LINKS, includeLabels: Self.INCLUDE_LABELS)
        let model = AutoTestSearchApiModel(filter: filter, includes: includes)
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var searchResults: [AutoTestApiResult]?

        _ = AutoTestsAPI.adaptersAutoTestsSearchPost(skip: nil, take: nil, orderBy: nil, searchField: nil, searchValue: nil, autoTestSearchApiModel: model, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error searching autotests: \(error.localizedDescription)")
                operationError = error
            } else {
                searchResults = data
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to search autotests: \(error.localizedDescription)")
            throw error
        }
        
        Self.logger.debug("Search for autotest by external ID \"\(externalId)\" found \(searchResults?.count ?? 0) result(s).")
        return searchResults?.first
    }

    func linkAutoTestToWorkItems(id: String, workItemIds: [String]) throws {
        Self.logger.debug("TmsApiClient: linkAutoTestToWorkItems... with id: \(id) and workItemIds: \(workItemIds)")

        lock.lock()
        defer { lock.unlock() }
        
        var lastError: Error? = nil
        for workItemId in workItemIds {
            Self.logger.debug("Attempting to link autotest \(id) to workitem \(workItemId)")
            var success = false
            for attempt in 0..<Self.MAX_TRIES {
                let attemptSemaphore = DispatchSemaphore(value: 0)
                var attemptError: Error?
                
                _ = AutoTestsAPI.adaptersAutoTestsIdWorkItemsPost(id: id, workItemIdApiModel: WorkItemIdApiModel(id: workItemId), apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { _, error in
                    if let error = error {
                        attemptError = error
                    }
                    attemptSemaphore.signal()
                }
                
                attemptSemaphore.wait()
                
                if let error = attemptError {
                    lastError = error
                    Self.logger.error("Cannot link autotest \(id) to work item \(workItemId) on attempt \(attempt + 1): \(error.localizedDescription)")
                    if attempt < Self.MAX_TRIES - 1 {
                         Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0)
                    }
                } else {
                    Self.logger.debug("Link autotest \(id) to workitem \(workItemId) successful on attempt \(attempt + 1).")
                    success = true
                    lastError = nil
                    break
                }
            }
            if !success, let errorToThrow = lastError {
                 Self.logger.error("Failed to link autotest \(id) to work item \(workItemId) after \(Self.MAX_TRIES) attempts.")
                 throw errorToThrow
            }
        }
    }

    func unlinkAutoTestToWorkItem(id: String, workItemId: String) throws -> Bool {
        Self.logger.debug("TmsApiClient: unlinkAutoTestToWorkItem... with id: \(id) and workItemId: \(workItemId)")

        for attempt in 0..<Self.MAX_TRIES {
            let attemptSemaphore = DispatchSemaphore(value: 0)
            var attemptError: Error?
            var successFlag = false

            _ = AutoTestsAPI.adaptersAutoTestsIdWorkItemsDelete(id: id, workItemId: workItemId, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { _, error in
                if let error = error {
                    attemptError = error
                } else {
                    successFlag = true
                }
                attemptSemaphore.signal()
            }
            
            attemptSemaphore.wait()
            
            if let error = attemptError {
                Self.logger.error("Failed to unlink autotest \(id) from work item \(workItemId) on attempt \(attempt + 1): \(error.localizedDescription)")
                if attempt == Self.MAX_TRIES - 1 {
                    throw error
                }
                Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0)
            } else if successFlag {
                Self.logger.debug("Unlinked autotest \(id) from workitem \(workItemId) on attempt \(attempt + 1).")
                return true
            } else {
                Self.logger.warning("Unlink attempt \(attempt + 1) for autotest \(id) from workitem \(workItemId) neither errored nor explicitly succeeded. Retrying if attempts remain.")
                if attempt == Self.MAX_TRIES - 1 {
                    throw TmsApiClientError.missingApiResponseData("Failed to confirm unlinking after max retries for autotest \(id) from workitem \(workItemId).")
                }
                Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0)
            }
        }
        Self.logger.error("Failed to unlink autotest \(id) from work item \(workItemId) after \(Self.MAX_TRIES) attempts, and loop completed without explicit success or error throw.")
        return false
    }

    func getWorkItemsLinkedToTest(id: String) throws -> [AutoTestWorkItemIdentifierApiResult] {
        Self.logger.debug("TmsApiClient: getWorkItemsLinkedToTest... with id: \(id)")
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var workItemsResult: [AutoTestWorkItemIdentifierApiResult]?
        
        _ = AutoTestsAPI.adaptersAutoTestsIdWorkItemsGet(id: id, isDeleted: false, isWorkItemDeleted: false, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error retrieving work items linked to test \(id): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                workItemsResult = data
            } else {
                Self.logger.error("adaptersAutoTestsIdWorkItemsGet for test \(id) returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("adaptersAutoTestsIdWorkItemsGet returned no data and no error for test ID: \(id)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to retrieve work items linked to test \(id) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let result = workItemsResult else {
            Self.logger.error("Retrieved nil work items for test \(id) without an explicit API error. This is unexpected.")
            throw TmsApiClientError.missingApiResponseData("Retrieved nil work items for test ID: \(id) without explicit API error")
        }
        
        return result
    }

    func sendTestResults(testRunUuid: String, models: [AutoTestResultsForTestRunModel]) throws -> [String] {
        print("[TestItAdapter] TmsApiClient.sendTestResults called with testRunUuid: \(testRunUuid)")
        Self.logger.debug("TmsApiClient: sendTestResults... with testRunUuid: \(testRunUuid) and models: \(models)")

        // Escape HTML in models before sending
        var escapedModels = models
        for i in 0..<escapedModels.count {
            escapedModels[i].escapeHtmlProperties()
        }

        guard let runUUID = UUID(uuidString: testRunUuid) else {
            print("[TestItAdapter] ERROR: Invalid Test Run UUID format: \(testRunUuid)")
            Self.logger.error("Cannot send results: Invalid Test Run UUID format \"\(testRunUuid)\"")
            throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
        
        print("[TestItAdapter] Calling TestRunsAPI.adaptersTestRunsIdTestResultsPost...")
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var resultUUIDsFromApi: [UUID]?
        
        _ = TestRunsAPI.adaptersTestRunsIdTestResultsPost(id: runUUID, autoTestResultsForTestRunModel: escapedModels, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error sending test results for test run \(testRunUuid): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                resultUUIDsFromApi = data
            } else {
                Self.logger.debug("adaptersTestRunsIdTestResultsPost for test run \(testRunUuid) returned no data and no error. Interpreting as empty results.")
                resultUUIDsFromApi = []
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to send test results for test run \(testRunUuid) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let receivedUUIDs = resultUUIDsFromApi else {
            Self.logger.error("adaptersTestRunsIdTestResultsPost for test run \(testRunUuid) resulted in nil UUIDs unexpectedly after processing.")
            throw TmsApiClientError.missingApiResponseData("adaptersTestRunsIdTestResultsPost resulted in nil UUIDs unexpectedly for test run: \(testRunUuid)")
        }
        
        Self.logger.debug("Sent \(models.count) test results for test run \(testRunUuid). Received \(receivedUUIDs.count) result IDs.")
        return receivedUUIDs.map { $0.uuidString }
    }

    func addAttachment(path: String) throws -> String {
        print("[TestItAdapter] TmsApiClient.addAttachment called with path: \(path)")
        Self.logger.debug("TmsApiClient: addAttachment... with path: \(path)")

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            print("[TestItAdapter] ERROR: File not found at path: \(path)")
            print("[TestItAdapter] Current working directory: \(FileManager.default.currentDirectoryPath)")
            Self.logger.error("Cannot add attachment: File not found at path \"\(path)\"")
            throw TmsApiClientError.fileNotFound(path)
        }

        let currentDirectory = FileManager.default.currentDirectoryPath
        Self.logger.debug("Current working directory: \(currentDirectory)")

        do {
            if !FileManager.default.isReadableFile(atPath: path) {
                print("[TestItAdapter] ERROR: No read permission for file at path: \(path)")
                Self.logger.error("Cannot add attachment: No read permission for file at path \"\(path)\"")
                throw TmsApiClientError.fileNotFound(path)
            }
        } catch {
            print("[TestItAdapter] ERROR checking file permissions: \(error.localizedDescription)")
            Self.logger.error("Error checking file permissions: \(error.localizedDescription)")
            throw TmsApiClientError.fileNotFound(path)
        }
        
        print("[TestItAdapter] File found and readable, uploading...")
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var attachmentModelResponse: AttachmentModel?
        
        _ = AttachmentsAPI.adaptersAttachmentsPost(file: fileURL, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                print("[TestItAdapter] ERROR uploading attachment: \(error.localizedDescription)")
                Self.logger.error("Error uploading attachment from path \"\(path)\": \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                print("[TestItAdapter] Attachment uploaded successfully, received model")
                attachmentModelResponse = data
            } else {
                print("[TestItAdapter] ERROR: API returned no data and no error")
                Self.logger.error("adaptersAttachmentsPost for path \"\(path)\" returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("adaptersAttachmentsPost for path \"\(path)\" returned no data and no error")
            }
            semaphore.signal()
        }
        
        print("[TestItAdapter] Waiting for attachment upload to complete...")
        semaphore.wait()
        print("[TestItAdapter] Attachment upload completed")
        
        if let error = operationError {
            print("[TestItAdapter] ERROR: Failed to upload attachment: \(error.localizedDescription)")
            Self.logger.error("Failed to upload attachment from path \"\(path)\" (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let model = attachmentModelResponse else {
            print("[TestItAdapter] ERROR: Attachment response was nil")
            Self.logger.error("adaptersAttachmentsPost for path \"\(path)\" response was nil after operation, and no explicit error was caught.")
            throw TmsApiClientError.missingApiResponseData("adaptersAttachmentsPost response was nil for path \"\(path)\" after operation")
        }
        
        print("[TestItAdapter] ✓✓✓ Attachment uploaded successfully! ID: \(model.id.uuidString)")
        Self.logger.debug("Uploaded attachment from path \"\(path)\". Received ID: \(model.id.uuidString)")
        return model.id.uuidString
    }

    func getTestResult(uuid: UUID) throws -> TestResultResponse {
        Self.logger.debug("TmsApiClient: getTestResult... with uuid: \(uuid)")
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var testResultResponse: TestResultResponse?
        
        _ = AdaptersApi.TestResultsAPI.adaptersTestResultsIdGet(id: uuid, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error getting test result by ID \(uuid.uuidString): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                testResultResponse = data
            } else {
                Self.logger.error("adaptersTestResultsIdGet for ID \(uuid.uuidString) returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("adaptersTestResultsIdGet returned no data and no error for ID: \(uuid.uuidString)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to get test result by ID \(uuid.uuidString) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let response = testResultResponse else {
            Self.logger.error("adaptersTestResultsIdGet for ID \(uuid.uuidString) response was nil after operation, and no explicit error was caught.")
            throw TmsApiClientError.missingApiResponseData("adaptersTestResultsIdGet response was nil after operation for ID: \(uuid.uuidString)")
        }
        
        return response
    }

    func updateTestResult(uuid: UUID, model: TestResultUpdateRequest) throws {
        Self.logger.debug("TmsApiClient: updateTestResult... with uuid: \(uuid)")

        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = AdaptersApi.TestResultsAPI.adaptersTestResultsIdPut(id: uuid, testResultUpdateRequest: escapedModel, apiResponseQueue: AdaptersApiAPI.apiResponseQueue) { _, error in
            if let error = error {
                Self.logger.error("Error updating test result by ID \(uuid.uuidString): \(error.localizedDescription)")
                operationError = error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to update test result by ID \(uuid.uuidString) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        Self.logger.debug("Updated test result: \(uuid.uuidString)")
    }
}

// Define custom errors for better context
enum TmsApiClientError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidUUIDFormat(String)
    case missingApiResponseData(String)
    case fileNotFound(String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid Client Configuration: \(reason)"
        case .invalidUUIDFormat(let reason):
            return "Invalid UUID Format: \(reason)"
        case .missingApiResponseData(let reason):
            return "Missing API Response Data: \(reason)"
        case .fileNotFound(let path):
            return "File Not Found: \(path)"
        case .internalError(let reason):
            return "Internal Error: \(reason)"
        }
    }
}
