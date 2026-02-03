import Foundation
import os.log
import testit_api_client


class HttpWriter: Writer {
    
    private var configuration: ClientConfiguration
    private let client: ApiClient
    private let storage: ResultStorage
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter", category: "HttpWriter")

    private var testResults: [String: UUID] = [:] // Maps TestResultCommon.uuid to the UUID received from API

    func setTestRun(testRunId: String) {
        self.configuration.testRunId = testRunId
    }
    
    init(configuration: ClientConfiguration, client: ApiClient, storage: ResultStorage) {
        self.configuration = configuration
        self.client = client
        self.storage = storage
        Self.logger.debug("HttpWriter initialized.")
    }

    func writeTest(_ testResultCommon: TestResultCommon) {
        do {
            Self.logger.debug("Attempting to write auto test: \(testResultCommon.externalId)")

            let autoTestApiResult = try client.getAutoTestByExternalId(externalId: testResultCommon.externalId)
            let workItemIds = testResultCommon.workItemIds // Assuming this is [String]
            var autoTestId: String?
            
            let autotestModel = Converter.convertAutoTestApiResultToAutoTestModel(autoTestApiResult: autoTestApiResult)

            if let existingAutotest = autotestModel {
                // Self.logger.debug("Auto test exists. Updating auto test: \(existingAutotest.externalId)")
                
                let AutoTestUpdateApiModel: AutoTestUpdateApiModel
                if testResultCommon.itemStatus == .failed {
                    AutoTestUpdateApiModel = Converter.autoTestModelToAutoTestUpdateApiModel(
                        autoTestModel: existingAutotest,
                        links: Converter.convertPutLinks(testResultCommon.linkItems), // linkItems: [LinkItemModel]?
                        isFlaky: false
                    )!
                } else {
                    guard let projectId = UUID(uuidString: configuration.projectId) else {
                        Self.logger.error("Invalid project ID format in configuration: \(self.configuration.projectId)")
                        return
                    }
                    AutoTestUpdateApiModel = Converter.testResultToAutoTestUpdateApiModel(
                        result: testResultCommon,
                        projectId: projectId,
                        isFlaky: false
                    )!
                }
                autoTestId = existingAutotest.id.uuidString
                do {
                    Self.logger.debug("writeTest: Calling client.updateAutoTest with ")
                    // TODO: may be obsolete api call
                    try client.updateAutoTest(model: AutoTestUpdateApiModel)
                    Self.logger.info("Successfully updated autotest with externalId: \(testResultCommon.externalId)")
                } catch {
                    Self.logger.error("Error updating autotest with externalId \(testResultCommon.externalId): \(error.localizedDescription). Proceeding without this autotest ID.")
                    // autoTestId keep nil or the same as before, the execution continues
                }
            } else {
                Self.logger.debug("Creating new auto test: \(testResultCommon.externalId)")
                guard let projectId = UUID(uuidString: configuration.projectId) else {
                    Self.logger.error("Invalid project ID format in configuration: \(self.configuration.projectId)")
                    return
                }
                let newAutoTestCreateApiModel = Converter.testResultToAutoTestCreateApiModel(result: testResultCommon, projectId: projectId)
                // Assuming createAutoTest returns the ID of the created autotest (String or UUID)
                
                let createdAutoTestIdString = try! client.createAutoTest(model: newAutoTestCreateApiModel!)
                autoTestId = createdAutoTestIdString
                
            }

            if let currentAutoTestId = autoTestId, !workItemIds.isEmpty {
                try updateTestLinkToWorkItems(autoTestId: currentAutoTestId, workItemIds: workItemIds)
            }
            
            guard let configId = UUID(uuidString: configuration.configurationId) else {
                Self.logger.error("Invalid configuration ID format: \(self.configuration.configurationId)")
                return
            }
            
            Self.logger.debug("calling testResultToAutoTestResultsForTestRunModel inside of writeTest....")
            let autoTestResultsModel = Converter.testResultToAutoTestResultsForTestRunModel(
                result: testResultCommon, configurationId: configId, setupResults: nil, teardownResults: nil
            )

            let resultsForApi: [AutoTestResultsForTestRunModel] = [autoTestResultsModel!]
            
            

            let testRunUuidString = configuration.testRunId
            guard !testRunUuidString.isEmpty && testRunUuidString.lowercased() != "null" else {
                Self.logger.error("Cannot send test results: Test Run ID is missing or empty. In adapterMode=2, test run should be created automatically.")
                return
            }
            
            print("[TestItAdapter] Sending result by testRunId: \(testRunUuidString)")
            Self.logger.debug("Sending result by testRunId: \(testRunUuidString)")
            
            let idsSentToApi = try client.sendTestResults(testRunUuid: testRunUuidString, models: resultsForApi) // Assuming returns [String]?
            print("[TestItAdapter] ✓✓✓ Test result sent successfully! Received IDs: \(idsSentToApi)")
            if let firstIdString = idsSentToApi.first, let firstId = UUID(uuidString: firstIdString) {
                // Assuming testResultCommon.uuid is a String key
                testResults[testResultCommon.uuid!] = firstId
                print("[TestItAdapter] Result ID mapped: \(testResultCommon.uuid!) -> \(firstId)")
            }

        } catch let error as TmsApiClientError {
            print("[TestItAdapter] ERROR: API Client error writing autotest \(testResultCommon.externalId): \(error.localizedDescription)")
            Self.logger.error("API Client error writing autotest \(testResultCommon.externalId): \(error.localizedDescription). Response: N/A")
        } catch {
            print("[TestItAdapter] ERROR: Failed to write autotest \(testResultCommon.externalId): \(error.localizedDescription)")
            Self.logger.error("Failed to write autotest \(testResultCommon.externalId): \(error.localizedDescription)")
        }
    }

