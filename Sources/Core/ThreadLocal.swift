import Foundation

// deprecated
class ThreadLocal<T> {
    private let key = UUID().uuidString

    init() {}

    func get() -> T? {
        return Thread.current.threadDictionary[key] as? T
    }

    func set(_ value: T) {
        Thread.current.threadDictionary[key] = value
    }

    func remove() {
        Thread.current.threadDictionary.removeObject(forKey: key)
    }
}