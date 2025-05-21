import Foundation

struct FixtureResult: Codable, ResultWithSteps, ResultWithAttachments {
    var name: String?
    var itemStatus: ItemStatus?
    var itemStage: ItemStage?
    var description: String?
    var trace: String?
    private var steps: [StepResult] = []
    var linkItems: [LinkItem] = [] 
    private var attachments: [String] = []
    var parent: String?
    var start: Int64?
    var stop: Int64?
    var parameters: [String: String] = [:]

    // CodingKeys to handle private properties
    enum CodingKeys: String, CodingKey {
        case name, itemStatus, itemStage, description, trace, steps, linkItems, attachments, parent, start, stop, parameters
    }

    // Initializer for decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        itemStatus = try container.decodeIfPresent(ItemStatus.self, forKey: .itemStatus)
        itemStage = try container.decodeIfPresent(ItemStage.self, forKey: .itemStage)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        trace = try container.decodeIfPresent(String.self, forKey: .trace)
        steps = try container.decodeIfPresent([StepResult].self, forKey: .steps) ?? []
        linkItems = try container.decodeIfPresent([LinkItem].self, forKey: .linkItems) ?? []
        attachments = try container.decodeIfPresent([String].self, forKey: .attachments) ?? []
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        start = try container.decodeIfPresent(Int64.self, forKey: .start)
        stop = try container.decodeIfPresent(Int64.self, forKey: .stop)
        parameters = try container.decodeIfPresent([String: String].self, forKey: .parameters) ?? [:]
    }

    // Custom initializer for common use cases
    init(name: String? = nil, 
         itemStatus: ItemStatus? = nil, 
         itemStage: ItemStage? = nil, 
         description: String? = nil, 
         trace: String? = nil,
         steps: [StepResult] = [], 
         linkItems: [LinkItem] = [], 
         attachments: [String] = [], 
         parent: String? = nil, 
         start: Int64? = nil, 
         stop: Int64? = nil, 
         parameters: [String : String] = [:]) {
        self.name = name
        self.itemStatus = itemStatus
        self.itemStage = itemStage
        self.description = description
        self.trace = trace
        self.steps = steps
        self.linkItems = linkItems
        self.attachments = attachments
        self.parent = parent
        self.start = start
        self.stop = stop
        self.parameters = parameters
    }

    // Encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(itemStatus, forKey: .itemStatus)
        try container.encodeIfPresent(itemStage, forKey: .itemStage)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(trace, forKey: .trace)
        try container.encode(steps, forKey: .steps) // Encode even if empty
        try container.encode(linkItems, forKey: .linkItems)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encode(parameters, forKey: .parameters)
    }

    // Default memberwise initializer is sufficient unless custom logic needed

    // Protocol implementations
    func getSteps() -> [StepResult] { return steps }
    func getAttachments() -> [String] { return attachments }
} 