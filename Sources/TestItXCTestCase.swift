import XCTest
import ObjectiveC

/// A custom base class for XCTestCases that intercepts lifecycle events (setUp, tearDown, test execution)
/// using Objective-C method swizzling.
open class TestItXCTestCase: XCTestCase {
    private static var originalSetUpIMP: IMP? = nil
    private static var originalTearDownIMP: IMP? = nil

    private static var originalSetUpWithErrorIMP: IMP? = nil
    private static var originalTearDownWithErrorIMP: IMP? = nil

    // MARK: - Initialization
    
    // CRITICAL: Initialize observer before swizzling to ensure it's registered before any tests run
    // This static block executes when the class is first loaded, which happens before XCTest starts
    private static let _ensureObserverReady: Void = {
        print("[TestItAdapter] TestItXCTestCase class loading - initializing observer")
        _ = OverallLifecycleObserver.shared
        print("[TestItAdapter] Observer ready")
    }()

    private static let swizzleSetupAndTeardown: Void = {
        // Ensure observer is ready before swizzling
        _ = TestItXCTestCase._ensureObserverReady
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

    private static let swizzleSetupAndTeardownWithError: Void = {
        // Swizzle setUp
        let originalSetUp = class_getInstanceMethod(TestItXCTestCase.self, #selector(setUpWithError)) // Updated class name
        let swizzledSetUp = class_getInstanceMethod(TestItXCTestCase.self, #selector(swizzled_setUpWithError)) // Updated class name
        originalSetUpWithErrorIMP = method_getImplementation(originalSetUp!)
        method_exchangeImplementations(originalSetUp!, swizzledSetUp!)

        // Swizzle tearDown
        let originalTearDown = class_getInstanceMethod(TestItXCTestCase.self, #selector(tearDownWithError)) // Updated class name
        let swizzledTearDown = class_getInstanceMethod(TestItXCTestCase.self, #selector(swizzled_tearDownWithError)) // Updated class name
        originalTearDownWithErrorIMP = method_getImplementation(originalTearDown!)
        method_exchangeImplementations(originalTearDown!, swizzledTearDown!)
    }()


    // Ensure swizzling happens automatically
    override open class func setUp() {
        super.setUp()
        
        _ = TestItXCTestCase.swizzleSetupAndTeardown
        _ = TestItXCTestCase.swizzleSetupAndTeardownWithError
    }

    @objc func swizzled_setUp() {
        // Tracking logic before user-defined `setUp`
 
        // executing before actual setup override
        OverallLifecycleObserver.shared.onBeforeSetup(testCase: self)

        // Call the original `setUp` implementation
        if let originalIMP = TestItXCTestCase.originalSetUpIMP { // Updated class name
            let originalSetUpFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalSetUpFunc(self, #selector(XCTestCase.setUp))
        }

        // Additional tracking logic after `setUp`
        OverallLifecycleObserver.shared.onAfterSetup(testCase: self)
    }

    @objc func swizzled_tearDown() {
        OverallLifecycleObserver.shared.onBeforeTeardown(testCase: self)

        // Call the original `tearDown` implementation
        if let originalIMP = TestItXCTestCase.originalTearDownIMP { // Updated class name
            let originalTearDownFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalTearDownFunc(self, #selector(XCTestCase.tearDown))
        }

        OverallLifecycleObserver.shared.onAfterTeardown(testCase: self)
    }

    @objc func swizzled_setUpWithError() throws {
        // Tracking logic before user-defined `setUp`
 
        // executing before actual setup override
        OverallLifecycleObserver.shared.onBeforeSetup(testCase: self)

        // Call the original `setUp` implementation
        if let originalIMP = TestItXCTestCase.originalSetUpIMP { // Updated class name
            let originalSetUpFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalSetUpFunc(self, #selector(XCTestCase.setUp))
        }

        // Additional tracking logic after `setUp`
        OverallLifecycleObserver.shared.onAfterSetup(testCase: self)
    }

    @objc func swizzled_tearDownWithError() throws {
        OverallLifecycleObserver.shared.onBeforeTeardown(testCase: self)

        // Call the original `tearDown` implementation
        if let originalIMP = TestItXCTestCase.originalTearDownIMP { // Updated class name
            let originalTearDownFunc = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector) -> Void).self)
            originalTearDownFunc(self, #selector(XCTestCase.tearDown))
        }

        OverallLifecycleObserver.shared.onAfterTeardown(testCase: self)
    }

} 
