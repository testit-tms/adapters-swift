import XCTest
import Dispatch
import os.log

// https://developer.apple.com/documentation/xctest/xctestobservation
class OverallLifecycleObserver: NSObject, XCTestObservation {

    // Static singleton instance
    static let shared = OverallLifecycleObserver()

    private var writer: TestItWriter?
    private var appPropertiesInitialized = false
    private var writerInitialized = false // Additional flag for writer
    private var beforeAllCalled = false

    // Storage for XCTIssue of the current test
    private var currentTestBodyIssues: [XCTIssue] = []
    private var currentFixtureIssues: [XCTIssue] = []
    private var currentTestCaseName: String? // For linking issue with specific test

    // Execution context for setUp and tearDown
    private var currentTestCaseInSetUp: XCTestCase?
    private var currentTestCaseInTearDown: XCTestCase?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "OverallLifecycleObserver")


    // Private initializer to ensure the instance is created only through OverallLifecycleObserver.shared
    private override init() {
        
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
        self.logger.info("OverallLifecycleObserver.shared initialized and registered. Setup will occur based on XCTest lifecycle events.")
    }

    deinit {
        // XCTestObservationCenter stores a weak reference, so this may not be needed if shared lives the whole time.
        // But for completeness.
        XCTestObservationCenter.shared.removeTestObserver(self)
        self.logger.info("OverallLifecycleObserver.shared deinitialized and removed.")
    }


    // This method is called before the first test in the bundle
    // not called!
    func testBundleWillStart(_ testBundle: Bundle) {
        self.logger.info("Attempting setup in testBundleWillStart with bundle: \(testBundle.bundleURL.lastPathComponent)")
    }

    func testSuiteWillStart(_ testSuite: XCTestSuite) {
        self.logger.info("Test suite will start: \(testSuite.name)")
        // If dependencies are not yet configured (for example, testBundleWillStart did not work)
        if !appPropertiesInitialized || !writerInitialized {
            self.logger.info("Dependencies not yet fully initialized, attempting setup via testSuiteWillStart.")
            // Try to find .xctest bundle, because Bundle(for: type(of: testSuite)) may be not the right one
            if let xctestBundle = findXCTestBundle() {
                setupDependencies(using: xctestBundle, isPreferredBundle: false) // false, because this is fallback
            } else {
                // If .xctest bundle is not found, try to use suite bundle, but this is less reliable
                let suiteBundle = Bundle(for: type(of: testSuite))
                self.logger.info(".xctest bundle not found, falling back to suiteBundle: \(suiteBundle.bundleURL.lastPathComponent) for setup.")
                setupDependencies(using: suiteBundle, isPreferredBundle: false)
            }
        }

        // on before all (testSuite)
        if !beforeAllCalled {
            let success = waitForAsyncTask {
                guard let strongWriter = self.writer else {
                    self.logger.error("ERROR from testSuiteWillStart Task - Writer is nil.")
                    return
                }
                await strongWriter.onBeforeAll()
                self.beforeAllCalled = true
            }
            self.logger.info("testSuiteWillStart - onBeforeAll completion success: \(success)")
        }
    }


    // This method is called AFTER ALL tests in the bundle have finished
    func testBundleDidFinish(_ testBundle: Bundle) {
        self.logger.info("-------------------------------------")
        self.logger.info(">>> All tests in the bundle did finish! <<<: \(testBundle.bundleURL.lastPathComponent)")
        self.logger.info("-------------------------------------")
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                self.logger.error("ERROR from testBundleDidFinish Task - Writer is nil.")
                return
            }
            await strongWriter.onAfterAll()
        }
        self.logger.info("testBundleDidFinish - onAfterAll completion success: \(success)")
    }
    
    // The rest of the XCTestObservation protocol methods...
    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        self.logger.info("Test suite did finish: \(testSuite.name)")
    }

    // looks like the same as TestItXCTestCase.invokeTest()
    func testCaseWillStart(_ testCase: XCTestCase) {
        self.logger.info("Test case will start: \(testCase.name)")

        // Clear before new test
        self.currentTestBodyIssues = []
        self.currentFixtureIssues = []
        self.currentTestCaseName = testCase.name

        let success = waitForAsyncTask {
            self.logger.info("Task for testCaseWillStart: Calling writer.onTestWillStart for test \(testCase.name)...")
            // Delay removed, because it was not part of the rollback request to waitForAsyncTask
            guard let strongWriter = self.writer else {
                self.logger.error("ERROR from testCaseWillStart Task - Writer is nil.")
                return
            }
            await strongWriter.onTestWillStart(for: testCase)
            self.logger.info("Task for testCaseWillStart: writer.onTestWillStart completed for test \(testCase.name).")
        }
        self.logger.info("testCaseWillStart - onTestWillStart completion success: \(success)")
    }

    // automatically in both success and failure cases
    func testCaseDidFinish(_ testCase: XCTestCase) {
        self.logger.info("Test case did finish: \(testCase.name)")
        let finishTime = Date() // Fix time of test finish

        waitForAsyncTask {
            if let strongWriter = self.writer {
                let fixtureService = strongWriter.fixtureService
                // Complete before-fixture (setUp)
                // If recordFailureInCurrentFixture already marked it as failed and finished, this call will not overwrite the status.
                // If no errors were recorded, it will be marked as passed.
                fixtureService.completeCurrentBeforeFixture(for: testCase, status: .passed, stopTime: finishTime, issue: nil)

                // Complete after-fixture (tearDown)
                // Similarly, if recordFailureInCurrentFixture already marked it as failed and finished, the status will not change.
                // If no errors were recorded, it will be marked as passed.
                // The stop time for tearDown can also be finishTime, or more accurately, if available.
                fixtureService.completeCurrentAfterFixture(for: testCase, status: .passed, stopTime: finishTime, issue: nil)

                // Pass collected issues and testCase to TestItWriter
                await strongWriter.onTestDidFinish(for: testCase, fixtureIssues: self.currentFixtureIssues, testBodyIssues: self.currentTestBodyIssues)
            } else {
                self.logger.error("ERROR from testCaseDidFinish - Writer or FixtureService is nil, cannot complete fixtures or call onTestDidFinish.")
            }
            // Clear issues after processing, prepare for next test
            self.currentTestBodyIssues = []
            self.currentFixtureIssues = []
            self.currentTestCaseName = nil
        }
    }

    // This method will be called for each registered XCTIssue
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        // Save all 'issue', occurred during the test
        // Ensure that issue belongs to the currently processed test, if currentTestCaseName is used for strict checking
        // In this case, simply add it, because testCaseDidFinish will handle everything for the finished test
        self.logger.info("Test case \(testCase.name) recorded issue: \(issue.compactDescription) at \(issue.sourceCodeContext.location?.fileURL.lastPathComponent ?? "unknown file"):\(issue.sourceCodeContext.location?.lineNumber ?? 0)")
        // self.currentTestIssues.append(issue) // Remove old addition

        let context: String
        var isFixtureFailure = false

        if let currentlyInSetUp = self.currentTestCaseInSetUp, currentlyInSetUp === testCase {
            context = "setUp"
            isFixtureFailure = true
            self.logger.info("Issue recorded during setUp of \(testCase.name): \(issue.compactDescription)")
            self.currentFixtureIssues.append(issue) // Add to fixtureIssues
            Task { // Async call, to not block testCase(_:didRecord:)
                await writer?.recordFixtureFailure(for: testCase, issue: issue, fixtureContext: context)
            }
        } else if let currentlyInTearDown = self.currentTestCaseInTearDown, currentlyInTearDown === testCase {
            context = "tearDown"
            isFixtureFailure = true
            self.logger.info("Issue recorded during tearDown of \(testCase.name): \(issue.compactDescription)")
            self.currentFixtureIssues.append(issue) // Add to fixtureIssues
            Task { // Async call
                await writer?.recordFixtureFailure(for: testCase, issue: issue, fixtureContext: context)
            }
        } else {
            // Error occurred in the test body, not in setUp or tearDown.
            self.currentTestBodyIssues.append(issue) // Add to testBodyIssues
            self.logger.info("Issue recorded in test body of \(testCase.name) (or outside specific setUp/tearDown context): \(issue.compactDescription)")
        }

        // Further processing of isFixtureFailure can be here or in writer
    }

    // not called on failing assertions
    func testCase(_ testCase: XCTestCase, didFailWith description: String, inFile filePath: String?, atLine lineNumber: Int) {
        self.logger.info("Test case FAILED: \(testCase.name) - \(description)")
        waitForAsyncTask {
            if let strongWriter = self.writer {
                await strongWriter.onTestFailed(for: testCase)
            } else {
                self.logger.error("ERROR from testCaseDidFinish - Writer is nil, cannot call onTestFailed.")
            }
        }
    }

    func onBeforeSetup(testCase: XCTestCase) {
        self.logger.info("onBeforeSetup for test \(testCase.name)")
        self.currentTestCaseInSetUp = testCase // Set setUp context
        // Your logic for before setup
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                self.logger.error("ERROR from onBeforeSetup Task - Writer is nil.")
                return
            }
            await strongWriter.onBeforeSetup(for: testCase)
        }
        self.logger.info("onBeforeSetup - onBeforeSetup completion success: \(success)")
    }

    func onAfterSetup(testCase: XCTestCase) {
        self.logger.info("onAfterSetup for \(testCase.name)")
        self.currentTestCaseInSetUp = nil // Reset setUp context
        // TODO: Perhaps, here we need to call writer?.onAfterSetup(for: testCase), if such logic is needed
    }

    func onBeforeTeardown(testCase: XCTestCase) {
        self.logger.info("onBeforeTeardown for test \(testCase.name)")
        self.currentTestCaseInTearDown = testCase // Set tearDown context
        // Your logic for before teardown
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                self.logger.error("ERROR from onBeforeTeardown Task - Writer is nil.")
                return
            }
            await strongWriter.onBeforeTeardown(for: testCase)
        }
        self.logger.info("onBeforeTeardown - onBeforeTeardown completion success: \(success)")
    }

    func onAfterTeardown(testCase: XCTestCase) {
        self.logger.info("onAfterTeardown for \(testCase.name)")
        self.currentTestCaseInTearDown = nil // Reset tearDown context
        // TODO: Perhaps, here we need to call writer?.onAfterTeardown(for: testCase), if such logic is needed
    }

    private func setupDependencies(using bundle: Bundle, isPreferredBundle: Bool) {
        // If we have already successfully initialized from the preferred bundle (from testBundleWillStart),
        // and now we received a call with isPreferredBundle = false (from testSuiteWillStart), then do nothing.
        if appPropertiesInitialized && !isPreferredBundle && writerInitialized {
            self.logger.info("Dependencies already initialized, skipping setup from non-preferred bundle: \(bundle.bundleURL.lastPathComponent)")
            return
        }
        
        self.logger.info("Running setupDependencies with bundle: \(bundle.bundleURL.lastPathComponent), isPreferred: \(isPreferredBundle)")

        if !appPropertiesInitialized {
            let propertiesFileName = "testit"
            let propertiesExtension = "properties"
            self.logger.info("Attempting to load AppProperties from bundle: \(bundle.bundleURL.lastPathComponent)")
            guard let propertiesURL = bundle.url(forResource: propertiesFileName, withExtension: propertiesExtension) else {
                self.logger.warning("Warning: File \(propertiesFileName).\(propertiesExtension) not found in bundle \(bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent). AppProperties will not be initialized from this bundle.")
                return
            }
            do {
                let propertiesContent = try String(contentsOf: propertiesURL, encoding: .utf8)
                AppProperties.initialize(propertiesString: propertiesContent)
                self.logger.info("AppProperties initialized. Content loaded from: \(propertiesURL.path)")
                appPropertiesInitialized = true
            } catch {
                self.logger.warning("Error reading properties file \(propertiesURL.path): \(error). AppProperties will not be initialized.")
                return
            }
        }

        if !writerInitialized {
            guard appPropertiesInitialized else {
                 self.logger.error("ERROR - AppProperties not initialized, cannot create TestItWriter.")
                 return
            }
            writer = TestItWriter()
            writerInitialized = true
            self.logger.info("TestItWriter initialized.")
        }
    }

    
    private func findXCTestBundle() -> Bundle? {
        for bundle in Bundle.allBundles {
            // Search for bundles with .xctest extension
            if bundle.bundlePath.hasSuffix(".xctest") {
                self.logger.info("Found .xctest bundle via findXCTestBundle: \(bundle.bundleURL.lastPathComponent)")
                return bundle
            }
        }
        self.logger.info("No .xctest bundle found via findXCTestBundle.")
        return nil
    }


    /// Synchronously waits for the completion of an asynchronous operation with a timeout.
    /// - Parameters:
    ///   - timeout: Maximum waiting time in seconds.
    ///   - operation: Asynchronous operation to execute.
    /// - Returns: `true`, if the operation completed before the timeout, otherwise `false`.
    private func waitForAsyncTask(
        timeout: TimeInterval = 500.0, 
        operation: @escaping () async -> Void
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            await operation()
            semaphore.signal() // Signal about the completion of the operation
        }

        // Wait for the signal from the semaphore, but not longer than the specified timeout
        let result = semaphore.wait(timeout: .now() + timeout)

        if result == .timedOut {
            self.logger.info("waitForAsyncTask timed out after \(timeout) seconds.")
            return false
        }
        return true
    }
}
