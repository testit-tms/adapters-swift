import Foundation
// Label definition
struct Label: Codable {
    var name: String?
}

extension Label: CustomStringConvertible {
    var description: String {
        var builder = "class Label {\n"
        builder += "    name: \(Utils.toIndentedString(self.name))\n"
        builder += "}"
        return builder
    }
}
