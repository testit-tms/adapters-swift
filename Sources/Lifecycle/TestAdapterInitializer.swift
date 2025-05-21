import Foundation
import XCTest 

class TestAdapterInitializer: NSObject {
    override init() {
        super.init()
        _ = OverallLifecycleObserver.shared
    }
} 