    private func updateTestLinkToWorkItems(autoTestId: String, workItemIds: [String]) throws {
        var mutableWorkItemIds = workItemIds 
        let linkedWorkItems = try client.getWorkItemsLinkedToTest(id: autoTestId) // Assuming returns [AutoTestWorkItemIdentifierApiResult]

        for linkedWorkItem in linkedWorkItems {
            // TODO: there where globalId instead of id for some reason
            let linkedWorkItemId = linkedWorkItem.id // Assuming globalId is UUID

            if let index = mutableWorkItemIds.firstIndex(of: linkedWorkItemId.uuidString) { // Convert UUID to String
                mutableWorkItemIds.remove(at: index)
                continue
            }

            if configuration.automaticUpdationLinksToTestCases {
                try client.unlinkAutoTestToWorkItem(id: autoTestId, workItemId: linkedWorkItemId.uuidString) // Convert UUID to String here as well
            }
        }

        if !mutableWorkItemIds.isEmpty {
            try client.linkAutoTestToWorkItems(id: autoTestId, workItemIds: mutableWorkItemIds)
        }
    }
    
    func writeClass(_ container: ClassContainer) {
        Self.logger.debug("writeClass started...")
        container.children.forEach { testUuidString in

            // let testUuid = UUID(uuidString: testUuidString)
            let testResultOpt = storage.getTestResult(testUuidString)
            let testResult = testResultOpt

            do {
                let autoTestApiResult = try client.getAutoTestByExternalId(externalId: testResult!.externalId)
                guard let autoTestModel = Converter.convertAutoTestApiResultToAutoTestModel(autoTestApiResult: autoTestApiResult) else {
                    Self.logger.warning("writeClass: Could not convert API result to autoTestModel for \(testResult!.externalId)")
                    return
                }

                var beforeClassFixtures = Converter.convertFixture(fixtures: container.beforeClassMethods, parentUuid: nil)
                let beforeEachFixtures = Converter.convertFixture(fixtures: container.beforeEachTest, parentUuid: testUuidString)
                beforeClassFixtures.append(contentsOf: beforeEachFixtures)

                var afterClassFixtures = Converter.convertFixture(fixtures: container.afterClassMethods, parentUuid: nil)
                let afterEachFixtures = Converter.convertFixture(fixtures: container.afterEachTest, parentUuid: testUuidString)
                afterClassFixtures.append(contentsOf: afterEachFixtures)

                let AutoTestUpdateApiModel = Converter.autoTestModelToAutoTestUpdateApiModel(
                    autoTestModel: autoTestModel,
                    setup: beforeClassFixtures,
                    teardown: afterClassFixtures,
                    isFlaky: false
                )
                Self.logger.debug("writeClass: Calling client.updateAutoTest with ")
                try client.updateAutoTest(model: AutoTestUpdateApiModel!)
                Self.logger.debug("writeClass: Successfully updated autotest \(autoTestModel.externalId) with class fixtures.")
            } catch {
                Self.logger.error("writeClass: Failed for test \(testResult!.externalId): \(error.localizedDescription)")
            }
        }
    }

