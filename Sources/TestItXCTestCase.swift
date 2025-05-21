import XCTest
import ObjectiveC

/// A custom base class for XCTestCases that intercepts lifecycle events (setUp, tearDown, test execution)
/// using Objective-C method swizzling.
///
/// This class provides hooks (`logLifecycleEvent`) to integrate external systems (like the TestIt adapter)
/// by allowing custom logic to be executed before and after standard test lifecycle methods.
open class TestItXCTestCase: XCTestCase { // Renamed from CustomTestCase
    private static var originalSetUpIMP: IMP? = nil
    private static var originalTearDownIMP: IMP? = nil


    private var initializer = TestAdapterInitializer()

    // MARK: - Initialization
    

    private static let swizzleSetupAndTeardown: Void = {
        // Swizzle setUp
        let originalSetUp = class_getInstanceMethod(TestItXCTestCase.self, #selector(setUp)) // Updated class name
        let swizzledSetUp = class_getInstanceMethod(TestItXCTestCase.self, #selector(swizzled_setUp)) // Updated class name
        originalSetUpIMP = method_getImplementation(originalSetUp!)
        method_exchangeImplementations(originalSetUp!, swizzledSetUp!)

        // Swizzle tearDown
        let originalTearDown = class_getInstanceMethod(TestItXCTestCase.self, #selector(tearDown)) // Updated class name
        let swizzledTearDown = class_getInstanceMethod(TestItXCTestCase.self, #selector(swizzled_tearDown)) // Updated class name
        originalTearDownIMP = method_getImplementation(originalTearDown!)
        method_exchangeImplementations(originalTearDown!, swizzledTearDown!)
    }()


    // Ensure swizzling happens automatically
    override open class func setUp() {
        super.setUp()
        
        _ = TestItXCTestCase.swizzleSetupAndTeardown // Updated class name
    }


    @objc func swizzled_setUp() {
        // Tracking logic before user-defined `setUp`
        print("swizzled_setUp started")
 
        logLifecycleEvent("TestIt setUp started for \(self.name)") // Updated log message
        // executing before actual setup override
        OverallLifecycleObserver.shared.onBeforeSetup(testCase: self)

        // Call the original `setUp` implementation
        if let originalIMP = TestItXCTestCase.originalSetUpIMP { // Updated class name
            let originalSetUpFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalSetUpFunc(self, #selector(XCTestCase.setUp))
        }

        // Additional tracking logic after `setUp`
        OverallLifecycleObserver.shared.onAfterSetup(testCase: self)
        logLifecycleEvent("TestIt setUp completed for \(self.name)") // Updated log message
    }

    @objc func swizzled_tearDown() {
        logLifecycleEvent("TestIt tearDown started for \(self.name)") // Updated log message
        OverallLifecycleObserver.shared.onBeforeTeardown(testCase: self)

        // Call the original `tearDown` implementation
        if let originalIMP = TestItXCTestCase.originalTearDownIMP { // Updated class name
            let originalTearDownFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalTearDownFunc(self, #selector(XCTestCase.tearDown))
        }

        OverallLifecycleObserver.shared.onAfterTeardown(testCase: self)
        logLifecycleEvent("TestIt tearDown completed for \(self.name)") // Updated log message
    }

    func logLifecycleEvent(_ message: String) {
        print("[Lifecycle Event]: \(message)")
        // Add logic to send data to a server or save logs
    }
} 
