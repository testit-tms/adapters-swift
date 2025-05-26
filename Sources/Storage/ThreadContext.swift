import Foundation
import os.log



class ThreadContext {
    private var currentContext: [String: String] = [:] 
    private let lock = NSLock()
    private var uuidStack: [String] = [] // Simple stack simulation
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "ThreadContext")


    func clear() {
        lock.lock()
        defer { lock.unlock() }
        uuidStack.removeAll()
        // currentContext.removeValue(forKey: "currentThreadId") // Example
        logger.info("ThreadContext STUB: clear called")
    }

    func start(_ uuid: String) {
        lock.lock()
        defer { lock.unlock() }
        uuidStack.append(uuid)
        // currentContext["currentThreadId"] = uuid // Example
    }
    
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        _ = uuidStack.popLast()
    }

    // Returns the root (first started) UUID in the current stack simulation
    func getRoot() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return uuidStack.first
    }

    // Returns the currently active (last started) UUID in the stack simulation
    func getCurrent() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return uuidStack.last
        // return currentContext["currentThreadId"] // Example
    }
    
    // Returns the parent (second-to-last) UUID in the stack simulation, if available
    func getParent() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard uuidStack.count >= 2 else {
            return nil // No parent if fewer than 2 items
        }
        return uuidStack[uuidStack.count - 2]
    }
} 