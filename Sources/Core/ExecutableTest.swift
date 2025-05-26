import Foundation

/// Represents the current stage of an executable test's lifecycle.
public enum ExecutableTestStage {
    case before
    case test
    case after
}

/// Represents the state of an executable test during its lifecycle.
public struct ExecutableTest {
    /// A unique identifier for this test execution instance.
    public let uuid: String

    /// Indicates if any step within this test execution has failed.
    public var isFailedStep: Bool

    /// Stores the error that caused a step failure, if any.
    public var stepCause: Error?

    /// The current lifecycle stage of the test execution.
    public var executableTestStage: ExecutableTestStage

    /// Initializes a new executable test state.
    /// - Parameters:
    ///   - uuid: A unique identifier. Defaults to a new UUID string.
    ///   - isFailedStep: Initial failure state. Defaults to `false`.
    ///   - stepCause: Initial step cause. Defaults to `nil`.
    ///   - executableTestStage: Initial stage. Defaults to `.before`.
    public init(
        uuid: String = UUID().uuidString,
        isFailedStep: Bool = false,
        stepCause: Error? = nil,
        executableTestStage: ExecutableTestStage = .before
    ) {
        self.uuid = uuid
        self.isFailedStep = isFailedStep
        self.stepCause = stepCause
        self.executableTestStage = executableTestStage
    }

    public mutating func setTestStatus() {
        self.executableTestStage = .test
    }

    public mutating func setAfterStatus() {
        self.executableTestStage = .after
    }

    public func isAfter() -> Bool {
        return executableTestStage == .after
    }

    public func isBefore() -> Bool {
        return executableTestStage == .before
    }

    public func isTest() -> Bool {
        return executableTestStage == .test
    }
}
