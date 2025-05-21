import Foundation

struct ClassContainer: Codable {
    var uuid: String? = nil
    var name: String? = nil
    var beforeEachTest: [FixtureResult] = []
    var afterEachTest: [FixtureResult] = []
    var beforeClassMethods: [FixtureResult] = []
    var afterClassMethods: [FixtureResult] = []
    var children: [String] = []
    var start: Int64? = nil
    var stop: Int64? = nil

}

extension ClassContainer: CustomStringConvertible {
    var description: String {
        var builder = "class ClassContainer {\n"
        builder += "    uuid: \(Utils.toIndentedString(self.uuid))\n"
        builder += "    name: \(Utils.toIndentedString(self.name))\n"
        builder += "    beforeEachTest: \(Utils.toIndentedString(self.beforeEachTest))\n"
        builder += "    afterEachTest: \(Utils.toIndentedString(self.afterEachTest))\n"
        builder += "    beforeClassMethods: \(Utils.toIndentedString(self.beforeClassMethods))\n"
        builder += "    afterClassMethods: \(Utils.toIndentedString(self.afterClassMethods))\n"
        builder += "    children: \(Utils.toIndentedString(self.children))\n"
        builder += "    start: \(Utils.toIndentedString(self.start))\n"
        builder += "    stop: \(Utils.toIndentedString(self.stop))\n"
        builder += "}"
        return builder
    }
} 