import Foundation
import AdaptersApi
import os.log

enum Converter {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "Converter")
    private static let defaultLinkType: AdaptersApi.LinkType = .related

    // Adapters API LinkType is required; use Related when the source link type is missing or invalid.
    private static func toApiLinkType(from rawValue: String) -> AdaptersApi.LinkType {
        guard let linkType = AdaptersApi.LinkType(rawValue: rawValue) else {
            logger.warning("Warning: Could not convert LinkType rawValue: \(rawValue). Fallback to Related.")
            return defaultLinkType
        }
        return linkType
    }

    static func testResultToAutoTestCreateApiModel(result: TestResultCommon, projectId: UUID?) -> AutoTestCreateApiModel? {

        guard let uuidString = result.uuid,
            let projId = projectId ?? UUID(uuidString: uuidString)
        else {
            logger.error("Error: Missing required uuid in TestResultCommon or invalid UUID string for AutoTestCreateApiModel conversion.")
            return nil
        }

        let model = AutoTestCreateApiModel(
            projectId: projId,
            externalId: result.externalId,
            externalKey: result.externalKey,
            name: result.name,
            namespace: result.spaceName,
            classname: result.className,
            title: result.title,
            description: result.description,
            isFlaky: false,
            steps: convertSteps(result.getSteps()),
            setup: nil,
            teardown: nil,
            shouldCreateWorkItem: result.automaticCreationTestCases,
            labels: labelsPostConvert(result.labels),
            links: convertPostLinks(result.linkItems),
            tags: result.tags
        )
        return model
    }

    static func testResultToAutoTestUpdateApiModel(result: TestResultCommon) -> AutoTestUpdateApiModel? {
        return testResultToAutoTestUpdateApiModel(result: result, projectId: nil, isFlaky: nil)
    }

    static func testResultToAutoTestUpdateApiModel(result: TestResultCommon,
                                             projectId: UUID?,
                                             isFlaky: Bool?) -> AutoTestUpdateApiModel? {
        // externalId and name are non-optional in TestResultCommon
        let uuidString = result.externalId
        guard let projId = projectId ?? UUID(uuidString: uuidString)
        else {
            // Update error message
            logger.error("Error: Missing required uuid in TestResultCommon or invalid UUID string for AutoTestUpdateApiModel conversion.")
            return nil
        }

        let model = AutoTestUpdateApiModel(
            id: nil,
            projectId: projId,
            externalId: result.externalId,
            externalKey: result.externalKey,
            
            name: result.name,
            namespace: result.spaceName,
            classname: result.className,
            title: result.title,
            description: result.description,
            isFlaky: isFlaky,
            steps: convertSteps(result.getSteps()),
            setup: [],
            teardown: [],
            labels: labelsPostConvert(result.labels),
            links: convertPutLinks(result.linkItems),
            tags: result.tags
        )
        return model
    }

    static func testResultToTestResultUpdateModel(result: TestResultResponse,
                                                  setupResults: [AutoTestStepResultUpdateRequest]?,
                                                  teardownResults: [AutoTestStepResultUpdateRequest]?
    ) -> TestResultUpdateRequest {
        let model = TestResultUpdateRequest(
            failureClassIds: result.failureClassIds,
            statusCode: result.status?.code,
            comment: result.comment,
            links: convertLinkApiResultsToCreateLinks(result.links ?? []),
            stepResults: result.stepResults,
            attachments: convertAttachmentsFromResult(result.attachments ?? []),
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
    static func convertFixture(fixtures: [FixtureResult], parentUuid: String?) -> [AutoTestStepApiModel] {
        return fixtures
            .filter { filterSteps(parentUuid: parentUuid, f: $0) }
            .compactMap { fixture -> AutoTestStepApiModel? in
                guard let name = fixture.name else { return nil } // Handle optional name
                let model = AutoTestStepApiModel(
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

    static func autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: AutoTestApiResult) -> AutoTestUpdateApiModel? {
        return autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: autoTestApiResult, links: nil, isFlaky: nil, setup: nil, teardown: nil)
    }

    static func autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: AutoTestApiResult,
                                                setup: [AutoTestStepApiModel]?,
                                                teardown: [AutoTestStepApiModel]?,
                                                isFlaky: Bool?) -> AutoTestUpdateApiModel? {
        return autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: autoTestApiResult, links: nil, isFlaky: isFlaky, setup: setup, teardown: teardown)
    }

    static func autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: AutoTestApiResult,
                                                links: [LinkUpdateApiModel]?,
                                                isFlaky: Bool?) -> AutoTestUpdateApiModel? {
        return autoTestApiResultToAutoTestUpdateApiModel(autoTestApiResult: autoTestApiResult, links: links, isFlaky: isFlaky, setup: nil, teardown: nil)
    }

    static func autoTestStepApiResultToAutoTestStepApiModel(
            autoTestStepApiResult: AutoTestStepApiResult
        ) -> AutoTestStepApiModel? {
            return AutoTestStepApiModel(
                title: autoTestStepApiResult.title,
                description: autoTestStepApiResult.description,
                steps: autoTestStepApiResult.steps?.compactMap { step in
                    autoTestStepApiResultToAutoTestStepApiModel(autoTestStepApiResult: step)
                } ?? []
            )
        }

    static func autoTestStepModelToAutoTestStepApiModel(
            autoTestStepModel: AutoTestStepModel
        ) -> AutoTestStepApiModel? {
            return AutoTestStepApiModel(
                title: autoTestStepModel.title,
                description: autoTestStepModel.description,
                steps: autoTestStepModel.steps?.compactMap { step in
                    autoTestStepModelToAutoTestStepApiModel(autoTestStepModel: step)
                } ?? []
            )
        }
    
    static func autoTestStepApiModelToAutoTestStepModel(
        autoTestStepApiModel: AutoTestStepApiModel
    ) -> AutoTestStepModel {
        return AutoTestStepModel(
            title: autoTestStepApiModel.title,
            description: autoTestStepApiModel.description,
            steps: autoTestStepApiModel.steps?.compactMap { step in
                autoTestStepApiModelToAutoTestStepModel(autoTestStepApiModel: step)
            }
        )
    }

    static func autoTestApiResultToAutoTestUpdateApiModel(
        autoTestApiResult: AutoTestApiResult,
        links: [LinkUpdateApiModel]?,
        isFlaky: Bool?,
        setup: [AutoTestStepApiModel]?,
        teardown: [AutoTestStepApiModel]?
    ) -> AutoTestUpdateApiModel? {
        // externalId and name are non-optional in AutoTestApiResult, so no need to conditionally bind them.
        // The guard statement is removed as there are no longer any optional values to check here
        // that would cause the function to return nil early based on missing externalId or name.
        // If other fields were critical and optional, they would remain in a guard.

        let model = AutoTestUpdateApiModel(
            id: autoTestApiResult.id,
            projectId: autoTestApiResult.projectId,
            externalId: autoTestApiResult.externalId!,
            externalKey: autoTestApiResult.externalKey,
            name: autoTestApiResult.name,
            namespace: autoTestApiResult.namespace,
            classname: autoTestApiResult.classname,
            title: autoTestApiResult.title,
            description: autoTestApiResult.description,
            isFlaky: isFlaky,
            steps: autoTestApiResult.steps?.compactMap { autoTestStepApiResultToAutoTestStepApiModel(autoTestStepApiResult: $0) },
            setup: setup ?? autoTestApiResult.setup?.compactMap { autoTestStepApiResultToAutoTestStepApiModel(autoTestStepApiResult: $0) },
            teardown: teardown ?? autoTestApiResult.teardown?.compactMap { autoTestStepApiResultToAutoTestStepApiModel(autoTestStepApiResult: $0) },
            labels: labelsConvert(convertLabelApiResultsToLabelShortModels(autoTestApiResult.labels ?? [])),
            links: links ?? autoTestApiResult.links?.compactMap { LinkUpdateApiModel(title: $0.title, url: $0.url, description: $0.description, type: $0.type) },
            tags: autoTestApiResult.tags
        )
        return model
    }

    static func testResultToAutoTestResultsForTestRunModel(
        result: TestResultCommon,
        configurationId: UUID?
    ) -> AutoTestResultsForTestRunModel? {
        return testResultToAutoTestResultsForTestRunModel(result: result, configurationId: configurationId, setupResults: nil, teardownResults: nil)
    }

    // Passed, failed, Skipped, InProgress, Blocked
    static func mapStatusType(status: String) -> TestStatusType {
        if status == "Passed" {
            return TestStatusType.succeeded
        }
        if status == "Failed" {
            return TestStatusType.failed
        }
        if status == "InProgress" {
            return TestStatusType.inProgress
        }
        if status == "Blocked" {
            return TestStatusType.incomplete
        }
        
        return TestStatusType.incomplete
    }

    static func testResultToAutoTestResultsForTestRunModel(result: TestResultCommon,
                                                           configurationId: UUID?,
                                                           setupResults: [AttachmentPutModelAutoTestStepResultsModel]?,
                                                           teardownResults: [AttachmentPutModelAutoTestStepResultsModel]?
    ) -> AutoTestResultsForTestRunModel? {

        // Safely unwrap required fields
        // externalId, start, and stop are non-optional in TestResultCommon
        guard let itemStatusValue = result.itemStatus?.value, // Assuming ItemStatus has a String 'value' property
              let uuidString = result.uuid,
              let configId = configurationId ?? UUID(uuidString: uuidString) // Use guard let for nil-coalescing with failable init
        else {
            // Update error message
            logger.error("Error: Missing required fields (itemStatus, uuid, configurationId) or invalid status/uuid/configId in TestResultCommon for AutoTestResultsForTestRunModel conversion.")
            return nil
        }
        var statusType = mapStatusType(status: itemStatusValue)

        let throwable = result.throwable
        let message = throwable?.localizedDescription ?? result.message // Get error description
        let traces = throwable != nil ? "\(String(describing: throwable))" : nil // Simple error description

        let model = AutoTestResultsForTestRunModel(
            configurationId: configId,
            links: convertPostLinksToPostModel(result.resultLinks),
            failureReasonNames: nil, // New field, assuming nil. Populate if source exists in TestResultCommon.
            autoTestExternalId: result.externalId,
            statusType: statusType,
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
    
    static func convertPostLinksToPostModel(_ links: [LinkItem]) -> [LinkPostModel] {
            return links.compactMap { link -> LinkPostModel? in
                return LinkPostModel(
                    title: link.title,
                    url: link.url,
                    description: link.description,
                    type: toApiLinkType(from: link.type.rawValue),
                    hasInfo: false
                )
            }
        }

    static func convertPostLinks(_ links: [LinkItem]) -> [LinkCreateApiModel] {
        return links.compactMap { link -> LinkCreateApiModel? in
            return LinkCreateApiModel(
                title: link.title,
                url: link.url,
                description: link.description,
                type: toApiLinkType(from: link.type.rawValue)
            )
        }
    }

    static func convertPutLinks(_ links: [LinkItem]) -> [LinkUpdateApiModel] {
        return links.compactMap { link -> LinkUpdateApiModel? in
            return LinkUpdateApiModel(
                id: nil,
                title: link.title,
                url: link.url,
                description: link.description,
                type: toApiLinkType(from: link.type.rawValue)
            )
        }
    }

    private static func convertLinkApiResultsToCreateLinks(_ links: [LinkApiResult]) -> [CreateLinkApiModel] {
        return links.map { link in
            CreateLinkApiModel(
                title: link.title,
                url: link.url,
                description: link.description,
                type: link.type
            )
        }
    }

    static func convertSteps(_ steps: [StepResult]) -> [AutoTestStepApiModel] {
        return steps.compactMap { step -> AutoTestStepApiModel? in
             guard let name = step.name else { return nil } // Steps require a name/title
             return AutoTestStepApiModel(
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

    static func labelsConvert(_ labels: [LabelShortModel]) -> [LabelApiModel] {
        return labels.map { label in
            LabelApiModel(name: label.name)
        }
    }

    static func labelsPostConvert(_ labels: [Label]) -> [LabelApiModel] {
         return labels.compactMap { label -> LabelApiModel? in
            guard let name = label.name else { return nil }
            return LabelApiModel(name: name)
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

    // MARK: - Test Run Update Helpers

    static func buildUpdateEmptyTestRunApiModel(_ testRun: TestRunApiResult) -> UpdateEmptyTestRunApiModel {
        return UpdateEmptyTestRunApiModel(
            id: testRun.id,
            name: testRun.name,
            attachments: buildAssignAttachmentApiModels(testRun.attachments),
            links: buildUpdateLinkApiModels(testRun.links),
            tags: testRun.tags
        )
    }

    static func buildAssignAttachmentApiModels(_ attachments: [AttachmentApiResult]) -> [AssignAttachmentApiModel] {
        return attachments.map { attachment in
            AssignAttachmentApiModel(id: attachment.id)
        }
    }

    static func buildUpdateLinkApiModels(_ links: [LinkApiResult]) -> [UpdateLinkApiModel] {
        return links.map { link in
            UpdateLinkApiModel(
                id: link.id,
                title: link.title,
                url: link.url,
                description: link.description,
                type: link.type
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
