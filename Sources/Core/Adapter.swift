import Foundation
import os.log

// Using enum for static methods and properties, mimicking Kotlin object
enum Adapter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "Adapter")
    
    // Lazy static vars for shared instances. Initialization is thread-safe.
    private static var _adapterManager: AdapterManager? = nil
    private static var _storage: ResultStorage? = nil
    // Additions for ExecutableTestService and its ThreadLocal
    private static var _executableTestService: ExecutableTestService? = nil
    private static var _threadLocalExecutableTest: ThreadLocal<ExecutableTest>? = nil

    // Use NSRecursiveLock to allow the same thread to acquire the lock multiple times
    private static let initLock = NSRecursiveLock() // Lock specifically for initialization logic

    static func getAdapterManager() -> AdapterManager {
        // Double-checked locking pattern (adapted for Swift lazy init)
        if _adapterManager == nil {
            initLock.lock()
            defer { initLock.unlock() }
            if _adapterManager == nil {
                logger.info("Initializing shared AdapterManager...")
                let appProperties = AppProperties.loadProperties()
                let manager = ConfigManager(properties: appProperties)
                // Use the convenience initializer that sets up dependencies
                _adapterManager = AdapterManager(clientConfiguration: manager.getClientConfiguration(), adapterConfig: manager.getAdapterConfig())
                logger.info("Shared AdapterManager initialized.")
            }
        }
        // We force unwrap here because the logic guarantees it's non-nil
        // If initialization failed critically, AppProperties.loadProperties would likely fatalError
        return _adapterManager!
    }

    static func getExecutableTestService() -> ExecutableTestService {
        if _executableTestService == nil {
            initLock.lock()
            defer { initLock.unlock() }
            if _executableTestService == nil {
                logger.info("Initializing shared ThreadLocal<ExecutableTest> and ExecutableTestService...")
                if _threadLocalExecutableTest == nil {
                    _threadLocalExecutableTest = ThreadLocal<ExecutableTest>()
                    // Initialize with a default ExecutableTest for the current thread if it's the first time.
                    // Subsequent calls to get() on other threads will return nil until set() is called for them.
                    // The refreshUuid or initial setting logic elsewhere should handle setting this per thread.
                    // For the very first initialization, let's ensure one is set.
                    _threadLocalExecutableTest?.set(ExecutableTest())
                     logger.info("Shared ThreadLocal<ExecutableTest> initialized and initial ExecutableTest set for current thread.")
                }
                _executableTestService = ExecutableTestService()
                logger.info("Shared ExecutableTestService initialized.")
            }
        }
        return _executableTestService!
    }

    static func getResultStorage() -> ResultStorage {
        if _storage == nil {
            initLock.lock()
            defer { initLock.unlock() }
            if _storage == nil {
                logger.info("Initializing shared ResultStorage...")
                // Use the stub implementation for now
                _storage = InMemoryResultStorage()
                logger.info("Shared ResultStorage initialized.")
            }
        }
        return _storage! // Force unwrap after initialization
    }


} 
