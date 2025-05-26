import Foundation

struct StepResult: Codable, ResultWithSteps, ResultWithAttachments {
    var name: String?
    var itemStatus: ItemStatus?
    var itemStage: ItemStage?
    var description: String? 
    private var steps: [StepResult] = []
    var linkItems: [LinkItem] = []
    private var attachments: [String] = []
    var throwable: Error? = nil 
    var start: Int64? = nil
    var stop: Int64? = nil
    var parameters: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case name, itemStatus, itemStage, description, steps, linkItems, attachments, throwable, start, stop, parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        itemStatus = try container.decodeIfPresent(ItemStatus.self, forKey: .itemStatus)
        itemStage = try container.decodeIfPresent(ItemStage.self, forKey: .itemStage)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        steps = try container.decode([StepResult].self, forKey: .steps)
        linkItems = try container.decode([LinkItem].self, forKey: .linkItems)
        attachments = try container.decode([String].self, forKey: .attachments)
        // throwable = try container.decodeIfPresent(Error.self, forKey: .throwable) // Error is not Codable
        start = try container.decodeIfPresent(Int64.self, forKey: .start)
        stop = try container.decodeIfPresent(Int64.self, forKey: .stop)
        parameters = try container.decode([String: String].self, forKey: .parameters)
    }
    
    // Encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(itemStatus, forKey: .itemStatus)
        try container.encodeIfPresent(itemStage, forKey: .itemStage)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(steps, forKey: .steps)
        try container.encode(linkItems, forKey: .linkItems)
        try container.encode(attachments, forKey: .attachments)
        // try container.encodeIfPresent(throwable, forKey: .throwable) // Error is not Codable
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encode(parameters, forKey: .parameters)
    }
    
    init(name: String? = nil, itemStatus: ItemStatus? = nil, itemStage: ItemStage? = nil, description: String? = nil, steps: [StepResult] = [], linkItems: [LinkItem] = [], attachments: [String] = [], throwable: Error? = nil, start: Int64? = nil, stop: Int64? = nil, parameters: [String : String] = [:]) {
        self.name = name
        self.itemStatus = itemStatus
        self.itemStage = itemStage
        self.description = description
        self.steps = steps
        self.linkItems = linkItems
        self.attachments = attachments
        self.throwable = throwable
        self.start = start
        self.stop = stop
        self.parameters = parameters
    }

    func getAttachments() -> [String] {
        return attachments
    }

    func getSteps() -> [StepResult] {
        return steps
    }

    mutating func setSteps(steps: [StepResult]) {
        self.steps = steps
    }
}

