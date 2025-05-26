import Foundation
import os.log
import XCTest

final class TestService {
    private let adapterManager: AdapterManager
    private var uuids: [String: String]
    private let isStepContainers: Bool
    private let executableTestService: ExecutableTestService

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "TestService")

    init(adapterManager: AdapterManager,
         uuids: [String: String],
         isStepContainers: Bool,
         executableTestService: ExecutableTestService) {
        self.adapterManager = adapterManager
        self.uuids = uuids
        self.isStepContainers = isStepContainers
        self.executableTestService = executableTestService
    }

    // MARK: - Test Lifecycle

    func onTestStart(testCase: XCTestCase, uuid: String) async {
        Self.logger.info("TestService.onTestStart called... with uuid: \(uuid)")
        
        let className = String(describing: type(of: testCase))
        let testName = testCase.name
        let spaceName = TestItContext.getNamespace(from: testCase)
        // let spaceName = "default"

        let result = TestResultCommon(
            uuid: uuid,
            externalId: Utils.genExternalID(testName),
            className: className,
            spaceName: spaceName,
            labels: [],
            linkItems: [],
            name: testName
        )
        
        uuids[testCase.name] = uuid
        await adapterManager.scheduleTestCase(result: result)
        await adapterManager.startTestCase(uuid: uuid)
    }

   

    func stopTestWithResult(testCase: XCTestCase, status: ItemStatus, message: String?, trace: String?) async {
        Self.logger.debug("TestService.stopTestWithResult called for test: \(testCase.name) with status: \(String(describing: status))")
        
        executableTestService.setAfterStatus(testName: testCase.name)
        
        guard let uuid = executableTestService.getUuid(testName: testCase.name) else {
            Self.logger.error("Could not get UUID for test: \(testCase.name) in stopTestWithResult.")
            return
        }

        var finalItemStatus: ItemStatus = .failed
        var errorForThrowable: Error? = nil

        switch status {
        case .passed:
            finalItemStatus = .passed
            Self.logger.debug("Test successful: \(testCase.name)")
        case .failed:
            finalItemStatus = .failed
            if let msg = message {
                errorForThrowable = NSError(domain: "XCTestError", code: 1, userInfo: [NSLocalizedDescriptionKey: msg, "trace": trace ?? "No trace available"])
            }
            Self.logger.debug("Test failed: \(testCase.name) - Message: \(message ?? "N/A")")
        case .skipped:
            finalItemStatus = .skipped
            if let msg = message {
                errorForThrowable = NSError(domain: "XCTestSkipped", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            Self.logger.debug("Test skipped: \(testCase.name) - Message: \(message ?? "N/A")")
        case .inProgress:
            Self.logger.debug("In progress")
        case .blocked:
            Self.logger.debug("Blocked")
        }

        
        let context = TestItContextBuilder.getContext(forKey: testCase.name)
        if let context = context {
            // Self.logger.info("TestItContext: \(context)")
            adapterManager.updateTestCase(uuid: uuid) { testResult in 
                testResult.itemStatus = finalItemStatus
                testResult.throwable = errorForThrowable
                testResult.updateFromContext(with: context)
            }
        } else {
            Self.logger.info("TestItContext not found for key: \(testCase.name)")
            adapterManager.updateTestCase(uuid: uuid) { testResult in 
                testResult.itemStatus = finalItemStatus
                testResult.throwable = errorForThrowable
            }
        }

        
        await adapterManager.stopTestCase(uuid: uuid)
    }

}
