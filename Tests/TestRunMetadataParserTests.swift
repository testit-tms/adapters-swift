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

    func testV2TestRunPayloadToModel_MapsLinksAttachmentsTagsAndDescription() throws {
        let attachmentId = UUID()
        let linkId = UUID()
        let statusId = UUID()
        let runId = UUID()
        let json = """
        {
          "id": "\(runId.uuidString)",
          "name": "TestRun_2026",
          "description": "existing description",
          "launchSource": "Test IT",
          "stateName": "InProgress",
          "status": {
            "id": "\(statusId.uuidString)",
            "type": "Succeeded",
            "code": "PASSED"
          },
          "links": [
            {
              "id": "\(linkId.uuidString)",
              "title": "Link #1",
              "url": "https://example.com/1",
              "description": "first",
              "type": "Related"
            }
          ],
          "attachments": [
            {
              "id": "\(attachmentId.uuidString)",
              "fileId": "file-1",
              "type": "text/plain",
              "size": 10,
              "name": "a.txt"
            }
          ],
          "tags": ["smoke", {"name": "nightly"}],
          "testResults": [{"id": "ignored"}]
        }
        """.data(using: .utf8)!

        let model = try Converter.v2TestRunPayloadToModel(json)

        XCTAssertEqual(model.id, runId)
        XCTAssertEqual(model.name, "TestRun_2026")
        XCTAssertEqual(model.description, "existing description")
        XCTAssertEqual(model.launchSource, "Test IT")
        XCTAssertEqual(model.stateName, .inProgress)
        XCTAssertEqual(model.links.count, 1)
        XCTAssertEqual(model.links[0].url, "https://example.com/1")
        XCTAssertEqual(model.links[0].id, linkId)
        XCTAssertEqual(model.attachments.map(\.id), [attachmentId])
        XCTAssertEqual(model.tags, ["smoke", "nightly"])

        let update = Converter.buildUpdateEmptyTestRunApiModel(model)
        XCTAssertEqual(update.description, "existing description")
        XCTAssertEqual(update.launchSource, "Test IT")
        XCTAssertEqual(update.attachments?.map(\.id), [attachmentId])
        XCTAssertEqual(update.links?.map(\.url), ["https://example.com/1"])
    }
}
