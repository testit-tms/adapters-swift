import Foundation

struct TestItParams {
    var isStepContainer: Bool = false
    var afterTestThrowable: Error? = nil
    var setupName: String? = nil
    var teardownName: String? = nil
}
