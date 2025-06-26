import Foundation
import os.log
import testit_api_client

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
        TestitApiClientAPI.basePath = baseUrl
        TestitApiClientAPI.customHeaders["Authorization"] = TmsApiClient.AUTH_PREFIX + " " + self.clientConfiguration.privateToken
        TestitApiClientAPI.apiResponseQueue = DispatchQueue.global(qos: .background)
        // TestitApiClientAPI.requiresAuthentication = self.clientConfiguration.certValidation
        
        Self.logger.debug("TmsApiClient initialized.")
    }

    // MARK: - ApiClient Protocol Implementation

    func createTestRun() async throws -> TestRunV2ApiResult {
        Self.logger.debug("TmsApiClient: createTestRun...")
        guard let projectId = UUID(uuidString: clientConfiguration.projectId) else {
            Self.logger.error("Cannot create test run: Invalid Project ID format \"\(self.clientConfiguration.projectId)\"")
            throw TmsApiClientError.invalidConfiguration("Invalid Project ID format")
        }
        
        let model = CreateEmptyTestRunApiModel(projectId: projectId)
        Self.logger.debug("Creating new test run: \(String(describing: model))")
        
        // 1. Create Empty Test Run
        let createResponse: TestRunV2ApiResult = try await withCheckedThrowingContinuation { continuation in
            _ = TestRunsAPI.createEmpty(createEmptyTestRunApiModel: model) { [weak self] data, error in
                guard let _ = self else {
                    // Self was deallocated, which is unlikely if createTestRun is still executing,
                    // but it's safe to handle.
                    Self.logger.error("createEmpty callback: self is nil during createTestRun")
                    continuation.resume(throwing: TmsApiClientError.internalError("Self was deallocated during createEmpty callback"))
                    return
                }
                
                if let error = error {
                    Self.logger.error("Error response from createEmpty: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    Self.logger.error("createEmpty returned no data and no error.")
                    continuation.resume(throwing: TmsApiClientError.missingApiResponseData("createEmpty returned no data and no error"))
                }
            }
        }
        
        Self.logger.debug("Successfully created test run, ID: \(createResponse.id.uuidString). Now starting it.")

        // 2. Start Test Run
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            _ = TestRunsAPI.startTestRun(id: createResponse.id) { [weak self] _, error in
                guard let _ = self else {
                    Self.logger.error("startTestRun callback: self is nil during createTestRun")
                    continuation.resume(throwing: TmsApiClientError.internalError("Self was deallocated during startTestRun callback"))
                    return
                }
                
                if let error = error {
                    Self.logger.error("Error starting test run: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    // Successful start, returning Void
                    continuation.resume(returning: ())
                }
            }
        }
        
        Self.logger.debug("Test run created and started: \(createResponse.id.uuidString)")
        return createResponse
    }

    func getTestRun(uuid: String) throws -> TestRunV2ApiResult {
        Self.logger.debug("TmsApiClient: getTestRun...")
        lock.lock()
        defer { lock.unlock() }
        
        guard let runUUID = UUID(uuidString: uuid) else {
             Self.logger.error("Cannot get test run: Invalid UUID format \"\(uuid)\"")
             throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var testRunResult: TestRunV2ApiResult?
        
        _ = TestRunsAPI.getTestRunById(id: runUUID) { data, error in
            if let error = error {
                Self.logger.error("Error getting test run: \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                testRunResult = data
            } else {
                Self.logger.error("getTestRunById returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("getTestRunById returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to get test run: \(error.localizedDescription)")
            throw error
        }
        
        guard let result = testRunResult else {
            Self.logger.error("getTestRunById response was nil after operation")
            throw TmsApiClientError.missingApiResponseData("getTestRunById response was nil after operation")
        }
        
        return result
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
        
        _ = TestRunsAPI.completeTestRun(id: runUUID) { _, error in
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
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var testRunResult: TestRunV2ApiResult?

        _ = TestRunsAPI.getTestRunById(id: runUUID) { data, error in
            if let error = error {
                Self.logger.error("Error getting test run for getTestFromTestRun: \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                testRunResult = data
            } else {
                Self.logger.error("getTestRunById (for getTestFromTestRun) returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("getTestRunById (for getTestFromTestRun) returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to get test run for getTestFromTestRun: \(error.localizedDescription)")
            throw error
        }
        
        guard let model = testRunResult else {
            Self.logger.error("getTestRunById (for getTestFromTestRun) response was nil after operation")
            throw TmsApiClientError.missingApiResponseData("getTestRunById (for getTestFromTestRun) response was nil after operation")
        }

        guard let testResults = model.testResults, !testResults.isEmpty else {
            return []
        }
        
        // Assuming TestResultV2ShortModel has configurationId and autoTest?.externalId
        // Need to add these properties to the stub if not present
        return testResults.filter { $0.configurationId == configUUID }
                          .compactMap { $0.autoTest?.externalId }
    }

    func updateAutoTest(model: AutoTestPutModel) throws {
        Self.logger.debug("TmsApiClient: updateAutoTest... with externalId: \(model.externalId)")
        
        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()
        
        // Log each property of AutoTestPutModel
        Self.logger.debug("AutoTestPutModel details - id: \(escapedModel.id?.uuidString ?? "nil"), externalId: \(escapedModel.externalId), projectId: \(escapedModel.projectId.uuidString), name: \(escapedModel.name), namespace: \(escapedModel.namespace ?? "nil"), classname: \(escapedModel.classname ?? "nil"), title: \(escapedModel.title ?? "nil"), description: \(escapedModel.description ?? "nil"), isFlaky: \(escapedModel.isFlaky?.description ?? "nil"), externalKey: \(escapedModel.externalKey ?? "nil")")
        Self.logger.debug("AutoTestPutModel links: \(String(describing: escapedModel.links))")
        Self.logger.debug("AutoTestPutModel steps: \(String(describing: escapedModel.steps))")
        Self.logger.debug("AutoTestPutModel setup: \(String(describing: escapedModel.setup))")
        Self.logger.debug("AutoTestPutModel teardown: \(String(describing: escapedModel.teardown))")
        Self.logger.debug("AutoTestPutModel labels: \(String(describing: escapedModel.labels))")
        Self.logger.debug("AutoTestPutModel workItemIdsForLinkWithAutoTest: \(String(describing: escapedModel.workItemIdsForLinkWithAutoTest))")

        lock.lock()
        defer { lock.unlock() }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = AutoTestsAPI.updateAutoTest(autoTestPutModel: escapedModel, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { _, error in // Added apiResponseQueue for clarity, assuming it's needed as per typical library patterns
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

    func createAutoTest(model: AutoTestPostModel) throws -> String {
        Self.logger.debug("TmsApiClient: createAutoTest... with externalId: \(model.externalId)")

        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()

        lock.lock()
        defer { lock.unlock() }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var createdAutoTestModel: AutoTestModel?
        
        _ = AutoTestsAPI.createAutoTest(autoTestPostModel: escapedModel, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error creating autotest: \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                createdAutoTestModel = data
            } else {
                Self.logger.error("createAutoTest returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("createAutoTest returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to create autotest: \(error.localizedDescription)")
            throw error
        }
        
        guard let createdTest = createdAutoTestModel else {
            Self.logger.error("createAutoTest response was nil after operation")
            throw TmsApiClientError.missingApiResponseData("createAutoTest response was nil after operation")
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

        _ = AutoTestsAPI.apiV2AutoTestsSearchPost(skip: nil, take: nil, orderBy: nil, searchField: nil, searchValue: nil, autoTestSearchApiModel: model, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error searching autotests: \(error.localizedDescription)")
                operationError = error
            } else {
                // Data can be nil or an empty array if no results are found, which is not an error itself.
                searchResults = data
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to search autotests: \(error.localizedDescription)")
            throw error
        }
        
        // Note: searchResults can be nil or an empty array if the API call was successful but found no matching autotests.
        // The original logic `tests.first` gracefully handles an empty array by returning nil.
        // If searchResults is nil due to an issue not caught by `operationError` (e.g. malformed success response without error flag), this will also result in nil.
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
                
                _ = AutoTestsAPI.linkAutoTestToWorkItem(id: id, workItemIdModel: WorkItemIdModel(id: workItemId), apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { _, error in
                    if let error = error {
                        attemptError = error
                    } else {
                        // Successful link
                    }
                    attemptSemaphore.signal()
                }
                
                attemptSemaphore.wait()
                
                if let error = attemptError {
                    lastError = error // Store the last error encountered for this workItemId
                    Self.logger.error("Cannot link autotest \(id) to work item \(workItemId) on attempt \(attempt + 1): \(error.localizedDescription)")
                    if attempt < Self.MAX_TRIES - 1 {
                         Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0) // Keep sleep for retry delay
                    } else {
                        // This was the last attempt for this workItemId, error will be thrown after loop if not successful
                    }
                } else {
                    Self.logger.debug("Link autotest \(id) to workitem \(workItemId) successful on attempt \(attempt + 1).")
                    success = true
                    lastError = nil // Clear last error on success for this workItemId
                    break // Exit retry loop for this workItemId on success
                }
            }
            // If after all retries for a specific work item it failed, throw the last error encountered for it
            if !success, let errorToThrow = lastError {
                 Self.logger.error("Failed to link autotest \(id) to work item \(workItemId) after \(Self.MAX_TRIES) attempts.")
                 throw errorToThrow // Throw immediately if a single workItem link fails after all retries
            }
        }
        // If the loop completes without throwing, all links were successful or workItemIds was empty
    }

    func unlinkAutoTestToWorkItem(id: String, workItemId: String) throws -> Bool {
        Self.logger.debug("TmsApiClient: unlinkAutoTestToWorkItem... with id: \(id) and workItemId: \(workItemId)")

        // No lock needed according to Kotlin version? Consider if needed for safety.
        // Following existing pattern of no lock for this method.
        for attempt in 0..<Self.MAX_TRIES {
            let attemptSemaphore = DispatchSemaphore(value: 0)
            var attemptError: Error?
            var successFlag = false // Flag to indicate success for the current attempt

            _ = AutoTestsAPI.deleteAutoTestLinkFromWorkItem(id: id, workItemId: workItemId, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { _, error in
                if let error = error {
                    attemptError = error
                } else {
                    successFlag = true // Mark success for this attempt
                }
                attemptSemaphore.signal()
            }
            
            attemptSemaphore.wait()
            
            if let error = attemptError {
                Self.logger.error("Failed to unlink autotest \(id) from work item \(workItemId) on attempt \(attempt + 1): \(error.localizedDescription)")
                if attempt == Self.MAX_TRIES - 1 {
                    throw error // Re-throw after last attempt
                }
                // If not the last attempt, sleep and retry
                Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0)
            } else if successFlag {
                Self.logger.debug("Unlinked autotest \(id) from workitem \(workItemId) on attempt \(attempt + 1).")
                return true // Successfully unlinked
            } else {
                // This case should ideally not be hit if API guarantees error or success.
                // If it is hit, it means no error and no explicit success signal from the API logic for this attempt.
                // Log it and continue to retry or fail after max attempts.
                Self.logger.warning("Unlink attempt \(attempt + 1) for autotest \(id) from workitem \(workItemId) neither errored nor explicitly succeeded. Retrying if attempts remain.")
                if attempt == Self.MAX_TRIES - 1 {
                    // If this was the last attempt and it was ambiguous, throw a generic error or the last known specific error if one was ever set.
                    // For now, throwing a generic one indicating failure to confirm unlinking.
                    throw TmsApiClientError.missingApiResponseData("Failed to confirm unlinking after max retries for autotest \(id) from workitem \(workItemId).")
                }
                Thread.sleep(forTimeInterval: TimeInterval(Self.WAITING_TIME_MS) / 1000.0)
            }
        }
        // This part should ideally not be reached if logic always returns true on success or throws an error on definitive failure.
        // If the loop completes without returning true (success) or throwing an error, it implies MAX_TRIES might be 0 or some unexpected flow.
        Self.logger.error("Failed to unlink autotest \(id) from work item \(workItemId) after \(Self.MAX_TRIES) attempts, and loop completed without explicit success or error throw.")
        return false // Default to false if loop completes without success, though ideally an error should have been thrown.
    }

    func getWorkItemsLinkedToTest(id: String) throws -> [WorkItemIdentifierModel] {
        Self.logger.debug("TmsApiClient: getWorkItemsLinkedToTest... with id: \(id)")

        // No lock needed according to Kotlin version? Consider if needed for safety if there are shared mutable states accessed by this path.
        // For now, following the existing pattern of no lock for this specific method.
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var workItemsResult: [WorkItemIdentifierModel]?
        
        // Using false for isDeleted and isWorkItemDeleted as per the original synchronous call's parameters.
        _ = AutoTestsAPI.getWorkItemsLinkedToAutoTest(id: id, isDeleted: false, isWorkItemDeleted: false, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error retrieving work items linked to test \(id): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                workItemsResult = data
            } else {
                // This case: no error, but also no data. Treat as an issue if a non-optional array is expected.
                Self.logger.error("getWorkItemsLinkedToAutoTest for test \(id) returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("getWorkItemsLinkedToAutoTest returned no data and no error for test ID: \(id)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to retrieve work items linked to test \(id) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        // If we reach here, operationError is nil. We must have data.
        // The guard below ensures workItemsResult is not nil. If it were, an error would have been set above.
        guard let result = workItemsResult else {
            // This path should ideally not be reached if the logic above correctly sets operationError
            // when data is nil and no error object was provided by the API.
            Self.logger.error("Retrieved nil work items for test \(id) without an explicit API error. This is unexpected.")
            throw TmsApiClientError.missingApiResponseData("Retrieved nil work items for test ID: \(id) without explicit API error")
        }
        
        return result
    }

    func sendTestResults(testRunUuid: String, models: [AutoTestResultsForTestRunModel]) throws -> [String] {
        Self.logger.debug("TmsApiClient: sendTestResults... with testRunUuid: \(testRunUuid) and models: \(models)")

        // Escape HTML in models before sending
        var escapedModels = models
        for i in 0..<escapedModels.count {
            escapedModels[i].escapeHtmlProperties()
        }

        // No lock needed according to Kotlin version? Consider if needed for safety.
        guard let runUUID = UUID(uuidString: testRunUuid) else {
             Self.logger.error("Cannot send results: Invalid Test Run UUID format \"\(testRunUuid)\"")
            throw TmsApiClientError.invalidUUIDFormat("Invalid Test Run UUID format")
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var resultUUIDsFromApi: [UUID]?
        
        _ = TestRunsAPI.setAutoTestResultsForTestRun(id: runUUID, autoTestResultsForTestRunModel: escapedModels, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error sending test results for test run \(testRunUuid): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                resultUUIDsFromApi = data
            } else {
                // If API returns no error AND no data, and a [UUID]? is expected, this implies an empty list of results.
                // However, the original function expects [String], so an empty list here is valid.
                // If the API *guarantees* non-nil on success, this might be an error. Assuming nil means empty for now.
                Self.logger.debug("setAutoTestResultsForTestRun for test run \(testRunUuid) returned no data and no error. Interpreting as empty results.")
                resultUUIDsFromApi = [] // Explicitly set to empty array if API returns nil data without error.
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to send test results for test run \(testRunUuid) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        // If operationError is nil, we proceed. resultUUIDsFromApi could be nil if API truly returns nil on success (which we convert to [] above)
        // or an array (possibly empty) of UUIDs.
        guard let receivedUUIDs = resultUUIDsFromApi else {
            // This path should not be reached if the completion handler logic above correctly converts nil data (without error) to an empty array.
            Self.logger.error("setAutoTestResultsForTestRun for test run \(testRunUuid) resulted in nil UUIDs unexpectedly after processing.")
            throw TmsApiClientError.missingApiResponseData("setAutoTestResultsForTestRun resulted in nil UUIDs unexpectedly for test run: \(testRunUuid)")
        }
        
        Self.logger.debug("Sent \(models.count) test results for test run \(testRunUuid). Received \(receivedUUIDs.count) result IDs.")
        return receivedUUIDs.map { $0.uuidString } // Convert UUIDs to Strings
    }

    func addAttachment(path: String) throws -> String {
        Self.logger.debug("TmsApiClient: addAttachment... with path: \(path)")

        // No lock needed according to Kotlin version? Consider if needed for safety.
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
             Self.logger.error("Cannot add attachment: File not found at path \"\(path)\"")
             throw TmsApiClientError.fileNotFound(path)
        }

        // Log the current working directory
        let currentDirectory = FileManager.default.currentDirectoryPath
        Self.logger.debug("Current working directory: \(currentDirectory)")

        // Check file permissions
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            //Self.logger.debug("File attributes: \(attributes)")
            
            // Check read permissions
            if !FileManager.default.isReadableFile(atPath: path) {
                Self.logger.error("Cannot add attachment: No read permission for file at path \"\(path)\"")
                throw TmsApiClientError.fileNotFound(path)
            }
        } catch {
            Self.logger.error("Error checking file permissions: \(error.localizedDescription)")
            throw TmsApiClientError.fileNotFound(path)
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var attachmentModelResponse: AttachmentModel?
        
        _ = AttachmentsAPI.apiV2AttachmentsPost(file: fileURL, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error uploading attachment from path \"\(path)\": \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                attachmentModelResponse = data
            } else {
                Self.logger.error("apiV2AttachmentsPost for path \"\(path)\" returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("apiV2AttachmentsPost for path \"\(path)\" returned no data and no error")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to upload attachment from path \"\(path)\" (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let model = attachmentModelResponse else {
            Self.logger.error("apiV2AttachmentsPost for path \"\(path)\" response was nil after operation, and no explicit error was caught.")
            throw TmsApiClientError.missingApiResponseData("apiV2AttachmentsPost response was nil for path \"\(path)\" after operation")
        }
        
        Self.logger.debug("Uploaded attachment from path \"\(path)\". Received ID: \(model.id.uuidString)")
        return model.id.uuidString
    }

    func getTestResult(uuid: UUID) throws -> TestResultResponse {
        Self.logger.debug("TmsApiClient: getTestResult... with uuid: \(uuid)")

        // No lock needed according to Kotlin version? Consider if needed for safety.
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        var testResultResponse: TestResultResponse?
        
        _ = TestResultsAPI.apiV2TestResultsIdGet(id: uuid, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { data, error in
            if let error = error {
                Self.logger.error("Error getting test result by ID \(uuid.uuidString): \(error.localizedDescription)")
                operationError = error
            } else if let data = data {
                testResultResponse = data
            } else {
                Self.logger.error("apiV2TestResultsIdGet for ID \(uuid.uuidString) returned no data and no error.")
                operationError = TmsApiClientError.missingApiResponseData("apiV2TestResultsIdGet returned no data and no error for ID: \(uuid.uuidString)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to get test result by ID \(uuid.uuidString) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        guard let response = testResultResponse else {
            Self.logger.error("apiV2TestResultsIdGet for ID \(uuid.uuidString) response was nil after operation, and no explicit error was caught.")
            throw TmsApiClientError.missingApiResponseData("apiV2TestResultsIdGet response was nil after operation for ID: \(uuid.uuidString)")
        }
        
        return response
    }

    func updateTestResult(uuid: UUID, model: TestResultUpdateV2Request) throws {
        Self.logger.debug("TmsApiClient: updateTestResult... with uuid: \(uuid)")

        // Escape HTML in model before sending
        var escapedModel = model
        escapedModel.escapeHtmlProperties()

         // No lock needed according to Kotlin version? Consider if needed for safety.
        
        let semaphore = DispatchSemaphore(value: 0)
        var operationError: Error?
        
        _ = TestResultsAPI.apiV2TestResultsIdPut(id: uuid, testResultUpdateV2Request: escapedModel, apiResponseQueue: TestitApiClientAPI.apiResponseQueue) { _, error in
            if let error = error {
                Self.logger.error("Error updating test result by ID \(uuid.uuidString): \(error.localizedDescription)")
                operationError = error
            }
            // On success, data is Void?, so no explicit data to store.
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = operationError {
            Self.logger.error("Failed to update test result by ID \(uuid.uuidString) (propagating error): \(error.localizedDescription)")
            throw error
        }
        
        Self.logger.debug("Updated test result: \(uuid.uuidString)")
    }
    
    // MARK: - Helper for TestRunV2ApiResult extension (if needed)
    // Add extension if TestRunV2ApiResult stub doesn't have testResults property
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

// Example extension if TestRunV2ApiResult stub needs modification
extension TestRunV2ApiResult {
    // NOTE: This is needed for getTestFromTestRun to work.
    // Define testResults based on actual API response structure
    // This might require another stub model like TestResultV2ShortModel
     var testResults: [TestResultV2ShortModel]? {
         // return actual property or parse from raw response data
         return nil // Placeholder - Needs real implementation or better stub
     }
}

// Example stub if TestResultV2ShortModel is needed
 struct TestResultV2ShortModel { // Placeholder - Needs real implementation
     var configurationId: UUID?
     var autoTest: AutoTestApiResult? // Assumes AutoTestApiResult stub exists
 } 
