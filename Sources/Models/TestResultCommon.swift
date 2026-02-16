import Foundation
import testit_api_client

// Definitions for dependent types.



struct TestResultCommon: Codable, ResultWithSteps {
    var uuid: String? = nil
    var externalId: String = ""
    var workItemIds: [String] = []
    var className: String = ""
    var spaceName: String = ""
    var labels: [Label] = []
    var tags: [String] = []
    var linkItems: [LinkItem] = []
    var resultLinks: [LinkItem] = []
    var attachments: [String] = []
    var name: String = ""
    var title: String = ""
    var message: String = ""
    var itemStatus: ItemStatus? = nil
    private var itemStage: ItemStage? = nil
    var description: String = ""
    private var steps: [StepResult] = []
    var start: Int64 = 0 // Using Int64 to match Long
    var stop: Int64 = 0  // Using Int64 to match Long
    // @Contextual var throwable: Throwable? = nil // Throwable has no direct equivalent in Swift, using Error?
    var throwable: Error? = nil
    var parameters: [String: String] = [:]
    var automaticCreationTestCases: Bool = false
    var externalKey: String? = nil
    var originalTestName: String = ""

    // Using CodingKeys for mapping private properties if encoding/decoding is needed
    enum CodingKeys: String, CodingKey {
        case uuid, externalId, workItemIds, className, spaceName, labels, linkItems, resultLinks, attachments, name, title, message, itemStatus, itemStage, description, steps, start, stop, throwable, parameters, automaticCreationTestCases, externalKey, originalTestName, tags
    }

    // Initializer for decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        externalId = try container.decode(String.self, forKey: .externalId)
        workItemIds = try container.decode([String].self, forKey: .workItemIds)
        className = try container.decode(String.self, forKey: .className)
        spaceName = try container.decode(String.self, forKey: .spaceName)
        labels = try container.decode([Label].self, forKey: .labels)
        tags = try container.decode([String].self, forKey: .tags)
        linkItems = try container.decode([LinkItem].self, forKey: .linkItems)
        resultLinks = try container.decode([LinkItem].self, forKey: .resultLinks)
        attachments = try container.decode([String].self, forKey: .attachments)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        itemStatus = try container.decodeIfPresent(ItemStatus.self, forKey: .itemStatus)
        itemStage = try container.decodeIfPresent(ItemStage.self, forKey: .itemStage)
        description = try container.decode(String.self, forKey: .description)
        steps = try container.decode([StepResult].self, forKey: .steps)
        start = try container.decode(Int64.self, forKey: .start)
        stop = try container.decode(Int64.self, forKey: .stop)
        // throwable = try container.decodeIfPresent(Error.self, forKey: .throwable) // Error is not Codable by default
        parameters = try container.decode([String: String].self, forKey: .parameters)
        automaticCreationTestCases = try container.decode(Bool.self, forKey: .automaticCreationTestCases)
        externalKey = try container.decodeIfPresent(String.self, forKey: .externalKey)
        originalTestName = try container.decode(String.self, forKey: .originalTestName)
    }
    
    // Initializer for creating an instance
    init(uuid: String? = nil, externalId: String = "", workItemIds: [String] = [], className: String = "", spaceName: String = "", labels: [Label] = [], tags: [String] = [], linkItems: [LinkItem] = [], resultLinks: [LinkItem] = [], attachments: [String] = [], name: String = "", title: String = "", message: String = "", itemStatus: ItemStatus? = nil, itemStage: ItemStage? = nil, description: String = "", steps: [StepResult] = [], start: Int64 = 0, stop: Int64 = 0, throwable: Error? = nil, parameters: [String : String] = [:], automaticCreationTestCases: Bool = false, externalKey: String? = nil, originalTestName: String = "") {
        self.uuid = uuid
        self.externalId = externalId
        self.workItemIds = workItemIds
        self.className = className
        self.spaceName = spaceName
        self.labels = labels
        self.tags = tags
        self.linkItems = linkItems
        self.resultLinks = resultLinks
        self.attachments = attachments
        self.name = name
        self.title = title
        self.message = message
        self.itemStatus = itemStatus
        self.itemStage = itemStage
        self.description = description
        self.steps = steps
        self.start = start
        self.stop = stop
        self.throwable = throwable
        self.parameters = parameters
        self.automaticCreationTestCases = automaticCreationTestCases
        self.externalKey = externalKey
        self.originalTestName = originalTestName
    }


    // Encoder
     func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encode(externalId, forKey: .externalId)
        try container.encode(workItemIds, forKey: .workItemIds)
        try container.encode(className, forKey: .className)
        try container.encode(spaceName, forKey: .spaceName)
        try container.encode(labels, forKey: .labels)
        try container.encode(tags, forKey: .tags)
        try container.encode(linkItems, forKey: .linkItems)
        try container.encode(resultLinks, forKey: .resultLinks)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(name, forKey: .name)
        try container.encode(title, forKey: .title)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(itemStatus, forKey: .itemStatus)
        try container.encodeIfPresent(itemStage, forKey: .itemStage)
        try container.encode(description, forKey: .description)
        try container.encode(steps, forKey: .steps)
        try container.encode(start, forKey: .start)
        try container.encode(stop, forKey: .stop)
        // try container.encodeIfPresent(throwable, forKey: .throwable) // Error is not Codable by default
        try container.encode(parameters, forKey: .parameters)
        try container.encode(automaticCreationTestCases, forKey: .automaticCreationTestCases)
        try container.encodeIfPresent(externalKey, forKey: .externalKey)
        try container.encode(originalTestName, forKey: .originalTestName)
    }


    mutating func setItemStage(stage: ItemStage) {
        self.itemStage = stage
    }

    func getSteps() -> [StepResult] {
        return steps
    }

    mutating func setSteps(steps: [StepResult]) {
        self.steps = steps
        // Returning self in a struct's mutating method is not standard practice in Swift, 
        // so the method is changed to void
    }
}

extension TestResultCommon {
    mutating func updateFromContext(with context: TestItContext) {
        self.externalId = context.externalId ?? self.externalId
        self.description = context.description ?? self.description
        self.workItemIds = context.workItemIds ?? self.workItemIds
        self.name = context.name ?? self.name
        self.title = context.title ?? self.title
        self.message = context.message ?? self.message
        self.itemStatus = context.itemStatus ?? self.itemStatus 
        self.attachments = context.attachments ?? self.attachments
        self.uuid = context.uuid ?? self.uuid
        self.parameters = context.parameters ?? self.parameters
        self.labels = context.labels ?? self.labels
        self.tags = context.tags ?? self.tags
        self.linkItems = context.links ?? self.linkItems
        self.resultLinks = context.resultLinks ?? self.resultLinks
        self.externalKey = context.externalKey ?? self.externalKey
        self.originalTestName = self.name
    }
}
