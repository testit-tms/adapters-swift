import Foundation
import testit_api_client
import os.log

enum Converter {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "Converter")

    static func testResultToAutoTestPostModel(result: TestResultCommon, projectId: UUID?) -> AutoTestPostModel? {
       
        guard let uuidString = result.uuid,
            let projId = projectId ?? UUID(uuidString: uuidString)
        else {
            logger.error("Error: Missing required uuid in TestResultCommon or invalid UUID string for AutoTestPostModel conversion.")
            return nil
        }

        let model = AutoTestPostModel(
            workItemIdsForLinkWithAutoTest: nil, 
            shouldCreateWorkItem: result.automaticCreationTestCases, // This was already mapped
            attributes: [:], 
            externalId: result.externalId,
            links: convertPostLinks(result.linkItems),
            projectId: projId,
            name: result.name,
            namespace: result.spaceName,
            classname: result.className,
            steps: convertSteps(result.getSteps()), 
            setup: nil, 
            teardown: nil, 
            title: result.title,
            description: result.description,
            labels: labelsPostConvert(result.labels),
            isFlaky: false, 
            externalKey: result.externalKey
        )
        return model
    }

    static func testResultToAutoTestPutModel(result: TestResultCommon) -> AutoTestPutModel? {
        return testResultToAutoTestPutModel(result: result, projectId: nil, isFlaky: nil)
    }

    static func testResultToAutoTestPutModel(result: TestResultCommon,
                                             projectId: UUID?,
                                             isFlaky: Bool?) -> AutoTestPutModel? {
        // externalId and name are non-optional in TestResultCommon
        let uuidString = result.externalId
        guard let projId = projectId ?? UUID(uuidString: uuidString)
        else {
            // Update error message
            logger.error("Error: Missing required uuid in TestResultCommon or invalid UUID string for AutoTestPutModel conversion.")
            return nil
        }

        let model = AutoTestPutModel(
            id: nil, // UUID(uuidString: uuidString),
            workItemIdsForLinkWithAutoTest: nil,
            externalId: result.externalId, 
            links: convertPutLinks(result.linkItems),
            projectId: projId,
            name: result.name, 
            namespace: result.spaceName,
            classname: result.className,
            steps: convertSteps(result.getSteps()),
            setup: [], 
            teardown: [], 
            title: result.title,
            description: result.description,
            labels: labelsPostConvert(result.labels),
            isFlaky: isFlaky,
            externalKey: result.externalKey
        )
        return model
    }

    static func testResultToTestResultUpdateModel(result: TestResultResponse,
                                                  setupResults: [AutoTestStepResultUpdateRequest]?,
                                                  teardownResults: [AutoTestStepResultUpdateRequest]?
    ) -> TestResultUpdateV2Request {
        let model = TestResultUpdateV2Request(
            failureClassIds: result.failureClassIds,
            outcome: result.outcome, // This field is deprecated in the new model
            statusCode: nil, // New field, assuming nil. Populate if source exists in TestResultResponse.
            comment: result.comment,
            links: result.links, 
            stepResults: result.stepResults, 
            attachments: convertAttachmentsFromResult(result.attachments ?? []),
            durationInMs: result.durationInMs, // This field is deprecated, mapped for now.
            duration: result.durationInMs, // Mapping old durationInMs to new duration field.
            stepComments: nil, 
            setupResults: setupResults,
            teardownResults: teardownResults,
            message: nil, 
            trace: nil 
        )
        return model
    }

    // convertFixture needs FixtureResult definition
    static func convertFixture(fixtures: [FixtureResult], parentUuid: String?) -> [AutoTestStepModel] {
        return fixtures
            .filter { filterSteps(parentUuid: parentUuid, f: $0) }
            .compactMap { fixture -> AutoTestStepModel? in
                guard let name = fixture.name else { return nil } // Handle optional name
                let model = AutoTestStepModel(
                    title: name,
                    description: fixture.`description`,
                    steps: convertSteps(fixture.getSteps())
                )
                return model
            }
    }

    private static func filterSteps(parentUuid: String?, f: FixtureResult?) -> Bool {
        guard let fixture = f else { return false }
        // Using Swift's optional comparison
        return parentUuid != nil && fixture.parent == parentUuid
    }
    
    static func autoTestModelToAutoTestPutModel(autoTestModel: AutoTestModel) -> AutoTestPutModel? {
        return autoTestModelToAutoTestPutModel(autoTestModel: autoTestModel, links: nil, isFlaky: nil, setup: nil, teardown: nil)
    }

    static func autoTestModelToAutoTestPutModel(autoTestModel: AutoTestModel,
                                                setup: [AutoTestStepModel]?,
                                                teardown: [AutoTestStepModel]?,
                                                isFlaky: Bool?) -> AutoTestPutModel? {
        return autoTestModelToAutoTestPutModel(autoTestModel: autoTestModel, links: nil, isFlaky: isFlaky, setup: setup, teardown: teardown)
    }

    static func autoTestModelToAutoTestPutModel(autoTestModel: AutoTestModel,
                                                links: [LinkPutModel]?,
                                                isFlaky: Bool?) -> AutoTestPutModel? {
        return autoTestModelToAutoTestPutModel(autoTestModel: autoTestModel, links: links, isFlaky: isFlaky, setup: nil, teardown: nil)
    }

    static func autoTestModelToAutoTestPutModel(
        autoTestModel: AutoTestModel,
        links: [LinkPutModel]?,
        isFlaky: Bool?,
        setup: [AutoTestStepModel]?,
        teardown: [AutoTestStepModel]?
    ) -> AutoTestPutModel? {
        // externalId and name are non-optional in AutoTestModel, so no need to conditionally bind them.
        // The guard statement is removed as there are no longer any optional values to check here
        // that would cause the function to return nil early based on missing externalId or name.
        // If other fields were critical and optional, they would remain in a guard.

        let model = AutoTestPutModel(
            id: autoTestModel.id, // Directly mapped from AutoTestModel.id
            workItemIdsForLinkWithAutoTest: nil, // Assuming nil, adjust if AutoTestModel provides this data
            externalId: autoTestModel.externalId, // Directly use non-optional value
            links: links ?? autoTestModel.links?.compactMap { LinkPutModel(title: $0.title, url: $0.url,  description: $0.description, type: $0.type, hasInfo: false) }, // Adjusted to map LinkModel to LinkPutModel
            projectId: autoTestModel.projectId,
            name: autoTestModel.name, // Directly use non-optional value
            namespace: autoTestModel.namespace,
            classname: autoTestModel.classname,
            steps: autoTestModel.steps,
            setup: setup ?? autoTestModel.setup, 
            teardown: teardown ?? autoTestModel.teardown, 
            title: autoTestModel.title,
            description: autoTestModel.description,
            labels: labelsConvert(autoTestModel.labels ?? []),
            isFlaky: isFlaky,
            externalKey: autoTestModel.externalKey // Directly mapped from AutoTestModel.externalKey if it exists
        )
        return model
    }
    
    static func testResultToAutoTestResultsForTestRunModel(
        result: TestResultCommon,
        configurationId: UUID?
    ) -> AutoTestResultsForTestRunModel? {
        return testResultToAutoTestResultsForTestRunModel(result: result, configurationId: configurationId, setupResults: nil, teardownResults: nil)
    }

    static func testResultToAutoTestResultsForTestRunModel(result: TestResultCommon,
                                                           configurationId: UUID?,
                                                           setupResults: [AttachmentPutModelAutoTestStepResultsModel]?,
                                                           teardownResults: [AttachmentPutModelAutoTestStepResultsModel]?
    ) -> AutoTestResultsForTestRunModel? {
        
        // Safely unwrap required fields
        // externalId, start, and stop are non-optional in TestResultCommon
        guard let itemStatusValue = result.itemStatus?.value, // Assuming ItemStatus has a String 'value' property
              let outcome = AvailableTestResultOutcome(rawValue: itemStatusValue), // Use guard let for failable init
              let uuidString = result.uuid,
              let configId = configurationId ?? UUID(uuidString: uuidString) // Use guard let for nil-coalescing with failable init
        else {
            // Update error message
            logger.error("Error: Missing required fields (itemStatus, uuid, configurationId) or invalid status/uuid/configId in TestResultCommon for AutoTestResultsForTestRunModel conversion.")
            return nil
        }

        let throwable = result.throwable
        let message = throwable?.localizedDescription ?? result.message // Get error description
        let traces = throwable != nil ? "\(String(describing: throwable))" : nil // Simple error description

        let model = AutoTestResultsForTestRunModel(
            configurationId: configId,
            links: convertPostLinks(result.resultLinks),
            failureReasonNames: nil, // New field, assuming nil. Populate if source exists in TestResultCommon.
            autoTestExternalId: result.externalId, 
            outcome: outcome,
            message: message,
            traces: traces,
            startedOn: Date(timeIntervalSince1970: TimeInterval(result.start / 1000)), // Convert Int64 ms to Date
            completedOn: Date(timeIntervalSince1970: TimeInterval(result.stop / 1000)), // Convert Int64 ms to Date
            duration: result.stop - result.start, 
            attachments: convertAttachments(result.attachments),
            parameters: result.parameters,
            properties: nil, // New field, assuming nil. Populate if source exists in TestResultCommon.
            stepResults: convertResultStep(result.getSteps()),
            setupResults: setupResults,
            teardownResults: teardownResults
        )
        return model
    }

    static func convertPostLinks(_ links: [LinkItem]) -> [LinkPostModel] {
        return links.compactMap { link -> LinkPostModel? in
            // Safely create LinkType from rawValue
            guard let linkType = testit_api_client.LinkType(rawValue: link.type.rawValue) else {
                logger.warning("Warning: Could not convert LinkType rawValue: \(link.type.rawValue)")
                return nil
            }
            return LinkPostModel(
                title: link.title,
                url: link.url, // url is non-optional in LinkPostModel and LinkItem
                description: link.description,
                type: Optional(linkType), // Explicitly convert non-optional LinkType to LinkType?
                hasInfo: false // Kept as true, as per previous logic and new non-optional requirement
            )
        }
    }

    static func convertPutLinks(_ links: [LinkItem]) -> [LinkPutModel] {
        return links.compactMap { link -> LinkPutModel? in
            guard let linkType = testit_api_client.LinkType(rawValue: link.type.rawValue) else {
                logger.warning("Warning: Could not convert LinkType rawValue: \(link.type.rawValue)")
                return nil
            }
            return LinkPutModel(
                id: nil, // New field, LinkItem doesn't have a direct ID to map here
                title: link.title,
                url: link.url,
                description: link.description,
                type: linkType,
                hasInfo: false // Assuming true, as per existing logic and model requiring it
            )
        }
    }

    static func convertSteps(_ steps: [StepResult]) -> [AutoTestStepModel] {
        return steps.compactMap { step -> AutoTestStepModel? in
             guard let name = step.name else { return nil } // Steps require a name/title
             return AutoTestStepModel(
                title: name,
                description: step.description,
                steps: convertSteps(step.getSteps())
             )
        }
    }

    static func convertResultStep(_ steps: [StepResult]) -> [AttachmentPutModelAutoTestStepResultsModel] {
        return steps.compactMap { step -> AttachmentPutModelAutoTestStepResultsModel? in
            guard let start = step.start,
                let stop = step.stop,
                let statusValue = step.itemStatus?.value, // Assuming ItemStatus has String value
                let outcome = AvailableTestResultOutcome(rawValue: statusValue) 
            else { 
                logger.warning("Warning: Skipping StepResult conversion due to missing start/stop/status.")
                return nil 
            }

            return AttachmentPutModelAutoTestStepResultsModel(
                title: step.name,
                description: step.`description`,
                startedOn: Date(timeIntervalSince1970: TimeInterval(start / 1000)), // Convert Int64 ms to Date
                completedOn: Date(timeIntervalSince1970: TimeInterval(stop / 1000)), // Convert Int64 ms to Date
                duration: stop - start,
                outcome: outcome,
                stepResults: convertResultStep(step.getSteps()),
                attachments: convertAttachments(step.getAttachments()),
                parameters: step.parameters
            )
        }
    }

    // convertResultFixture needs FixtureResult definition
    static func convertResultFixture(fixtures: [FixtureResult], parentUuid: String?) -> [AttachmentPutModelAutoTestStepResultsModel] {
        return fixtures
            .filter { filterSteps(parentUuid: parentUuid, f: $0) }
            .compactMap { fixture -> AttachmentPutModelAutoTestStepResultsModel? in
                guard let start = fixture.start,
                    let stop = fixture.stop,
                    let statusValue = fixture.itemStatus?.value, // Assuming ItemStatus has String value
                    let outcome = AvailableTestResultOutcome(rawValue: statusValue) 
                else { 
                    logger.warning("Warning: Skipping FixtureResult conversion due to missing start/stop/status.")
                    return nil
                }
                 
                return AttachmentPutModelAutoTestStepResultsModel(
                    title: fixture.name,
                    description: fixture.description,
                    startedOn: Date(timeIntervalSince1970: TimeInterval(start / 1000)), // Convert Int64 ms to Date
                    completedOn: Date(timeIntervalSince1970: TimeInterval(stop / 1000)), // Convert Int64 ms to Date
                    duration: stop - start,
                    outcome: outcome,
                    stepResults: convertResultStep(fixture.getSteps()),
                    attachments: convertAttachments(fixture.getAttachments()),
                    parameters: fixture.parameters
                )
            }
    }

    static func labelsConvert(_ labels: [LabelShortModel]) -> [LabelPostModel] {
        return labels.compactMap { label -> LabelPostModel? in 
            let name = label.name
            return LabelPostModel(name: name)
        }
    }

    static func labelsPostConvert(_ labels: [Label]) -> [LabelPostModel] {
         return labels.compactMap { label -> LabelPostModel? in 
            guard let name = label.name else { return nil }
            return LabelPostModel(name: name)
        }
    }

    // Helper to convert Milliseconds since epoch (Int64) to ISO8601 String UTC
    private static func dateToISO8601String(time: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time / 1000))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // Corresponds to OffsetDateTime
        return formatter.string(from: date)
    }

    // Helper to convert ISO8601 String to Date
    private static func dateFromISO8601String(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        // Try with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // Fallback to without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    static func convertAttachments(_ uuids: [String]) -> [AttachmentPutModel]? {
        let attachmentModels = uuids.compactMap { uuidString -> AttachmentPutModel? in
            guard let uuid = UUID(uuidString: uuidString) else { 
                logger.warning("Warning: Could not convert string \"\(uuidString)\" to UUID.")
                return nil 
            }
            return AttachmentPutModel(id: uuid)
        }
        return attachmentModels.isEmpty ? nil : attachmentModels // Return nil if empty, matching Kotlin logic
    }

    static func convertAttachmentsFromResult(_ models: [AttachmentApiResult]) -> [AttachmentUpdateRequest]? {
         let updateRequests = models.map { AttachmentUpdateRequest(id: $0.id) }
         return updateRequests.isEmpty ? nil : updateRequests // Return nil if empty
    }
    
    private static func convertStatusApiTypeToStatusType(apiType: TestStatusApiType) -> TestStatusType {
        return TestStatusType(rawValue: apiType.rawValue)!
    }

    static func convertAutoTestApiResultToAutoTestModel(autoTestApiResult: AutoTestApiResult?) -> AutoTestModel? {
        if let apiResult = autoTestApiResult {
            Self.logger.debug("convertAutoTestApiResultToAutoTestModel... with autoTestApiResult: id: \(apiResult.id), projectId: \(apiResult.projectId), externalId: \(apiResult.externalId ?? "nil"), name: \(apiResult.name), namespace: \(apiResult.namespace ?? "nil"), classname: \(apiResult.classname ?? "nil"), steps: \(apiResult.steps?.count ?? 0) items, setup: \(apiResult.setup?.count ?? 0) items, teardown: \(apiResult.teardown?.count ?? 0) items, title: \(apiResult.title ?? "nil"), description: \(apiResult.description ?? "nil"), isFlaky: \(apiResult.isFlaky), externalKey: \(apiResult.externalKey ?? "nil"), globalId: \(apiResult.globalId), isDeleted: \(apiResult.isDeleted), mustBeApproved: \(apiResult.mustBeApproved), createdDate: \(apiResult.createdDate), modifiedDate: \(apiResult.modifiedDate?.description ?? "nil"), createdById: \(apiResult.createdById), modifiedById: \(apiResult.modifiedById?.uuidString ?? "nil"), lastTestRunId: \(apiResult.lastTestRunId?.uuidString ?? "nil"), lastTestRunName: \(apiResult.lastTestRunName ?? "nil"), lastTestResultId: \(apiResult.lastTestResultId?.uuidString ?? "nil"), lastTestResultConfiguration: \(apiResult.lastTestResultConfiguration?.id.uuidString ?? "nil"), lastTestResultOutcome: \(apiResult.lastTestResultOutcome ?? "nil"), lastTestResultStatus: \(apiResult.lastTestResultStatus?.name ?? "nil"), stabilityPercentage: \(apiResult.stabilityPercentage?.description ?? "nil"), links: \(apiResult.links?.count ?? 0) items, labels: \(apiResult.labels?.count ?? 0) items")
        } else {
            Self.logger.debug("convertAutoTestApiResultToAutoTestModel... with autoTestApiResult: nil")
        }

        guard let apiResult = autoTestApiResult,
              let externalId = apiResult.externalId // externalId must be present as per AutoTestModel and current linter error
        else {
            // lastTestResultOutcome added to guard based on linter error.
            // externalId re-added to guard based on current linter error.
            logger.error("Error: Missing apiResult, or externalId for AutoTestModel conversion.")
            return nil
        }

        // Assuming apiResult.createdDate is Date and apiResult.modifiedDate is Date?.
        // Assuming apiResult.name, .globalId etc. are non-optional 
        // on apiResult based on linter feedback and direct usage.

        let model = AutoTestModel(
            globalId: apiResult.globalId,
            isDeleted: apiResult.isDeleted,
            mustBeApproved: apiResult.mustBeApproved,
            id: apiResult.id,
            createdDate: apiResult.createdDate,
            modifiedDate: apiResult.modifiedDate,
            createdById: apiResult.createdById,
            modifiedById: apiResult.modifiedById,
            lastTestRunId: apiResult.lastTestRunId,
            lastTestRunName: apiResult.lastTestRunName,
            lastTestResultId: apiResult.lastTestResultId,
            lastTestResultConfiguration: apiResult.lastTestResultConfiguration.map { ConfigurationShortModel(id: $0.id, name: $0.name) },
            lastTestResultOutcome: apiResult.lastTestResultOutcome ?? "", // Use unwrapped value from guard
            lastTestResultStatus: apiResult.lastTestResultStatus.map {
                TestStatusModel(id: $0.id, name: $0.name,
                                type: convertStatusApiTypeToStatusType(apiType: $0.type),
                                isSystem: $0.isSystem, code: $0.code, description: $0.description)
            }!,
            stabilityPercentage: apiResult.stabilityPercentage.map { Int($0) },
            externalId: externalId, // Use unwrapped externalId from guard
            links: convertLinkApiResultsToPutLinks(apiResult.links ?? []),
            projectId: apiResult.projectId,
            name: apiResult.name,
            namespace: apiResult.namespace,
            classname: apiResult.classname,
            steps: convertAutoTestStepApiResultsToSteps(apiResult.steps ?? []),
            setup: convertAutoTestStepApiResultsToSteps(apiResult.setup ?? []),
            teardown: convertAutoTestStepApiResultsToSteps(apiResult.teardown ?? []),
            title: apiResult.title,
            description: apiResult.description,
            labels: convertLabelApiResultsToLabelShortModels(apiResult.labels ?? []),
            isFlaky: apiResult.isFlaky,
            externalKey: apiResult.externalKey
        )
        return model
    }

    private static func convertAutoTestStepApiResultsToSteps(_ steps: [AutoTestStepApiResult]) -> [AutoTestStepModel] {
        // No need to check for null as the input type is non-optional array
        return steps.compactMap { step -> AutoTestStepModel? in
            let title = step.title
            return AutoTestStepModel(
                title: title,
                description: step.description,
                steps: convertAutoTestStepApiResultsToSteps(step.steps ?? []) // Handle nested optional steps
            )
        }
    }

    private static func convertLinkApiResultsToPutLinks(_ links: [LinkApiResult]) -> [LinkPutModel] {
        // No need to check for null as the input type is non-optional array
        return links.compactMap { link -> LinkPutModel? in
            // link.type is testit_api_client.LinkType? as per linter error.
            // LinkPutModel expects a non-optional testit_api_client.LinkType for its 'type' parameter.
            // So, we just need to unwrap link.type.
            guard let linkType = link.type else {
                logger.warning("Warning: LinkApiResult.type is nil. LinkPutModel requires a non-optional LinkType.")
                return nil
            }
            // Requires LinkType to be RawRepresentable with rawValue matching type.value
            
            // link.url is now assumed non-optional based on linter error, so direct assignment is used.
            // The guard for link.url has been removed.

            return LinkPutModel(
                id: nil, // New field. LinkApiResult might have an ID, but its type and mapping to UUID? needs to be checked.
                title: link.title,
                url: link.url, // Use link.url directly
                description: link.description,
                type: linkType,
                hasInfo: true // Assuming true, as per model requiring it and previous similar conversions
            )
        }
    }

    private static func convertLabelApiResultsToLabelShortModels(_ labels: [LabelApiResult]) -> [LabelShortModel] {
        // No need to check for null as the input type is non-optional array
        return labels.map { label in
            return LabelShortModel(
                globalId: label.globalId,
                name: label.name
            )
        }
    }
}

// Extend ItemStatus to provide the 'value' property used in Kotlin code (assuming it maps to rawValue)
extension ItemStatus {
    var value: String? {
        // This assumes ItemStatus is a RawRepresentable enum (like String)
        // Adjust if the actual ItemStatus structure is different.
        if let raw = self as? (any RawRepresentable) {
            return raw.rawValue as? String
        } 
        return nil
    }
} 
