import Foundation
import XCTest
import os.log

// IssueType
public enum IssueTypeCopy : Int {

    /// Issue raised by a failed XCTAssert or related API.
    case assertionFailure = 0
    /// Issue raised by the test throwing an error in Swift. This could also occur if an Objective C test is implemented in the form `- (BOOL)testFoo:(NSError **)outError` and returns NO with a non-nil out error.
    case thrownError = 1
    /// Code in the test throws and does not catch an exception, Objective C, C++, or other.
    case uncaughtException = 2
    /// One of the XCTestCase(measure:) family of APIs detected a performance regression.
    case performanceRegression = 3
    /// One of the framework APIs failed internally. For example, XCUIApplication was unable to launch or terminate an app or XCUIElementQuery was unable to complete a query.
    case system = 4
    /// Issue raised when XCTExpectFailure is used but no matching issue is recorded.
    case unmatchedExpectedFailure = 5
}

final class TestItWriter {

    private let adapterManager = Adapter.getAdapterManager()
    private var uuids: [String: String] = [: ]
    private var context = [String: TestItContext]()
    private var params = [String: TestItParams]()

    private var lastClassContainerId: String?
    private var lastMainContainerId: String?
    private var beforeTestStart: TimeInterval = 0
    private var afterTestStart: TimeInterval = 0