    func writeTests(_ container: MainContainer) { // For MainContainer
        do {
            Self.logger.warning("HttpWriter.writeTests started...")
            let beforeAllFixtures = Converter.convertFixture(fixtures: container.beforeMethods, parentUuid: nil)
            let afterAllFixtures = Converter.convertFixture(fixtures: container.afterMethods, parentUuid: nil)
            let beforeResultAll = Converter.convertResultFixture(fixtures: container.beforeMethods, parentUuid: nil)
            let afterResultAll = Converter.convertResultFixture(fixtures: container.afterMethods, parentUuid: nil)

            for classUuidString in container.children {
                // let classUuid = UUID(uuidString: classUuidString)
                let classContainerOpt = storage.getClassContainer(classUuidString)
                let classContainer = classContainerOpt

                let beforeResultClass = Converter.convertResultFixture(fixtures: classContainer!.beforeClassMethods, parentUuid: nil)
                let afterResultClass = Converter.convertResultFixture(fixtures: classContainer!.afterClassMethods, parentUuid: nil)

                for testUuidString in classContainer!.children {
                    // let testUuid = UUID(uuidString: testUuidString)
                    let testResultOpt = storage.getTestResult(testUuidString)
                    let testResult = testResultOpt

                    // Kotlin: if (test?.isEmpty!!) -> Swift: check if optional is nil or if it has an isEmpty property
                    // Assuming testResult implies it's valid if not nil

                    do {
                        Self.logger.debug("Get autoTestByExternalId with externalId: \(testResult!.externalId) in writeTests")
                        var autoTestApiResult = try client.getAutoTestByExternalId(externalId: testResult!.externalId)
                        // update external key with new externalKey
                        autoTestApiResult?.externalKey = testResult?.externalKey

                        if autoTestApiResult != nil {
                            //Self.logger.debug("Auto test exists. Updating auto test: \(autoTestApiResult.externalId)")
                        } else {
                            Self.logger.debug("Creating new auto test: \(testResult!.externalId)")
                            guard let projectId = UUID(uuidString: configuration.projectId) else {
                                Self.logger.error("Invalid project ID format in configuration: \(self.configuration.projectId)")
                                return
                            }
                            let newAutoTestCreateApiModel = Converter.testResultToAutoTestCreateApiModel(result: testResult!, projectId: projectId)
                            // Assuming createAutoTest returns the ID of the created autotest (String or UUID)
                            
                            let createdAutoTestIdString = try! client.createAutoTest(model: newAutoTestCreateApiModel!)
                            autoTestApiResult = try client.getAutoTestByExternalId(externalId: testResult!.externalId)
                        }
                        let autoTestModel = Converter.convertAutoTestApiResultToAutoTestModel(autoTestApiResult: autoTestApiResult)

                        var beforeFinish = beforeAllFixtures
                        if let existingSetup = autoTestModel!.setup { // Assuming setup is [FixtureResultModel]?
                            beforeFinish.append(contentsOf: existingSetup)
                        }
                        
                        let classAfterFixtures = Converter.convertFixture(fixtures: classContainer!.afterClassMethods, parentUuid: nil)
                        var afterFinish = autoTestModel!.teardown ?? [] // Assuming teardown is [FixtureResultModel]?
                        afterFinish.append(contentsOf: classAfterFixtures)
                        afterFinish.append(contentsOf: afterAllFixtures)

                        let AutoTestUpdateApiModel = Converter.autoTestModelToAutoTestUpdateApiModel(
                            autoTestModel: autoTestModel!,
                            setup: Converter.autoTestStepModelToAutoTestStepApiModel(beforeFinish),
                            teardown: Converter.autoTestStepModelToAutoTestStepApiModel(afterFinish),
                            isFlaky: false
                        )
                        Self.logger.debug("writeTests: Calling client.updateAutoTest with ")
                        try client.updateAutoTest(model: AutoTestUpdateApiModel!)

                        let beforeResultEach = Converter.convertResultFixture(fixtures: classContainer!.beforeEachTest, parentUuid: testUuidString)
                        var beforeResultFinish = beforeResultAll
                        beforeResultFinish.append(contentsOf: beforeResultClass)
                        beforeResultFinish.append(contentsOf: beforeResultEach)

                        let afterResultEach = Converter.convertResultFixture(fixtures: classContainer!.afterEachTest, parentUuid: testUuidString)
                        var afterResultFinish: [AttachmentPutModelAutoTestStepResultsModel] = [] // Explicit type
                        afterResultFinish.append(contentsOf: afterResultEach)
                        afterResultFinish.append(contentsOf: afterResultClass)
                        afterResultFinish.append(contentsOf: afterResultAll)
                        
                        // Assuming AutoTestResultsForTestRunModel can take nil for configurationId
                        Self.logger.debug("calling testResultToAutoTestResultsForTestRunModel inside of writeTests....")
                        let _ = Converter.testResultToAutoTestResultsForTestRunModel(
                            result: testResult!,
                            configurationId: nil, // As per Kotlin logic
                            setupResults: beforeResultFinish,
                            teardownResults: afterResultFinish
                        )

                        guard let testResultId = testResults[testResult!.uuid!] else { // Use uuidString for key
                            Self.logger.warning("No stored testResultId found for test UUID: \(testResult!.uuid!)")
                            continue
                        }
                        
                        let resultModelFromServer = try client.getTestResult(uuid: testResultId) // Assuming client.getTestResult(id: UUID)
                        
                        let beforeResultRequest = modelToRequest(models: beforeResultFinish)
                        let afterResultRequest = modelToRequest(models: afterResultFinish)

                        let updateModel = Converter.testResultToTestResultUpdateModel(
                            result: resultModelFromServer, // Pass the fetched model
                            setupResults: beforeResultRequest,
                            teardownResults: afterResultRequest
                        )
                        
                        try client.updateTestResult(uuid: testResultId, model: updateModel)
                        Self.logger.debug("Successfully updated test result for \(testResult!.externalId)")

                    } catch {
                        Self.logger.error("Failed to update autotest/testResult for \(testResult!.externalId): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            Self.logger.error("Error during MainContainer (writeTests) processing: \(error.localizedDescription)")
        }
    }

    // Assuming AttachmentPutModelAutoTestStepResultsModel is the Swift equivalent for the model used in Kotlin
    // And AutoTestStepResultUpdateRequest is the Swift equivalent for the request model
    func modelToRequest(models: [AttachmentPutModelAutoTestStepResultsModel]) -> [AutoTestStepResultUpdateRequest] {
        return models.map { model in
            AutoTestStepResultUpdateRequest(
                title: model.title,
                description: model.description,
                // TODO: check if info exists
                // info: model.info, // Assuming 'info' property exists
                startedOn: model.startedOn,
                completedOn: model.completedOn,
                duration: model.duration,
                outcome: model.outcome, // Assuming 'outcome' maps correctly
                stepResults: stepModelToRequest(models: model.stepResults),
                attachments: attachmentModelToRequest(models: model.attachments),
                parameters: model.parameters // Assuming 'parameters' property exists
            )
        }
    }

    func attachmentModelToRequest(models: [AttachmentPutModel]?) -> [AttachmentUpdateRequest]? {
        return models?.map { model in
            AttachmentUpdateRequest(id: model.id) // Assuming AttachmentPutModel has 'id'
        }
    }

    func stepModelToRequest(models: [AttachmentPutModelAutoTestStepResultsModel]?) -> [AutoTestStepResultUpdateRequest]? {
        return models?.map { model in
            AutoTestStepResultUpdateRequest(
                title: model.title,
                description: model.description,
                // TODO: check if info exists
                //info: model.info,
                startedOn: model.startedOn,
                completedOn: model.completedOn,
                duration: model.duration,
                outcome: model.outcome,
                stepResults: (model.stepResults?.isEmpty == false) ? stepModelToRequest(models: model.stepResults) : [],
                attachments: attachmentModelToRequest(models: model.attachments),
                parameters: model.parameters
            )
        }
    }

    func writeAttachment(_ attachmentPath: String) -> String? { // Return String? to align with potential failure
        do {
            // Assuming client.addAttachment returns the ID of the attachment or throws.
            let attachmentId = try client.addAttachment(path: attachmentPath)
            Self.logger.debug("Successfully uploaded attachment from path: \(attachmentPath), ID: \(attachmentId)")
            return attachmentId
        } catch {
            Self.logger.error("Failed to write attachment from path \(attachmentPath): \(error.localizedDescription)")
            return nil
        }
    }

    func addUuid(key: String, uuid: UUID) {
        self.testResults[key] = uuid
        Self.logger.debug("Added UUID \(uuid.uuidString) for key \(key) to testResults.")
    }
}

