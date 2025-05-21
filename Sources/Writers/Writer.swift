import Foundation


protocol Writer {
    func setTestRun(testRunId: String)
    func writeTests(_ container: MainContainer)
    func writeClass(_ container: ClassContainer)
    func writeTest(_ result: TestResultCommon)
    func writeAttachment(_ attachmentPath: String) -> String?
}
