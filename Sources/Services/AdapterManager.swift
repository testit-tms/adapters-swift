import Foundation
import os.log
import testit_api_client
import Darwin


class AdapterManager {

    private var clientConfiguration: ClientConfiguration
    private let adapterConfig: AdapterConfig
    private let client: ApiClient
    private var writer: Writer? // Optional because it's set in the longer init
    var threadContext: ThreadContext
    private var storage: ResultStorage
    
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "AdapterManager")
    
    // Lock for synchronizing access to shared resources like storage and clientConfiguration
    // Note: Consider if storage itself should be thread-safe (e.g., Actor)
    private let lock = NSLock()

    // Designated Initializer (matches the primary Kotlin constructor)
    init(clientConfiguration: ClientConfiguration, adapterConfig: AdapterConfig, client: ApiClient, storage: ResultStorage, threadContext: ThreadContext, writer: Writer?) {
        Self.logger.debug("Initializing AdapterManager (Designated)...")
        self.clientConfiguration = clientConfiguration
        self.adapterConfig = adapterConfig
        self.client = client
        self.storage = storage
        self.threadContext = threadContext
        self.writer = writer
        logInitialConfigs()
    }
    
    // Convenience Initializer (matching Kotlin constructor with default ListenerManager (deprecated))
    convenience init(clientConfiguration: ClientConfiguration, adapterConfig: AdapterConfig, client: ApiClient) {
        let defaultStorage = Adapter.getResultStorage()
        let defaultThreadContext = ThreadContext()
        let defaultWriter = HttpWriter(configuration: clientConfiguration, client: client, storage: defaultStorage)
        
        self.init(clientConfiguration: clientConfiguration, 
                  adapterConfig: adapterConfig, 
                  client: client, 
                  storage: defaultStorage, 
                  threadContext: defaultThreadContext, 
                  writer: defaultWriter)
        Self.logger.debug("Initialized AdapterManager using default dependencies (storage, listener, context, writer).")
    }

    // Convenience Initializer (matching Kotlin constructor with default ApiClient)
    convenience init(clientConfiguration: ClientConfiguration, adapterConfig: AdapterConfig) {
        let defaultClient = TmsApiClient(configuration: clientConfiguration)
        let defaultStorage = Adapter.getResultStorage()
        let defaultThreadContext = ThreadContext()
        let defaultWriter = HttpWriter(configuration: clientConfiguration, client: defaultClient, storage: defaultStorage)

        self.init(clientConfiguration: clientConfiguration, 
                  adapterConfig: adapterConfig, 
                  client: defaultClient, 
                  storage: defaultStorage, 
                  threadContext: defaultThreadContext, 
                  writer: defaultWriter)
        Self.logger.debug("Initialized AdapterManager using default client, storage, context, writer.")
    }
    
    private func logInitialConfigs() {
         Self.logger.debug("Client configurations: \(String(describing: self.clientConfiguration))") // Adapt if ClientConfiguration isn't CustomStringConvertible
         Self.logger.debug("Adapter configurations: \(self.adapterConfig)") // AdapterConfig is CustomStringConvertible
    }

    // MARK: - Test Run Lifecycle

    func createTestRunIfNeeded() async {
        guard adapterConfig.shouldEnableTmsIntegration else {
            Self.logger.debug("TMS integration is disabled. Skipping Test Run creation.")
            return
        }

        Self.logger.debug("Attempting to establish Test Run ID...")

        let (initialTestRunId, isConfigTestRunIdMissing) = lock.withLock {
            let testRunId = self.clientConfiguration.testRunId
            return (testRunId, testRunId.isEmpty || testRunId.lowercased() == "null")
        }

        if !isConfigTestRunIdMissing && self.clientConfiguration.mode != "2" {
            Self.logger.info("Test Run ID already provided in configuration: \(initialTestRunId). Using this ID.")
            // Ensure that writer knows about this ID, if it was set only in configuration
            // and not passed through the logic below (for example, when restarting with an already existing ID)
            self.writer?.setTestRun(testRunId: initialTestRunId)
            return
        }

        Self.logger.debug("Test Run ID not found in configuration. Checking TEST_RUN_AUTO_ID environment variable.")
        let envVarName = "TEST_RUN_AUTO_ID"
        // var envTestRunId: String? = nil
        if let envValue = ProcessInfo.processInfo.environment[envVarName], !envValue.isEmpty {
            // envTestRunId = envValue
            Self.logger.info("Found Test Run ID in environment variable \(envVarName): \(envValue). Using this ID.")
            
            lock.withLock {
                self.clientConfiguration.testRunId = envValue
                self.writer?.setTestRun(testRunId: envValue)
            }
            return
        }

        // need new Test Run
        Self.logger.debug("Environment variable \(envVarName) is not set or is empty. Proceeding to create a new Test Run via API.")
        
        do {
            Self.logger.debug("Calling client.createTestRun() asynchronously...")
            let response = try await self.client.createTestRun() // Async call
            let newTestRunId = response.id.uuidString
            Self.logger.debug("client.createTestRun() completed. New Test Run ID: \(newTestRunId)")
            lock.withLock {
                self.clientConfiguration.testRunId = newTestRunId
                self.writer?.setTestRun(testRunId: newTestRunId)
            }
        } catch {
            Self.logger.error("Cannot start the launch (error during createTestRun or update): \(error.localizedDescription)")
        }
    }

    /**
     * Is not used in current version.
     */
    func stopTests() {
        guard adapterConfig.shouldEnableTmsIntegration else { return }
        // Check the non-optional testRunId directly
        guard self.clientConfiguration.testRunId.lowercased() != "null" else {
            Self.logger.warning("Cannot stop tests: testRunId is not set or is \"null\".")
            return
        }
        // Use the validated non-optional property
        let testRunId = self.clientConfiguration.testRunId 

        Self.logger.debug("Stop launch")

        do {
            let testRun = try self.client.getTestRun(uuid: testRunId)

            if testRun.stateName != .completed {
                try self.client.completeTestRun(uuid: testRunId)
                Self.logger.info("Completed test run: \(testRunId)")
            } else {
                 Self.logger.info("Test run \(testRunId) already completed.")
            }
        } catch {
            // Basic error check, replace with more robust error handling if needed
            let errorDesc = error.localizedDescription

            Self.logger.error("Cannot finish the launch (TestRunID: \(testRunId)): \(errorDesc)")
        }
    }

    // MARK: - Container Lifecycle

    func startMainContainer(container: MainContainer) {
        guard adapterConfig.shouldEnableTmsIntegration, let uuid = container.uuid else { return }

        var mutableContainer = container // Work with a mutable copy if needed
        mutableContainer.start = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, mutableContainer)

        Self.logger.debug("Start new main container \(uuid)")
    }

    func stopMainContainer(uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        guard var container = storage.getTestsContainer(uuid) else {
            Self.logger.error("Could not stop main container: container with uuid \(uuid) not found")
            return
        }
        
        container.stop = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, container) // Update storage with stopped container

        Self.logger.debug("Stop main container \(uuid)")

        writer?.writeTests(container)
    }

    func startClassContainer(parentUuid: String, container: ClassContainer) {
        guard adapterConfig.shouldEnableTmsIntegration, let uuid = container.uuid else { return }

        lock.withLock {
            if var parent = storage.getTestsContainer(parentUuid) {
                parent.children.append(uuid)
                storage.put(parentUuid, parent) // Update parent
            }
        }
        
        var mutableContainer = container
        mutableContainer.start = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, mutableContainer)

        Self.logger.debug("Start new class container \(uuid) for parent \(parentUuid)")
    }

    func stopClassContainer(uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        guard var container = storage.getClassContainer(uuid) else {
            Self.logger.debug("Could not stop class container: container with uuid \(uuid) not found")
            return
        }
        
        container.stop = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, container) // Update storage

        Self.logger.debug("Stop class container \(uuid)")

        writer?.writeClass(container)
    }

    func updateClassContainer(uuid: String, update: (inout ClassContainer) -> Void) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        Self.logger.debug("Update class container \(uuid)")

        // Use lock to ensure thread safety if storage is not inherently thread-safe
        let success = lock.withLock {
            guard var container = storage.getClassContainer(uuid) else {
                return false
            }
            update(&container)
            storage.put(uuid, container) // Put the modified container back
            return true
        }
        
        if !success {
            Self.logger.debug("Could not update class container: container with uuid \(uuid) not found")
        }
    }

    // MARK: - Test Case Lifecycle

    func startTestCase(uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        threadContext.clear() // Consider potential race conditions if called from multiple threads
        
        guard var testResult = storage.getTestResult(uuid) else {
            Self.logger.error("Could not start test case: test case with uuid \(uuid) is not scheduled")
            return
        }

        testResult.setItemStage(stage: .running)
        testResult.start = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, testResult) // Update storage

        threadContext.start(uuid)

        Self.logger.debug("Start test case \(uuid)")
    }

    func scheduleTestCase(result: TestResultCommon) {
        guard adapterConfig.shouldEnableTmsIntegration, let uuid = result.uuid else { return }

        var mutableResult = result
        mutableResult.setItemStage(stage: .scheduled)
        mutableResult.automaticCreationTestCases = adapterConfig.shouldAutomaticCreationTestCases
        storage.put(uuid, mutableResult)

        Self.logger.debug("Schedule test case \(uuid)")
    }
    
    // Update currently running test case
    func updateTestCase(update: (inout TestResultCommon) -> Void) {
         guard adapterConfig.shouldEnableTmsIntegration else { return }

        guard let uuid = threadContext.getRoot() else {
            Self.logger.error("Could not update test case: no test case running according to ThreadContext")
            return
        }
        
        updateTestCase(uuid: uuid, update: update)
    }

    // Update specific test case by UUID
    func updateTestCase(uuid: String, update: (inout TestResultCommon) -> Void) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        Self.logger.debug("Update test case \(uuid)")
        
        let success = lock.withLock {
            guard var testResult = storage.getTestResult(uuid) else {
                return false
            }
            update(&testResult)
            storage.put(uuid, testResult) // Put the modified result back
            return true
        }
        
        if !success {
            Self.logger.error("Could not update test case: test case with uuid \(uuid) not found")
        }
    }

    func stopTestCase(uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        guard var testResult = storage.getTestResult(uuid) else {
            Self.logger.error("Could not stop test case: test case with uuid \(uuid) not found")
            return
        }


        testResult.setItemStage(stage: .finished)
        testResult.stop = Int64(Date().timeIntervalSince1970 * 1000)
        

        if testResult.attachments.count > 0 {
            Self.logger.debug("attachments: \(testResult.attachments)")
            addAttachments(paths: testResult.attachments, uuid: uuid)            
            testResult.attachments = storage.getAttachmentsList(uuid)!
        }

        storage.put(uuid, testResult) // Update storage with final state

        threadContext.clear() // Clear context after stopping

        Self.logger.debug("Stop test case \(uuid)")

        writer?.writeTest(testResult)
    }

    // MARK: - Fixture Lifecycle
    // Note: Simplified fixture association. In Kotlin, it adds the FixtureResult object 
    // directly to the container's list. Here, we update the container fetched from storage.
    // This requires the container to be mutable or re-stored after modification.

    private func addFixtureToMainContainer(parentUuid: String, fixture: FixtureResult, type: MainFixtureType) {
        lock.withLock {
            guard var container = storage.getTestsContainer(parentUuid) else { return }
            switch type {
                case .beforeMethods: container.beforeMethods.append(fixture)
                case .afterMethods: container.afterMethods.append(fixture)
            }
            storage.put(parentUuid, container)
        }
    }
    
    private func addFixtureToClassContainer(parentUuid: String, fixture: FixtureResult, type: ClassFixtureType) {
        lock.withLock {
            guard var container = storage.getClassContainer(parentUuid) else { return }
            switch type {
                case .beforeClass: container.beforeClassMethods.append(fixture)
                case .afterClass: container.afterClassMethods.append(fixture)
                case .beforeEach: container.beforeEachTest.append(fixture)
                case .afterEach: container.afterEachTest.append(fixture)
            }
            storage.put(parentUuid, container)
        }
    }

    private enum MainFixtureType { case beforeMethods, afterMethods }
    private enum ClassFixtureType { case beforeClass, afterClass, beforeEach, afterEach }

    func startPrepareFixtureAll(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start prepare all fixture \(uuid) for parent \(parentUuid)")
        addFixtureToMainContainer(parentUuid: parentUuid, fixture: result, type: .beforeMethods)
        startFixture(uuid: uuid, result: result)
    }

    func startTearDownFixtureAll(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start tear down all fixture \(uuid) for parent \(parentUuid)")
        addFixtureToMainContainer(parentUuid: parentUuid, fixture: result, type: .afterMethods)
        startFixture(uuid: uuid, result: result)
    }

    func startPrepareFixture(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start prepare fixture \(uuid) for parent \(parentUuid)")
        addFixtureToClassContainer(parentUuid: parentUuid, fixture: result, type: .beforeClass)
        startFixture(uuid: uuid, result: result)
    }

    func startTearDownFixture(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start tear down fixture \(uuid) for parent \(parentUuid)")
        addFixtureToClassContainer(parentUuid: parentUuid, fixture: result, type: .afterClass)
        startFixture(uuid: uuid, result: result)
    }

    func startPrepareFixtureEachTest(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start prepare for each test fixture \(uuid) for parent \(parentUuid)")
        addFixtureToClassContainer(parentUuid: parentUuid, fixture: result, type: .beforeEach)
        startFixture(uuid: uuid, result: result)
    }

    func startTearDownFixtureEachTest(parentUuid: String, uuid: String, result: FixtureResult) {
        if !adapterConfig.shouldEnableTmsIntegration { return }
        Self.logger.debug("Start tear down for each test fixture \(uuid) for parent \(parentUuid)")
        addFixtureToClassContainer(parentUuid: parentUuid, fixture: result, type: .afterEach)
        startFixture(uuid: uuid, result: result)
    }

    private func startFixture(uuid: String, result: FixtureResult) {
        // No need to check adapterConfig again, checked by callers
        var mutableResult = result
        mutableResult.itemStage = .running
        mutableResult.start = Int64(Date().timeIntervalSince1970 * 1000)
        storage.put(uuid, mutableResult)

        threadContext.clear() // Fixtures often run in their own context? Check Kotlin logic.
        threadContext.start(uuid)
         Self.logger.debug("Started fixture \(uuid)")
    }

    func updateFixture(uuid: String, update: (inout FixtureResult) -> Void) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }
        Self.logger.debug("Update fixture \(uuid)")

        let success = lock.withLock {
            guard var fixture = storage.getFixture(uuid) else {
                return false
            }
            update(&fixture)
            storage.put(uuid, fixture) // Put the modified fixture back
            return true
        }
        
        if !success {
            Self.logger.error("Could not update test fixture: test fixture with uuid \(uuid) not found")
        }
    }

    func stopFixture(uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }

        // Fetch first to log it before removing
        guard var fixture = storage.getFixture(uuid) else {
            Self.logger.error("Could not stop test fixture: test fixture with uuid \(uuid) not found")
            return
        }

        fixture.itemStage = .finished
        fixture.stop = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Update storage *before* removing? Or just remove?
        // Kotlin removes, so we remove. Log the final state before removing.
        Self.logger.debug("Stop fixture \(uuid): Stage=\(fixture.itemStage?.rawValue ?? "nil"), Status=\(fixture.itemStatus?.rawValue ?? "nil")") 
        storage.remove(uuid) // Remove from storage
        threadContext.clear() // Clear context after fixture stops
    }

    // MARK: - Attachments

    func addAttachments(paths attachmentPaths: [String], uuid: String) {
        guard adapterConfig.shouldEnableTmsIntegration else { return }
        guard let writer = self.writer else {
            Self.logger.error("Cannot add attachments: Writer is not initialized.")
            return
        }

        var attachmentUuids: [String] = []
        for path in attachmentPaths {
            let attachmentId = writer.writeAttachment(path)
            if (attachmentId?.isEmpty ?? true) { // Check if ID is nil or empty
                 Self.logger.warning("Failed to write attachment for path: \(path). Skipping.")
                continue // Continue with next attachment
            }
            attachmentUuids.append(attachmentId!) // Force unwrap because we checked for nil/empty
        }
        
        guard !attachmentUuids.isEmpty else {
            Self.logger.info("No attachments were successfully written.")
            return
        }

        

        // Use the dedicated update method from ResultStorage stub
        storage.updateAttachmentsList(uuid, adding: attachmentUuids)
        Self.logger.debug("Added attachments \(attachmentUuids) to item \(uuid)")
    }

    // MARK: - Mode & Test Run Info


    func getTestFromTestRun() -> [String] {
        guard adapterConfig.shouldEnableTmsIntegration else { return [] }
        
        // Check both non-optional IDs directly
        guard clientConfiguration.testRunId.lowercased() != "null",
              clientConfiguration.configurationId.lowercased() != "null" else {
            Self.logger.warning("Cannot get tests from test run: testRunId or configurationId is not set or is \"null\".")
            return []
        }
        
        // Use the non-optional properties directly
        let testRunId = clientConfiguration.testRunId
        let configId = clientConfiguration.configurationId

        do {
            let testsForRun = try client.getTestFromTestRun(testRunUuid: testRunId, configurationId: configId)
            Self.logger.debug("List of tests from test run \(testRunId): \(testsForRun)")
            return testsForRun
        } catch {
            Self.logger.error("Could not get tests from test run \(testRunId): \(error.localizedDescription)")
            return []
        }
    }

} 
