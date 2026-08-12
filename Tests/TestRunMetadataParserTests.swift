import XCTest
@testable import testit_adapters_swift
import AdaptersApi

final class TestRunMetadataParserTests: XCTestCase {

    func testParseTags_CommaSeparated() {
        XCTAssertEqual(
            TestRunMetadataParser.parseTags("smoke, nightly, regression"),
            ["smoke", "nightly", "regression"]
        )
    }

    func testParseTags_JsonArray() {
        XCTAssertEqual(
            TestRunMetadataParser.parseTags("[\"smoke\", \"nightly\"]"),
            ["smoke", "nightly"]
        )
    }

    func testParseTags_EmptyOrInvalid_ReturnsEmpty() {
        XCTAssertEqual(TestRunMetadataParser.parseTags(nil), [])
        XCTAssertEqual(TestRunMetadataParser.parseTags(""), [])
        XCTAssertEqual(TestRunMetadataParser.parseTags("null"), [])
        XCTAssertEqual(TestRunMetadataParser.parseTags("[invalid"), [])
    }

    func testParseLinks_ValidJson_DefaultsTypeToRelated() {
        let raw = """
        [
          {"url":"https://gitlab.example.com/jobs/1","title":"CI Job"},
          {"url":"https://example.com/issue/2","title":"Bug","type":"Defect"}
        ]
        """

        let links = TestRunMetadataParser.parseLinks(raw)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].url, "https://gitlab.example.com/jobs/1")
        XCTAssertEqual(links[0].title, "CI Job")
        XCTAssertNil(links[0].type)

        let createModels = TestRunMetadataParser.toCreateLinkApiModels(links)
        XCTAssertEqual(createModels[0].type, .related)
        XCTAssertEqual(createModels[1].type, .defect)
    }

    func testParseLinks_SkipsEmptyUrlAndInvalidJson() {
        let raw = """
        [
          {"url":"","title":"broken"},
          {"url":"https://ok.example.com"}
        ]
        """
        let links = TestRunMetadataParser.parseLinks(raw)
        XCTAssertEqual(links.map(\.url), ["https://ok.example.com"])
        XCTAssertEqual(TestRunMetadataParser.parseLinks("{bad"), [])
    }

    func testMergeTags_PreservesExistingAndAddsNew() {
        let merged = TestRunMetadataParser.mergeTags(
            existing: ["ui", "smoke"],
            incoming: ["smoke", "nightly"]
        )
        XCTAssertEqual(merged, ["ui", "smoke", "nightly"])
    }

    func testMergeLinks_DeduplicatesByUrl() {
        let existing = [
            UpdateLinkApiModel(url: "https://a.example.com", type: .related)
        ]
        let incoming = [
            UpdateLinkApiModel(title: "A", url: "https://a.example.com", type: .defect),
            UpdateLinkApiModel(title: "B", url: "https://b.example.com", type: .related)
        ]

        let merged = TestRunMetadataParser.mergeLinks(existing: existing, incoming: incoming)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.url), ["https://a.example.com", "https://b.example.com"])
        XCTAssertEqual(merged[0].type, .related)
        XCTAssertEqual(merged[1].title, "B")
    }
}
