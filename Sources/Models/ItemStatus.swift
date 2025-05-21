import Foundation

enum ItemStatus: String, Codable {
    case passed = "Passed"
    case failed = "Failed"
    case skipped = "Skipped"
    case inProgress = "InProgress"
    case blocked = "Blocked"
} 