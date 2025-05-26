import Foundation
import OSLog
import XCTest

final class FixtureService {
    private let adapterManager: AdapterManager
    private let executableTestService: ExecutableTestService
    private let testService: TestService
    private let isStepContainers: Bool

    private var beforeFixtureUUID: String?
    private var afterFixtureUUID: String?

    private let logger = Logger()
    
    init(adapterManager: AdapterManager,
         executableTestService: ExecutableTestService,
         testService: TestService,
         isStepContainers: Bool) {
        self.adapterManager = adapterManager
        self.executableTestService = executableTestService
        self.testService = testService
        self.isStepContainers = isStepContainers
    }

    // MARK: - Before Test Management

    func onBeforeTestStart(testCase: XCTestCase, start: TimeInterval, lastClassContainerId: String) {
        logger.debug("Before test started")
        
        let parentUuid = executableTestService.getUuid(testName: testCase.name)
        let fixtureResult = FixtureResult(
            name: "Setup",
            itemStage: .running,
            parent: parentUuid,
            start: Int64(start * 1000)
        )
        beforeFixtureUUID = UUID().uuidString
        adapterManager.startPrepareFixtureEachTest(
            parentUuid: lastClassContainerId,
            uuid: beforeFixtureUUID!,
            result: fixtureResult
        )
    }


    // MARK: - After Test Management

    func onAfterTestStart(testCase: XCTestCase, start: TimeInterval, lastClassContainerId: String) {
        logger.debug("After test registered/started (new logic)")
        
        let parentUuid = executableTestService.getUuid(testName: testCase.name)
        let fixtureResult = FixtureResult(
            name: "TearDown", // Name for teardown
            itemStage: .running,
            parent: parentUuid,
            start: Int64(start * 1000)
        )
        afterFixtureUUID = UUID().uuidString
        adapterManager.startTearDownFixtureEachTest(
            parentUuid: lastClassContainerId,
            uuid: afterFixtureUUID!,
            result: fixtureResult
        )
    }


    // MARK: - Fixture Failures Handling

    func recordFailureInCurrentFixture(for testCase: XCTestCase, issue: XCTIssue, context: String) async {
        logger.debug("Recording failure in fixture for test \(testCase.name) during \(context). Issue: \(issue.compactDescription)")

        let fixtureUuidToUpdate: String?
        let fixtureName: String

        if context == "setUp" {
            fixtureUuidToUpdate = self.beforeFixtureUUID
            fixtureName = testCase.setupName() ?? "Setup"
        } else if context == "tearDown" {
            fixtureUuidToUpdate = self.afterFixtureUUID
            fixtureName = testCase.teardownName() ?? "TearDown"
        } else {
            logger.error("Unknown fixture context: \(context)")
            return
        }

        guard let uuid = fixtureUuidToUpdate else {
            logger.error("Could not record fixture failure: UUID for \(context) fixture is nil.")
            return
        }

        let stopTime = Int64(Date().timeIntervalSince1970 * 1000)

        adapterManager.updateFixture(uuid: uuid) { fixtureResult in
            fixtureResult.name = fixtureName // Update name in case
            fixtureResult.itemStatus = .failed
            fixtureResult.itemStage = .finished // Error completes the fixture
            fixtureResult.stop = stopTime
            let issueDescription = issue.compactDescription
            let trace = issue.detailedDescription ?? issue.sourceCodeContext.description
            fixtureResult.description = (fixtureResult.description ?? "") + "\nError: " + issueDescription
            fixtureResult.trace = (fixtureResult.trace ?? "") + "\n" + trace
        }
        
        // Important: Do NOT call adapterManager.stopFixture(uuid: uuid) here,
        // to keep the information about the failed fixture for HttpWriter.
        // The stopFixture logic is already present in onXYZTestOk/Failed methods, we need to review it.
        logger.debug("Updated fixture \(uuid) for \(context) with failure details.")
    }

    func completeCurrentBeforeFixture(for testCase: XCTestCase, status: ItemStatus, stopTime: Date, issue: XCTIssue? = nil) {
        guard let uuid = self.beforeFixtureUUID else {
            logger.error("Cannot complete beforeFixture: UUID is nil.")
            return
        }

        adapterManager.updateFixture(uuid: uuid) { fixtureResult in
            // Finish fixture only if it is not finished yet (for example, through recordFailureInCurrentFixture)
            if fixtureResult.itemStage != .finished {
                fixtureResult.name = testCase.setupName() ?? "Setup"
                fixtureResult.itemStatus = status
                fixtureResult.stop = Int64(stopTime.timeIntervalSince1970 * 1000)
                fixtureResult.itemStage = .finished

                if let anIssue = issue {
                    let issueDescription = anIssue.compactDescription
                    let trace = anIssue.detailedDescription ?? anIssue.sourceCodeContext.description
                    fixtureResult.description = (fixtureResult.description ?? "") + "\nError: " + issueDescription
                    fixtureResult.trace = (fixtureResult.trace ?? "") + "\n" + trace
                }
                self.logger.debug("Completed beforeFixture \(uuid) for test \(testCase.name) with status \(status.rawValue)")
            } else {
                self.logger.debug("BeforeFixture \(uuid) for test \(testCase.name) was already finished. Current status:")// \(fixtureResult.itemStatus!.rawValue)")
            }
        }
        // Do NOT call adapterManager.stopFixture(uuid: uuid) here
    }

    func completeCurrentAfterFixture(for testCase: XCTestCase, status: ItemStatus, stopTime: Date, issue: XCTIssue? = nil) {
        guard let uuid = self.afterFixtureUUID else {
            logger.error("Cannot complete afterFixture: UUID is nil.")
            return
        }

        adapterManager.updateFixture(uuid: uuid) { fixtureResult in
            // Finish fixture only if it is not finished yet
            if fixtureResult.itemStage != .finished {
                fixtureResult.name = testCase.teardownName() ?? "TearDown"
                fixtureResult.itemStatus = status
                fixtureResult.stop = Int64(stopTime.timeIntervalSince1970 * 1000)
                fixtureResult.itemStage = .finished

                if let anIssue = issue {
                    let issueDescription = anIssue.compactDescription
                    let trace = anIssue.detailedDescription ?? anIssue.sourceCodeContext.description
                    fixtureResult.description = (fixtureResult.description ?? "") + "\nError: " + issueDescription
                    fixtureResult.trace = (fixtureResult.trace ?? "") + "\n" + trace
                }
                self.logger.debug("Completed afterFixture \(uuid) for test \(testCase.name) with status \(status.rawValue)")
            } else {
                self.logger.debug("AfterFixture \(uuid) for test \(testCase.name) was already finished. Current status:")// \(fixtureResult.itemStatus!.rawValue)")
            }
        }
        // Do NOT call adapterManager.stopFixture(uuid: uuid) here
    }

}


// Utility functions/extensions potentially needed for XCTestCase
extension XCTestCase {
    // Placeholder implementations - replace with actual logic if needed
    func setupName() -> String? { return "setUp" } 
    func teardownName() -> String? { return "tearDown" }
}
