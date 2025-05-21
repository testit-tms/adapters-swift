import Foundation
// Enum definition with raw values
enum ItemStage: String, Codable {
    case running = "running"
    case finished = "finished"
    case scheduled = "scheduled"
    case pending = "pending"
}