    private let executableTestService: ExecutableTestService
    private let testService: TestService
    let fixtureService: FixtureService

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "TestItWriter")


    init() {
        self.executableTestService = Adapter.getExecutableTestService()

        self.testService = TestService(
            adapterManager: adapterManager,
            uuids: uuids,
            isStepContainers: false,
            executableTestService: self.executableTestService
        )

        self.fixtureService = FixtureService(
            adapterManager: adapterManager,
            executableTestService: self.executableTestService,
            testService: testService,
            isStepContainers: false
        )
    }

    // MARK: - Lifecycle Hooks

    func onBeforeAll() async {
        let rootTestName = "Unknown"
        await runContainers(rootTestName: rootTestName)
        await stopContainers(rootTestName: rootTestName)
    }

    func onAfterAll() async {
        let rootTestName = "Unknown"
        await stopContainers(rootTestName: rootTestName)
    }

    func recordFixtureFailure(for testCase: XCTestCase, issue: XCTIssue, fixtureContext: String) async {
        await fixtureService.recordFailureInCurrentFixture(for: testCase, issue: issue, context: fixtureContext)
    }

    func onTestWillStart(for testCase: XCTestCase) async {
        // logger.info("TestItWriter.onTestWillStart called...")
        await onTestStart(testCase: testCase)
    }

    
    func onTestDidFinish(for testCase: XCTestCase, fixtureIssues: [XCTIssue], testBodyIssues: [XCTIssue]) async {
        // logger.info("TestItWriter.onTestDidFinish called with \(fixtureIssues.count) fixture issues and \(testBodyIssues.count) test body issues.")

        // Determine the status and extract details from XCTIssue (now from testBodyIssues)
        let succeeded = testCase.testRun?.hasSucceeded ?? true 
        // testRun?.hasSucceeded will be false if there were assertions or uncaught errors in the test body.
        // If testRun == nil (for example, the test did not start), we consider succeeded = true (did not fail).

        var finalStatus: ItemStatus
        var combinedMessage: String? = nil
        var combinedTrace: String? = nil

        // Check succeeded (which reflects the result of the main test body)
        // and the presence of critical issues in testBodyIssues.
        // Fixture errors are already processed by FixtureService and will affect FixtureResult.
        let hasCriticalBodyIssues = testBodyIssues.contains { $0.type == .assertionFailure || $0.type == .thrownError }

        if !succeeded || hasCriticalBodyIssues {
            finalStatus = .failed

            var messagesArray: [String] = []
            var tracesArray: [String] = []

            for issue in testBodyIssues { // Use testBodyIssues
                if issue.type == .assertionFailure || issue.type == .thrownError {
                    messagesArray.append(issue.compactDescription)
                    if let location = issue.sourceCodeContext.location {
                        let fileName = location.fileURL.lastPathComponent
                        tracesArray.append("\(fileName):\(location.lineNumber)")
                    }
                }
            }
            
            combinedMessage = messagesArray.joined(separator: "\n")
            if combinedMessage?.isEmpty ?? true {
                if !succeeded {
                    combinedMessage = "Test failed due to an uncaught exception or unknown reason in test body."
                } else {
                    combinedMessage = "Test marked as failed by XCTest, but no specific assertion messages found in critical test body issues."
                }
            }
            combinedTrace = tracesArray.joined(separator: "\n---\n")
        } else {
            finalStatus = .passed
        }

        // fixtureIssues can be used for additional logging here if needed
        if !fixtureIssues.isEmpty {
            logger.info("TestItWriter: \(fixtureIssues.count) issues were recorded in setUp/tearDown and handled by FixtureService.")
            for issue in fixtureIssues {
                logger.info("  - Fixture Issue: \(issue.compactDescription) at \(issue.sourceCodeContext.location?.fileURL.lastPathComponent ?? "unknown"):\(issue.sourceCodeContext.location?.lineNumber ?? 0)")
            }
        }

        await testService.stopTestWithResult(
            testCase: testCase, 
            status: finalStatus, 
            message: combinedMessage, 
            trace: combinedTrace
        )
    }
    //  result: TestResultCommon
    func onTestFailed(for testCase: XCTestCase) async {
        // logger.info("TestItWriter.onTestFailed called...")
        // await testService.onTestFailed(testCase: testCase)
    }

    func onBeforeSetup(for testCase: XCTestCase) async {
        beforeTestStart = Date().timeIntervalSince1970 * 1000
        await fixtureService.onBeforeTestStart(testCase: testCase, start: beforeTestStart, lastClassContainerId: lastClassContainerId!)
    }

    func onBeforeTeardown(for testCase: XCTestCase) async {
        afterTestStart = Date().timeIntervalSince1970 * 1000
        guard let classContainerId = self.lastClassContainerId else {
            logger.error("Error in onBeforeTeardown: lastClassContainerId is nil for test \(testCase.name)")
            return
        }
        await fixtureService.onAfterTestStart(testCase: testCase, start: afterTestStart, lastClassContainerId: classContainerId)
    }

    // MARK: - Private Helpers

    private func onTestStart(testCase: XCTestCase) async {
        let testName = testCase.name
        executableTestService.refreshUuid(testName: testName)
        executableTestService.setTestStatus(testName: testName)
        guard let uuid = executableTestService.getUuid(testName: testName) else {
            logger.error("Error: Could not get UUID for starting test: \(testName)")
            return
        }
        await testService.onTestStart(testCase: testCase, uuid: uuid)
        
        guard let parentId = lastMainContainerId else {
            logger.error("Error: lastMainContainerId is nil in runContainers")
            return
        }
        let containerHash = Utils.getHash(testName)
        lastClassContainerId = containerHash
        let classContainer = ClassContainer(uuid: containerHash)
        await adapterManager.startClassContainer(parentUuid: parentId, container: classContainer)
        adapterManager.updateClassContainer(uuid: containerHash) { container in
            container.children.append(uuid)
        }
    }


    private func runContainers(rootTestName: String) async {
        await adapterManager.createTestRunIfNeeded()
        lastMainContainerId = UUID().uuidString
        guard let parentId = lastMainContainerId else {
            logger.error("Error: lastMainContainerId is nil in runContainers")
            return
        }
        let mainContainer = MainContainer(uuid: parentId)
        await adapterManager.startMainContainer(container: mainContainer)

        let rootHash = Utils.getHash(rootTestName)
        lastClassContainerId = rootHash
        let classContainer = ClassContainer(uuid: rootHash)
        await adapterManager.startClassContainer(parentUuid: parentId, container: classContainer)
    }

    private func stopContainers(rootTestName: String) async {
        let rootHash = Utils.getHash(rootTestName)
        await adapterManager.stopClassContainer(uuid: rootHash)
        if let mainId = lastMainContainerId {
             await adapterManager.stopMainContainer(uuid: mainId)
        }
    }
}
