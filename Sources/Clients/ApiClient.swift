import Foundation
import TestitApiClient

// Stub for ApiClient protocol
// Replace with your actual implementation

// Assuming TestRunV2GetModel exists or create a stub for it
// struct TestRunV2GetModel {
//     var id: UUID
//     var stateName: TestRunState // Needs TestRunState definition
//     // Add other properties
// }

// Renaming TestRunV2GetModel to TestRunV2ApiResult based on updated interface
// struct TestRunV2GetModel { // [DELETED]
//     var id: UUID // [DELETED]
//     var stateName: TestRunState // Needs TestRunState definition // [DELETED]
//     // Add other properties // [DELETED]
// } // [DELETED]

// Stub for TestRunV2ApiResult
//struct TestRunV2ApiResult {
//    var id: UUID // Assuming based on previous GetModel and createTestRun usage
//    var stateName: TestRunState // Assuming based on previous GetModel and getTestRun usage
//    // Add other properties based on actual definition
//}
//
//// Assuming TestRunState exists or create a stub for it
//enum TestRunState: String, Codable { // Example definition
//    case new = "New"
//    case inProgress = "InProgress"
//    case completed = "Completed"
//    // Add other states
//}
//
//// Stub for WorkItemIdentifierModel
//struct WorkItemIdentifierModel {
//    var id: String? // Or Int? Needs actual definition
//    // Add other properties
//}

protocol ApiClient {
    // Define methods based on usage in AdapterManager
    // Updated methods based on the full Kotlin interface
    
    // Test Run Management
    func createTestRun() async throws -> TestRunV2ApiResult 
    func getTestRun(uuid: String) throws -> TestRunV2ApiResult // Parameter changed to non-optional String
    func completeTestRun(uuid: String) throws // Parameter changed to non-optional String
    func getTestFromTestRun(testRunUuid: String, configurationId: String) throws -> [String] // Parameters changed to non-optional String

    // AutoTest Management
    func updateAutoTest(model: AutoTestPutModel) throws
    func createAutoTest(model: AutoTestPostModel) throws -> String // Returns AutoTest ID (String)
    func getAutoTestByExternalId(externalId: String) throws -> AutoTestApiResult? // Returns optional AutoTestApiResult

    // Work Item Linking
    func linkAutoTestToWorkItems(id: String, workItemIds: [String]) throws // Changed Iterable to Array
    func unlinkAutoTestToWorkItem(id: String, workItemId: String) throws -> Bool // Returns success status
    func getWorkItemsLinkedToTest(id: String) throws -> [WorkItemIdentifierModel]

    // Test Results & Attachments
    func sendTestResults(testRunUuid: String, models: [AutoTestResultsForTestRunModel]) throws -> [String] // Returns list of result IDs (String)
    func addAttachment(path: String) throws -> String // Returns attachment ID (String)
    func getTestResult(uuid: UUID) throws -> TestResultResponse
    func updateTestResult(uuid: UUID, model: TestResultUpdateV2Request) throws
} 
