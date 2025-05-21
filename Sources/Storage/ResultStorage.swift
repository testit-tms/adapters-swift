import Foundation


protocol ResultStorage {
   
    func put(_ uuid: String, _ value: Any)
    func remove(_ uuid: String)
    
    // Methods returning specific types (returning Optionals)
    func getTestsContainer(_ uuid: String) -> MainContainer?
    func getClassContainer(_ uuid: String) -> ClassContainer?
    func getTestResult(_ uuid: String) -> TestResultCommon?
    func getFixture(_ uuid: String) -> FixtureResult?
    func getStep(_ uuid: String) -> StepResult?
    
    
    func getAttachmentsList(_ uuid: String) -> [String]?
    func updateAttachmentsList(_ uuid: String, adding newAttachments: [String])
}

// Basic in-memory dictionary implementation for the stub
// NOT THREAD-SAFE - Replace with a proper implementation
class InMemoryResultStorage: ResultStorage {
    private var storage: [String: Any] = [:]
    private var attachmentLists: [String: [String]] = [:] // Separate storage for attachment lists
    private let lock = NSLock() // Simple lock for basic thread safety in the stub

    func put(_ uuid: String, _ value: Any) {
        lock.lock()
        defer { lock.unlock() }
        storage[uuid] = value
        if value is [String] { // Special handling if storing an attachment list directly
            attachmentLists[uuid] = value as? [String]
        }
    }

    func remove(_ uuid: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: uuid)
        attachmentLists.removeValue(forKey: uuid) // Also remove from attachment lists
    }

    func getTestsContainer(_ uuid: String) -> MainContainer? {
        lock.lock()
        defer { lock.unlock() }
        return storage[uuid] as? MainContainer
    }

    func getClassContainer(_ uuid: String) -> ClassContainer? {
        lock.lock()
        defer { lock.unlock() }
        return storage[uuid] as? ClassContainer
    }

    func getTestResult(_ uuid: String) -> TestResultCommon? {
        lock.lock()
        defer { lock.unlock() }
        return storage[uuid] as? TestResultCommon
    }

    func getFixture(_ uuid: String) -> FixtureResult? {
        lock.lock()
        defer { lock.unlock() }
        return storage[uuid] as? FixtureResult
    }

    func getStep(_ uuid: String) -> StepResult? {
        lock.lock()
        defer { lock.unlock() }
        return storage[uuid] as? StepResult
    }
    
    // Swift version returns the list or nil. Modification happens separately.
    func getAttachmentsList(_ uuid: String) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        // Attempt to get from specific list storage OR general storage
        return attachmentLists[uuid] ?? storage[uuid] as? [String]
    }
    
    // New method to handle adding attachments safely
    func updateAttachmentsList(_ uuid: String, adding newAttachments: [String]) {
        lock.lock()
        defer { lock.unlock() }
        if attachmentLists[uuid] != nil {
            attachmentLists[uuid]?.append(contentsOf: newAttachments)
        } else {
            attachmentLists[uuid] = newAttachments
        }
    }
} 
