import Foundation

final class ExecutableTestService {
    var currentTests: [String: ExecutableTest] = [:]
    private let lock = NSLock()

    // MARK: - Test Lifecycle Management

    func setTestStatus(testName: String) {
        lock.lock()
        defer { lock.unlock() }
        var executable = currentTests[testName]
        executable?.setTestStatus()
    }

    func setAfterStatus(testName: String) {
        lock.lock()
        defer { lock.unlock() }
        var executable = currentTests[testName]
        executable?.setAfterStatus()
    }

    // MARK: - Getters

    func getTest(testName: String) -> ExecutableTest? {
        lock.lock()
        defer { lock.unlock() }
        return currentTests[testName]
    }

    func getUuid(testName: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return currentTests[testName]?.uuid
    }

    // MARK: - UUID Management

    func refreshUuid(testName: String) {
        lock.lock()
        defer { lock.unlock() }
        let newTest = ExecutableTest() 
        currentTests[testName] = newTest
    }

    func onTestIgnoredRefreshIfNeed(testName: String) {
        lock.lock()
        defer { lock.unlock() }
        var executable = currentTests[testName]

        if executable?.isAfter() == true {
            let newTest = ExecutableTest() 
            currentTests[testName] = newTest
        }

        currentTests[testName]?.setAfterStatus()
    }

    func isTestStatus(testName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentTests[testName]?.isTest() ?? false
    }
}
