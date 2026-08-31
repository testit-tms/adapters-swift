import XCTest
@testable import testit_adapters_swift
import AdaptersApi

final class ConverterLayerTests: XCTestCase {

    private let projectId = UUID()

    private func makeResult(layer: String? = nil) -> TestResultCommon {
        TestResultCommon(
            uuid: projectId.uuidString,
            externalId: "ext-layer-test",
            name: "Layer test",
            layer: layer
        )
    }

    private func makeExistingAutotest(layer: LayerApiResult? = nil) -> AutoTestApiResult {
        AutoTestApiResult(
            id: UUID(),
            projectId: projectId,
            externalId: "ext-layer-test",
            name: "Existing",
            isFlaky: false,
            globalId: 1,
            layer: layer
        )
    }

    func testCreate_WithLayer_SendsRunSource() {
        let model = Converter.testResultToAutoTestCreateApiModel(result: makeResult(layer: TestLayers.API), projectId: projectId)

        XCTAssertEqual(model?.layer?.name, "API")
        XCTAssertEqual(model?.layer?.source, .run)
    }

    func testCreate_WithoutLayer_OmitsField() {
        let model = Converter.testResultToAutoTestCreateApiModel(result: makeResult(), projectId: projectId)

        XCTAssertNil(model?.layer)
    }

    func testCreate_CustomLayerString() {
        let model = Converter.testResultToAutoTestCreateApiModel(result: makeResult(layer: "my-custom-layer"), projectId: projectId)

        XCTAssertEqual(model?.layer?.name, "my-custom-layer")
        XCTAssertEqual(model?.layer?.source, .run)
    }

    func testUpdate_WithLayer_SendsResetLayerFalse() {
        let model = Converter.testResultToAutoTestUpdateApiModel(result: makeResult(layer: TestLayers.E2E), projectId: projectId, isFlaky: false)

        XCTAssertEqual(model?.layer?.name, "E2E")
        XCTAssertEqual(model?.layer?.source, .run)
        XCTAssertEqual(model?.resetLayer, false)
    }

    func testUpdate_WithoutLayer_SendsResetLayerFalseOnly() {
        let model = Converter.testResultToAutoTestUpdateApiModel(result: makeResult(), projectId: projectId, isFlaky: false)

        XCTAssertNil(model?.layer)
        XCTAssertEqual(model?.resetLayer, false)
    }

    func testFailedUpdatePath_AppliesLayerFromTest() {
        let existing = makeExistingAutotest(layer: LayerApiResult(name: "UI", source: .manual))
        let model = Converter.autoTestApiResultToAutoTestUpdateApiModel(
            autoTestApiResult: existing,
            links: nil,
            isFlaky: false,
            layerName: TestLayers.API
        )

        XCTAssertEqual(model?.layer?.name, "API")
        XCTAssertEqual(model?.layer?.source, .run)
        XCTAssertEqual(model?.resetLayer, false)
    }

    func testFailedUpdatePath_WithoutLayerInTest_OmitsLayer() {
        let existing = makeExistingAutotest(layer: LayerApiResult(name: "UI", source: .manual))
        let model = Converter.autoTestApiResultToAutoTestUpdateApiModel(
            autoTestApiResult: existing,
            links: nil,
            isFlaky: false
        )

        XCTAssertNil(model?.layer)
        XCTAssertEqual(model?.resetLayer, false)
    }
}
