import Foundation

struct MainContainer: Codable {
    var uuid: String? = nil
    var beforeMethods: [FixtureResult] = []
    var afterMethods: [FixtureResult] = []
    var children: [String] = []
    var start: Int64? = nil
    var stop: Int64? = nil
    
    // Default Codable conformance and memberwise initializer should suffice
}

extension MainContainer: CustomStringConvertible {
    var description: String {
        var builder = "class MainContainer {\n"
        builder += "    uuid: \(Utils.toIndentedString(self.uuid))\n"
        builder += "    beforeMethods: \(Utils.toIndentedString(self.beforeMethods))\n"
        builder += "    afterMethods: \(Utils.toIndentedString(self.afterMethods))\n"
        builder += "    children: \(Utils.toIndentedString(self.children))\n"
        builder += "    start: \(Utils.toIndentedString(self.start))\n"
        builder += "    stop: \(Utils.toIndentedString(self.stop))\n"
        builder += "}"
        return builder
    }
}
