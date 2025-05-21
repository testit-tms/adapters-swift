import Foundation

// Definition for LinkType. Replace with actual implementation.
enum LinkType: String, Codable {
    case related = "Related"
    case blockedBy = "BlockedBy"
    case defect = "Defect"
    case issue = "Issue"
    case requirement = "Requirement"
    case repository = "Repository"
}