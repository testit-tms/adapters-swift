import Foundation
import testit_api_client


protocol ApiClient {
    // Define methods based on usage in AdapterManager
    // Updated methods based on the full Kotlin interface
    
    // Test Run Management
    func createTestRun() async throws -> TestRunV2ApiResult 
    func getTestRun(uuid: String) throws -> TestRunV2ApiResult // Parameter changed to non-optional String
    func updateTestRun(uuid: String, name: String) throws // Update test run name
    func completeTestRun(uuid: String) throws // Parameter changed to non-optional String
    func getTestFromTestRun(testRunUuid: String, configurationId: String) throws -> [String] // Parameters changed to non-optional String

    // AutoTest Management
    func updateAutoTest(model: AutoTestUpdateApiModel) throws
    func createAutoTest(model: AutoTestCreateApiModel) throws -> String // Returns AutoTest ID (String)
    func getAutoTestByExternalId(externalId: String) throws -> AutoTestApiResult? // Returns optional AutoTestApiResult

    // Work Item Linking
    func linkAutoTestToWorkItems(id: String, workItemIds: [String]) throws // Changed Iterable to Array
    func unlinkAutoTestToWorkItem(id: String, workItemId: String) throws -> Bool // Returns success status
    func getWorkItemsLinkedToTest(id: String) throws -> [AutoTestWorkItemIdentifierApiResult]

    // Test Results & Attachments
    func sendTestResults(testRunUuid: String, models: [AutoTestResultsForTestRunModel]) throws -> [String] // Returns list of result IDs (String)
    func addAttachment(path: String) throws -> String // Returns attachment ID (String)
    func getTestResult(uuid: UUID) throws -> TestResultResponse
    func updateTestResult(uuid: UUID, model: TestResultUpdateV2Request) throws
} 
