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
        // Print to stdout for visibility in swift test runs
        print("[TestItAdapter] OverallLifecycleObserver initialized and registered in XCTestObservationCenter")
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
        print("[TestItAdapter] testSuiteWillStart: \(testSuite.name)")
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
        print("[TestItAdapter] ============================================")
        print("[TestItAdapter] >>> All tests in the bundle did finish! <<<")
        print("[TestItAdapter] ============================================")
        self.logger.info("-------------------------------------")
        self.logger.info(">>> All tests in the bundle did finish! <<<: \(testBundle.bundleURL.lastPathComponent)")
        self.logger.info("-------------------------------------")
        let success = waitForAsyncTask {
            guard let strongWriter = self.writer else {
                print("[TestItAdapter] ERROR: Writer is nil in testBundleDidFinish")
                self.logger.error("ERROR from testBundleDidFinish Task - Writer is nil.")
                return
            }
            print("[TestItAdapter] Calling onAfterAll...")
            await strongWriter.onAfterAll()
            print("[TestItAdapter] onAfterAll completed")
        }
        print("[TestItAdapter] testBundleDidFinish - onAfterAll completion success: \(success)")
        self.logger.info("testBundleDidFinish - onAfterAll completion success: \(success)")
    }
    
    // The rest of the XCTestObservation protocol methods...
    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        self.logger.info("Test suite did finish: \(testSuite.name)")
    }

    // looks like the same as TestItXCTestCase.invokeTest()
    func testCaseWillStart(_ testCase: XCTestCase) {
        print("[TestItAdapter] testCaseWillStart: \(testCase.name)")
        self.logger.info("Test case will start: \(testCase.name)")

        // CRITICAL: If testSuiteWillStart wasn't called (common in swift test), initialize dependencies here
        if !appPropertiesInitialized || !writerInitialized {
            print("[TestItAdapter] Dependencies not initialized, attempting setup in testCaseWillStart")
            self.logger.info("Dependencies not yet initialized, attempting setup via testCaseWillStart (fallback for swift test).")
            
            // First try test case bundle - this is most reliable for SPM
            let testCaseBundle = Bundle(for: type(of: testCase))
            print("[TestItAdapter] Test case bundle: \(testCaseBundle.bundleURL.lastPathComponent)")
            
            var dependenciesSetup = false
            
            // In SPM, resources are often in a separate .bundle file (not .xctest)
            // Search all bundles for one containing testit.properties
            // Also try to explicitly load .bundle files from common locations
            print("[TestItAdapter] Searching for bundle with testit.properties...")
            print("[TestItAdapter] Available bundles count: \(Bundle.allBundles.count)")
            
            // First, try all currently loaded bundles
            for bundle in Bundle.allBundles {
                let bundlePath = bundle.bundlePath
                // Check if this is a test-related bundle
                if bundlePath.contains("Tests") || bundlePath.hasSuffix(".bundle") || bundlePath.hasSuffix(".xctest") {
                    print("[TestItAdapter] Checking bundle: \(bundle.bundleURL.lastPathComponent)")
                    if let resourcePath = bundle.resourcePath {
                        // Try direct path first
                        let propertiesPath = (resourcePath as NSString).appendingPathComponent("testit.properties")
                        if FileManager.default.fileExists(atPath: propertiesPath) {
                            print("[TestItAdapter] ✓ Found bundle with testit.properties: \(bundle.bundleURL.lastPathComponent) (path: \(propertiesPath))")
                            setupDependencies(using: bundle, isPreferredBundle: false)
                            dependenciesSetup = true
                            break
                        }
                        // Try recursive search in subdirectories
                        let fileManager = FileManager.default
                        if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                            while let element = enumerator.nextObject() as? String {
                                if element.hasSuffix("testit.properties") {
                                    let foundPath = (resourcePath as NSString).appendingPathComponent(element)
                                    print("[TestItAdapter] ✓ Found bundle with testit.properties (recursive): \(bundle.bundleURL.lastPathComponent) at \(foundPath)")
                                    setupDependencies(using: bundle, isPreferredBundle: false)
                                    dependenciesSetup = true
                                    break
                                }
                            }
                            if dependenciesSetup { break }
                        }
                    }
                }
            }
            
            // Try to explicitly load .bundle file if it exists but wasn't loaded
            if !dependenciesSetup {
                let xctestPath = testCaseBundle.bundlePath
                let basePath = (xctestPath as NSString).deletingLastPathComponent
                
                // Construct possible bundle paths
                let xctestName = (xctestPath as NSString).lastPathComponent
                let bundleName = xctestName.replacingOccurrences(of: ".xctest", with: ".bundle")
                let bundleNameAlt = xctestName.replacingOccurrences(of: "PackageTests.xctest", with: "_examples-spmTests.bundle")
                
                let possibleBundlePaths = [
                    (basePath as NSString).appendingPathComponent(bundleName),
                    (basePath as NSString).appendingPathComponent(bundleNameAlt),
                    ((basePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(bundleName),
                    ((basePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent(bundleNameAlt),
                ]
                
                print("[TestItAdapter] Trying to load bundle from paths:")
                for bundlePathString in possibleBundlePaths {
                    print("[TestItAdapter]   - \(bundlePathString)")
                    if FileManager.default.fileExists(atPath: bundlePathString) {
                        print("[TestItAdapter]   ✓ Bundle exists: \(bundlePathString)")
                        if let bundle = Bundle(path: bundlePathString) {
                            print("[TestItAdapter]   ✓ Bundle loaded: \(bundle.bundleURL.lastPathComponent)")
                            if let resourcePath = bundle.resourcePath {
                                print("[TestItAdapter]   Resource path: \(resourcePath)")
                                let propertiesPath = (resourcePath as NSString).appendingPathComponent("testit.properties")
                                if FileManager.default.fileExists(atPath: propertiesPath) {
                                    print("[TestItAdapter] ✓✓✓ Found testit.properties in explicitly loaded bundle: \(propertiesPath)")
                                    setupDependencies(using: bundle, isPreferredBundle: false)
                                    dependenciesSetup = true
                                    break
                                }
                                // Try recursive search
                                let fileManager = FileManager.default
                                if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                                    while let element = enumerator.nextObject() as? String {
                                        if element.hasSuffix("testit.properties") {
                                            let foundPath = (resourcePath as NSString).appendingPathComponent(element)
                                            print("[TestItAdapter] ✓✓✓ Found testit.properties (recursive) in explicitly loaded bundle: \(foundPath)")
                                            setupDependencies(using: bundle, isPreferredBundle: false)
                                            dependenciesSetup = true
                                            break
                                        }
                                    }
                                    if dependenciesSetup { break }
                                }
                            }
                        }
                    }
                }
            }
            
            // Try finding resource file in test case bundle's resourcePath
            if !dependenciesSetup, let bundlePath = testCaseBundle.resourcePath {
                var propertiesPath = (bundlePath as NSString).appendingPathComponent("testit.properties")
                if FileManager.default.fileExists(atPath: propertiesPath) {
                    print("[TestItAdapter] Found testit.properties at: \(propertiesPath)")
                    do {
                        let propertiesContent = try String(contentsOfFile: propertiesPath, encoding: .utf8)
                        AppProperties.initialize(propertiesString: propertiesContent)
                        print("[TestItAdapter] AppProperties initialized from: \(propertiesPath)")
                        appPropertiesInitialized = true
                        
                        if !writerInitialized {
                            writer = TestItWriter()
                            writerInitialized = true
                            print("[TestItAdapter] TestItWriter initialized successfully")
                        }
                        dependenciesSetup = true
                    } catch {
                        print("[TestItAdapter] ERROR reading properties file: \(error)")
                    }
                } else {
                    // Try recursive search
                    let fileManager = FileManager.default
                    if let enumerator = fileManager.enumerator(atPath: bundlePath) {
                        while let element = enumerator.nextObject() as? String {
                            if element.hasSuffix("testit.properties") {
                                propertiesPath = (bundlePath as NSString).appendingPathComponent(element)
                                print("[TestItAdapter] Found testit.properties recursively at: \(propertiesPath)")
                                do {
                                    let propertiesContent = try String(contentsOfFile: propertiesPath, encoding: .utf8)
                                    AppProperties.initialize(propertiesString: propertiesContent)
                                    print("[TestItAdapter] AppProperties initialized from: \(propertiesPath)")
                                    appPropertiesInitialized = true
                                    
                                    if !writerInitialized {
                                        writer = TestItWriter()
                                        writerInitialized = true
                                        print("[TestItAdapter] TestItWriter initialized successfully")
                                    }
                                    dependenciesSetup = true
                                    break
                                } catch {
                                    print("[TestItAdapter] ERROR reading properties file: \(error)")
                                }
                            }
                        }
                    }
                }
            }
            
            // Fallback to findXCTestBundle
            if !dependenciesSetup {
                if let xctestBundle = findXCTestBundle() {
                    setupDependencies(using: xctestBundle, isPreferredBundle: false)
                } else {
                    setupDependencies(using: testCaseBundle, isPreferredBundle: false)
                }
            }
        }

        // CRITICAL: Call onBeforeAll if testSuiteWillStart wasn't called (fallback for swift test)
        // MUST be called BEFORE onTestWillStart to ensure test run is created
        if !beforeAllCalled {
            print("[TestItAdapter] testSuiteWillStart not called, calling onBeforeAll in testCaseWillStart")
            let beforeAllSuccess = waitForAsyncTask {
                guard let strongWriter = self.writer else {
                    self.logger.error("ERROR from testCaseWillStart onBeforeAll Task - Writer is nil.")
                    return
                }
                await strongWriter.onBeforeAll()
                self.beforeAllCalled = true
            }
            print("[TestItAdapter] onBeforeAll completed: \(beforeAllSuccess)")
        }

        // Clear before new test
        self.currentTestBodyIssues = []
        self.currentFixtureIssues = []
        self.currentTestCaseName = testCase.name

        // CRITICAL: Call onTestWillStart to initialize test UUID BEFORE test starts
        print("[TestItAdapter] Calling onTestWillStart for: \(testCase.name)")
        let success = waitForAsyncTask {
            self.logger.info("Task for testCaseWillStart: Calling writer.onTestWillStart for test \(testCase.name)...")
            guard let strongWriter = self.writer else {
                print("[TestItAdapter] ERROR: Writer is nil in testCaseWillStart")
                self.logger.error("ERROR from testCaseWillStart Task - Writer is nil.")
                return
            }
            await strongWriter.onTestWillStart(for: testCase)
            print("[TestItAdapter] onTestWillStart completed for: \(testCase.name)")
            self.logger.info("Task for testCaseWillStart: writer.onTestWillStart completed for test \(testCase.name).")
        }
        print("[TestItAdapter] testCaseWillStart - onTestWillStart completion success: \(success)")
        self.logger.info("testCaseWillStart - onTestWillStart completion success: \(success)")
    }

    // automatically in both success and failure cases
    func testCaseDidFinish(_ testCase: XCTestCase) {
        print("[TestItAdapter] testCaseDidFinish: \(testCase.name)")
        self.logger.info("Test case did finish: \(testCase.name)")
        let finishTime = Date() // Fix time of test finish

        waitForAsyncTask {
            if let strongWriter = self.writer {
                print("[TestItAdapter] Writer available, processing test finish...")
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
                print("[TestItAdapter] Calling onTestDidFinish for: \(testCase.name)")
                await strongWriter.onTestDidFinish(for: testCase, fixtureIssues: self.currentFixtureIssues, testBodyIssues: self.currentTestBodyIssues)
                print("[TestItAdapter] onTestDidFinish completed for: \(testCase.name)")
            } else {
                print("[TestItAdapter] ERROR: Writer is nil in testCaseDidFinish")
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
            print("[TestItAdapter] Attempting to load AppProperties from bundle: \(bundle.bundleURL.lastPathComponent)")
            self.logger.info("Attempting to load AppProperties from bundle: \(bundle.bundleURL.lastPathComponent)")
            
            var propertiesURL: URL?
            
            // Try standard Bundle API first
            propertiesURL = bundle.url(forResource: propertiesFileName, withExtension: propertiesExtension)
            
            // Fallback: try resourcePath for SPM packages
            if propertiesURL == nil, let resourcePath = bundle.resourcePath {
                // Try directly in resourcePath
                var propertiesPath = (resourcePath as NSString).appendingPathComponent("\(propertiesFileName).\(propertiesExtension)")
                if FileManager.default.fileExists(atPath: propertiesPath) {
                    propertiesURL = URL(fileURLWithPath: propertiesPath)
                    print("[TestItAdapter] Found properties file via resourcePath: \(propertiesPath)")
                } else {
                    // Try searching recursively in resourcePath
                    let fileManager = FileManager.default
                    if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                        while let element = enumerator.nextObject() as? String {
                            if element.hasSuffix("\(propertiesFileName).\(propertiesExtension)") {
                                propertiesPath = (resourcePath as NSString).appendingPathComponent(element)
                                propertiesURL = URL(fileURLWithPath: propertiesPath)
                                print("[TestItAdapter] Found properties file recursively: \(propertiesPath)")
                                break
                            }
                        }
                    }
                }
            }
            
            guard let finalPropertiesURL = propertiesURL else {
                print("[TestItAdapter] WARNING: File \(propertiesFileName).\(propertiesExtension) not found in bundle \(bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent)")
                self.logger.warning("Warning: File \(propertiesFileName).\(propertiesExtension) not found in bundle \(bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent). AppProperties will not be initialized from this bundle.")
                return
            }
            
            do {
                let propertiesContent = try String(contentsOf: finalPropertiesURL, encoding: .utf8)
                AppProperties.initialize(propertiesString: propertiesContent)
                print("[TestItAdapter] AppProperties initialized successfully from: \(finalPropertiesURL.path)")
                self.logger.info("AppProperties initialized. Content loaded from: \(finalPropertiesURL.path)")
                appPropertiesInitialized = true
            } catch {
                print("[TestItAdapter] ERROR reading properties file \(finalPropertiesURL.path): \(error)")
                self.logger.warning("Error reading properties file \(finalPropertiesURL.path): \(error). AppProperties will not be initialized.")
                return
            }
        }

        if !writerInitialized {
            guard appPropertiesInitialized else {
                print("[TestItAdapter] ERROR - AppProperties not initialized, cannot create TestItWriter.")
                self.logger.error("ERROR - AppProperties not initialized, cannot create TestItWriter.")
                return
            }
            writer = TestItWriter()
            writerInitialized = true
            print("[TestItAdapter] TestItWriter initialized successfully")
            self.logger.info("TestItWriter initialized.")
        }
    }

    
    private func findXCTestBundle() -> Bundle? {
        // First, try to find bundle that actually contains testit.properties
        // In SPM, resources are often in a .bundle file, not .xctest
        // Prioritize bundles that contain the properties file
        for bundle in Bundle.allBundles {
            let bundlePath = bundle.bundlePath
            // Check if this bundle might contain test resources
            if bundlePath.contains("Tests") || bundlePath.contains("test") || bundlePath.contains("PackageTests") || bundlePath.hasSuffix(".bundle") || bundlePath.hasSuffix(".xctest") {
                // Check via resourcePath (most reliable for SPM)
                if let resourcePath = bundle.resourcePath {
                    // Try direct path first
                    let propertiesPath = (resourcePath as NSString).appendingPathComponent("testit.properties")
                    if FileManager.default.fileExists(atPath: propertiesPath) {
                        print("[TestItAdapter] Found bundle with testit.properties: \(bundle.bundleURL.lastPathComponent)")
                        return bundle
                    }
                    // Try recursive search in subdirectories
                    let fileManager = FileManager.default
                    if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                        while let element = enumerator.nextObject() as? String {
                            if element.hasSuffix("testit.properties") {
                                print("[TestItAdapter] Found bundle with testit.properties (recursive): \(bundle.bundleURL.lastPathComponent)")
                                return bundle
                            }
                        }
                    }
                }
                // Also check via standard Bundle API
                if bundle.url(forResource: "testit", withExtension: "properties") != nil {
                    print("[TestItAdapter] Found bundle with testit.properties (via API): \(bundle.bundleURL.lastPathComponent)")
                    return bundle
                }
            }
        }
        
        // Fallback: return .xctest bundle if no bundle with resources found
        // This allows setupDependencies to try alternative search methods
        for bundle in Bundle.allBundles {
            if bundle.bundlePath.hasSuffix(".xctest") {
                print("[TestItAdapter] No bundle with resources found, using .xctest bundle: \(bundle.bundleURL.lastPathComponent)")
                return bundle
            }
        }
        
        print("[TestItAdapter] No suitable bundle found")
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
