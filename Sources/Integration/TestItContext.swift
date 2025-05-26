import Foundation
import XCTest
import testit_api_client

public struct TestItContext {
    var uuid: String?
    var externalId: String?
    var links: [LinkItem]?
    var resultLinks: [LinkItem]?
    var workItemIds: [String]?
    var attachments: [String]?
    var name: String?
    var title: String?
    var message: String?
    var itemStatus: ItemStatus?
    var description: String?
    var parameters: [String: String]?
    var labels: [Label]?
}

public class TestItContextBuilder {
    private static var storedContexts: [String: TestItContext] = [:]
    private var context: TestItContext

    public init() {
        self.context = TestItContext()
    }

    public func Uuid(_ uuid: String?) -> TestItContextBuilder {
        context.uuid = uuid
        return self
    }

    public func ExternalId(_ externalId: String?) -> TestItContextBuilder {
        context.externalId = externalId
        return self
    }

    public func Links(_ links: [LinkEntity]?) -> TestItContextBuilder {
        context.links = links?.map { $0.toLinkItem() }
        return self
    }
    
    public func AddLinks(_ links: [LinkEntity]?) -> TestItContextBuilder {
        context.resultLinks = links?.map { $0.toLinkItem() }
        return self
    }

    public func WorkItems(_ workItemIds: [String]?) -> TestItContextBuilder {
        context.workItemIds = workItemIds
        return self
    }

    public func Attachments(_ attachments: [String]?) -> TestItContextBuilder {
        context.attachments = attachments
        return self
    }

    public func Name(_ name: String?) -> TestItContextBuilder {
        context.name = name
        return self
    }

    public func Title(_ title: String?) -> TestItContextBuilder {
        context.title = title
        return self
    }

    public func Message(_ message: String?) -> TestItContextBuilder {
        context.message = message
        return self
    }

    public func Description(_ description: String?) -> TestItContextBuilder {
        context.description = description
        return self
    }

    public func Parameters(_ parameters: [String: String]?) -> TestItContextBuilder {
        context.parameters = parameters
        return self
    }

    public func Labels(_ labels: [LabelEntity]?) -> TestItContextBuilder {
        context.labels = labels?.map { $0.toLabel() }
        return self
    }

    public func build(_ test: XCTestCase) -> TestItContext {
        let key = test.name
        TestItContextBuilder.storedContexts[key] = context
        return context
    }

    public static func getContext(forKey key: String) -> TestItContext? {
        return storedContexts[key]
    }
}

public struct LinkEntity {
    var title: String
    var url: String
    var description: String
    var type: LinkEntityType

    public init(title: String, url: String, description: String, type: LinkEntityType) {
        self.title = title
        self.url = url
        self.description = description
        self.type = type
    }
}

extension LinkEntity {
    func toLinkItem() -> LinkItem {
        guard let linkType = LinkType(rawValue: self.type.rawValue) else {
            fatalError("Failed to convert LinkEntityType to LinkType")
        }

        return LinkItem(title: self.title, url: self.url,
                        description: self.description, type: linkType)
    }
}

public struct LabelEntity {
    var name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}

public enum LinkEntityType: String, Codable {
    case related = "Related"
    case blockedBy = "BlockedBy"
    case defect = "Defect"
    case issue = "Issue"
    case requirement = "Requirement"
    case repository = "Repository"
}

extension LabelEntity {
    func toLabel() -> Label {
        return Label(name: self.name)
    }
}

extension TestItContext {
    public static func getNamespace(from testCase: XCTestCase) -> String {
        // Take bundle
        let bundle = Bundle(for: type(of: testCase))
        
        // Take target name from bundle
        let targetName = bundle.bundleIdentifier ?? "UnknownTarget"
        
        // Form namespace
        return "\(targetName)"
    }
}
