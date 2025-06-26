import XCTest
@testable import TestItAdapter
import testit_api_client

class HtmlEscapeUtilsTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear environment variable before each test
        unsetenv("NO_ESCAPE_HTML")
    }
    
    override func tearDown() {
        // Clean up environment variable after each test
        unsetenv("NO_ESCAPE_HTML")
        super.tearDown()
    }
    
    // MARK: - Basic HTML Tag Escaping Tests
    
    func testEscapeHtmlTags_WithSimpleHtmlTags_ShouldEscape() {
        // Arrange
        let input = "<script>alert('xss')</script>"
        let expected = "\\<script>alert('xss')\\</script>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "HTML tags should be escaped")
    }
    
    func testEscapeHtmlTags_WithComplexHtmlTags_ShouldEscape() {
        // Arrange
        let input = "<div class=\"test\"><p>Hello <b>World</b></p></div>"
        let expected = "\\<div class=\"test\">\\<p>Hello \\<b>World\\</b>\\</p>\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Complex HTML tags should be escaped")
    }
    
    func testEscapeHtmlTags_WithSelfClosingTags_ShouldEscape() {
        // Arrange
        let input = "<img src=\"test.jpg\" /><br/>"
        let expected = "\\<img src=\"test.jpg\" />\\<br/>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Self-closing HTML tags should be escaped")
    }
    
    func testEscapeHtmlTags_WithNoHtmlTags_ShouldReturnOriginal() {
        // Arrange
        let input = "Just a regular string with no HTML"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, input, "String without HTML tags should remain unchanged")
    }
    
    func testEscapeHtmlTags_WithMathExpressions_ShouldNotEscape() {
        // Arrange
        let input = "2 < 3 and 5 > 4"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, input, "Math expressions without HTML tags should remain unchanged")
    }
    
    func testEscapeHtmlTags_WithAlreadyEscapedContent_ShouldNotDoubleEscape() {
        // Arrange
        let input = "\\<script>alert('test')\\</script>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, input, "Already escaped content should not be double-escaped")
    }
    
    func testEscapeHtmlTags_WithMixedEscapedAndUnescaped_ShouldEscapeOnlyUnescaped() {
        // Arrange
        let input = "\\<div><p>test</p>\\</div>"
        let expected = "\\<div>\\<p>test\\</p>\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should escape only unescaped tags")
    }
    
    func testEscapeHtmlTags_WithNilInput_ShouldReturnNil() {
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(nil)
        
        // Assert
        XCTAssertNil(result, "Nil input should return nil")
    }
    
    func testEscapeHtmlTags_WithEmptyString_ShouldReturnEmpty() {
        // Arrange
        let input = ""
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, "", "Empty string should remain empty")
    }
    
    // MARK: - Environment Variable Tests
    
    func testEscapeHtmlTags_WithNoEscapeEnvVar_ShouldReturnOriginal() {
        // Arrange
        setenv("NO_ESCAPE_HTML", "true", 1)
        let input = "<script>alert('xss')</script>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, input, "Should return original when NO_ESCAPE_HTML is true")
    }
    
    func testEscapeHtmlTags_WithNoEscapeEnvVarCaseInsensitive_ShouldReturnOriginal() {
        // Arrange
        setenv("NO_ESCAPE_HTML", "TRUE", 1)
        let input = "<div>test</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, input, "Should be case insensitive for TRUE")
    }
    
    func testEscapeHtmlTags_WithNoEscapeEnvVarFalse_ShouldEscape() {
        // Arrange
        setenv("NO_ESCAPE_HTML", "false", 1)
        let input = "<script>test</script>"
        let expected = "\\<script>test\\</script>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should escape when NO_ESCAPE_HTML is false")
    }
    
    // MARK: - String Array Tests
    
    func testEscapeHtmlInStringArray_WithHtmlTags_ShouldEscapeAll() {
        // Arrange
        let input = ["<div>test1</div>", "normal text", "<p>test2</p>"]
        let expected = ["\\<div>test1\\</div>", "normal text", "\\<p>test2\\</p>"]
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlInStringArray(input)
        
        // Assert
        XCTAssertEqual(result, expected, "All strings with HTML should be escaped")
    }
    
    func testEscapeHtmlInStringArray_WithNilInput_ShouldReturnNil() {
        // Act
        let result = HtmlEscapeUtils.escapeHtmlInStringArray(nil)
        
        // Assert
        XCTAssertNil(result, "Nil input should return nil")
    }
    
    func testEscapeHtmlInStringArray_WithEmptyArray_ShouldReturnEmpty() {
        // Arrange
        let input: [String] = []
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlInStringArray(input)
        
        // Assert
        XCTAssertEqual(result, [], "Empty array should remain empty")
    }
    
    func testEscapeHtmlInStringArray_WithNoEscapeEnvVar_ShouldReturnOriginal() {
        // Arrange
        setenv("NO_ESCAPE_HTML", "true", 1)
        let input = ["<div>test1</div>", "<p>test2</p>"]
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlInStringArray(input)
        
        // Assert
        XCTAssertEqual(result, input, "Should return original when NO_ESCAPE_HTML is true")
    }
    
    // MARK: - Mock API Model Tests
    
    func testHtmlEscapableProtocol_MockAutoTestModel() {
        // Arrange
        var mockModel = MockAutoTestModel(
            name: "<script>Test Name</script>",
            description: "<div>Test Description</div>",
            steps: ["<p>Step 1</p>", "Normal step", "<b>Step 3</b>"]
        )
        
        // Act
        mockModel.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(mockModel.name, "\\<script>Test Name\\</script>")
        XCTAssertEqual(mockModel.description, "\\<div>Test Description\\</div>")
        XCTAssertEqual(mockModel.steps, ["\\<p>Step 1\\</p>", "Normal step", "\\<b>Step 3\\</b>"])
    }
    
    // MARK: - Real API Model Tests
    
    func testRealApiModel_AutoTestPostModel_EscapeHtmlProperties() {
        // Arrange
        let projectId = UUID()
        var model = AutoTestPostModel(
            externalId: "test-external-id",
            projectId: projectId,
            name: "<script>Test Name</script>",
            namespace: "<div>Test Namespace</div>",
            classname: "<p>Test Class</p>",
            title: "<h1>Test Title</h1>",
            description: "<div>Test <b>Description</b> with HTML</div>",
            isFlaky: false,
            externalKey: "<span>External Key</span>"
        )
        
        // Add some steps with HTML
        model.steps = [
            AutoTestStepModel(
                title: "<h2>Step Title</h2>",
                description: "<p>Step description</p>",
                expected: "<div>Expected result</div>",
                testData: "<code>Test data</code>"
            )
        ]
        
        // Add labels with HTML
        model.labels = [
            LabelPostModel(name: "<label>Label Name</label>", value: "<value>Label Value</value>")
        ]
        
        // Add links with HTML
        model.links = [
            LinkPostModel(
                title: "<title>Link Title</title>",
                description: "<desc>Link Description</desc>",
                url: "https://example.com",
                type: LinkType.defect
            )
        ]
        
        // Act
        model.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(model.name, "\\<script>Test Name\\</script>")
        XCTAssertEqual(model.namespace, "\\<div>Test Namespace\\</div>")
        XCTAssertEqual(model.classname, "\\<p>Test Class\\</p>")
        XCTAssertEqual(model.title, "\\<h1>Test Title\\</h1>")
        XCTAssertEqual(model.description, "\\<div>Test \\<b>Description\\</b> with HTML\\</div>")
        XCTAssertEqual(model.externalKey, "\\<span>External Key\\</span>")
        
        // Check steps
        XCTAssertEqual(model.steps?[0].title, "\\<h2>Step Title\\</h2>")
        XCTAssertEqual(model.steps?[0].description, "\\<p>Step description\\</p>")
        XCTAssertEqual(model.steps?[0].expected, "\\<div>Expected result\\</div>")
        XCTAssertEqual(model.steps?[0].testData, "\\<code>Test data\\</code>")
        
        // Check labels
        XCTAssertEqual(model.labels?[0].name, "\\<label>Label Name\\</label>")
        XCTAssertEqual(model.labels?[0].value, "\\<value>Label Value\\</value>")
        
        // Check links (URL should not be escaped)
        XCTAssertEqual(model.links?[0].title, "\\<title>Link Title\\</title>")
        XCTAssertEqual(model.links?[0].description, "\\<desc>Link Description\\</desc>")
        XCTAssertEqual(model.links?[0].url, "https://example.com") // URL should remain unchanged
    }
    
    func testRealApiModel_AutoTestResultsForTestRunModel_EscapeHtmlProperties() {
        // Arrange
        let configurationId = UUID()
        let autoTestId = UUID()
        
        var model = AutoTestResultsForTestRunModel(
            configurationId: configurationId,
            autoTestExternalId: "test-external-id",
            outcome: .passed,
            message: "<div>Test message with <b>HTML</b></div>",
            trace: "<pre>Stack trace with <code>HTML</code></pre>"
        )
        
        // Add step results with HTML
        model.stepResults = [
            StepResult(
                title: "<h3>Step Title</h3>",
                description: "<p>Step description</p>",
                info: "<info>Additional info</info>",
                outcome: .passed,
                duration: 1000,
                parameters: ["<param>Parameter 1</param>", "Normal parameter"]
            )
        ]
        
        // Add setup results
        model.setupResults = [
            FixtureResult(outcome: .passed, duration: 500)
        ]
        
        // Add teardown results
        model.teardownResults = [
            FixtureResult(outcome: .passed, duration: 300)
        ]
        
        // Act
        model.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(model.message, "\\<div>Test message with \\<b>HTML\\</b>\\</div>")
        XCTAssertEqual(model.trace, "\\<pre>Stack trace with \\<code>HTML\\</code>\\</pre>")
        
        // Check step results
        XCTAssertEqual(model.stepResults?[0].title, "\\<h3>Step Title\\</h3>")
        XCTAssertEqual(model.stepResults?[0].description, "\\<p>Step description\\</p>")
        XCTAssertEqual(model.stepResults?[0].info, "\\<info>Additional info\\</info>")
        XCTAssertEqual(model.stepResults?[0].parameters, ["\\<param>Parameter 1\\</param>", "Normal parameter"])
    }
    
    func testRealApiModel_TestResultUpdateV2Request_EscapeHtmlProperties() {
        // Arrange
        var model = TestResultUpdateV2Request(
            comment: "<div>Test comment with <i>HTML</i> tags</div>"
        )
        
        // Add step results
        model.stepResults = [
            AttachmentPutModelAutoTestStepResultsModel(
                title: "<title>Step Title</title>",
                description: "<desc>Step Description</desc>",
                info: "<info>Step Info</info>",
                outcome: .passed,
                duration: 1000,
                parameters: ["<param1>Value1</param1>", "Normal value"]
            )
        ]
        
        // Act
        model.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(model.comment, "\\<div>Test comment with \\<i>HTML\\</i> tags\\</div>")
        
        // Check step results
        XCTAssertEqual(model.stepResults?[0].title, "\\<title>Step Title\\</title>")
        XCTAssertEqual(model.stepResults?[0].description, "\\<desc>Step Description\\</desc>")
        XCTAssertEqual(model.stepResults?[0].info, "\\<info>Step Info\\</info>")
        XCTAssertEqual(model.stepResults?[0].parameters, ["\\<param1>Value1\\</param1>", "Normal value"])
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceEscapeHtmlTags_LargeString() {
        // Arrange
        let input = String(repeating: "<div>test content</div>", count: 1000)
        
        // Act & Assert
        measure {
            _ = HtmlEscapeUtils.escapeHtmlTags(input)
        }
    }
    
    func testPerformanceEscapeHtmlInStringArray_LargeArray() {
        // Arrange
        let input = Array(repeating: "<div>test content</div>", count: 1000)
        
        // Act & Assert
        measure {
            _ = HtmlEscapeUtils.escapeHtmlInStringArray(input)
        }
    }
    
    func testPerformanceRealApiModel_LargeDataSet() {
        // Arrange
        let projectId = UUID()
        var models: [AutoTestPostModel] = []
        
        for i in 0..<100 {
            var model = AutoTestPostModel(
                externalId: "test-\(i)",
                projectId: projectId,
                name: "<script>Test \(i)</script>",
                namespace: "<div>Namespace \(i)</div>",
                classname: "<p>Class \(i)</p>",
                title: "<h1>Title \(i)</h1>",
                description: "<div>Description \(i) with <b>HTML</b></div>"
            )
            
            model.steps = [
                AutoTestStepModel(
                    title: "<h2>Step \(i)</h2>",
                    description: "<p>Description \(i)</p>",
                    expected: "<div>Expected \(i)</div>",
                    testData: "<code>Data \(i)</code>"
                )
            ]
            
            models.append(model)
        }
        
        // Act & Assert
        measure {
            for var model in models {
                model.escapeHtmlProperties()
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testEscapeHtmlTags_WithSpecialCharacters() {
        // Arrange
        let input = "<div>Test with special chars: ñáéíóú & symbols!</div>"
        let expected = "\\<div>Test with special chars: ñáéíóú & symbols!\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should handle special characters correctly")
    }
    
    func testEscapeHtmlTags_WithNestedQuotes() {
        // Arrange
        let input = "<div class=\"container 'inner'\">Content</div>"
        let expected = "\\<div class=\"container 'inner'\">Content\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should handle nested quotes correctly")
    }
    
    func testEscapeHtmlTags_WithMalformedHtml() {
        // Arrange
        let input = "<div><p>Unclosed tag and <script malformed"
        let expected = "\\<div>\\<p>Unclosed tag and \\<script malformed"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should handle malformed HTML correctly")
    }
    
    func testEscapeHtmlTags_WithXmlTags() {
        // Arrange
        let input = "<?xml version=\"1.0\"?><root><item>test</item></root>"
        let expected = "\\<?xml version=\"1.0\"?>\\<root>\\<item>test\\</item>\\</root>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should escape XML tags as well")
    }
    
    func testEscapeHtmlTags_WithComments() {
        // Arrange
        let input = "<!-- This is a comment --><div>content</div>"
        let expected = "\\<!-- This is a comment -->\\<div>content\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should escape HTML comments")
    }
    
    func testEscapeHtmlTags_WithUnicodeCharacters() {
        // Arrange
        let input = "<div>Unicode: 🚀 💻 ⚡ テスト</div>"
        let expected = "\\<div>Unicode: 🚀 💻 ⚡ テスト\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should handle Unicode characters correctly")
    }
    
    func testEscapeHtmlTags_WithNewlinesAndTabs() {
        // Arrange
        let input = "<div>\n\tContent with\n\ttabs and newlines\n</div>"
        let expected = "\\<div>\n\tContent with\n\ttabs and newlines\n\\</div>"
        
        // Act
        let result = HtmlEscapeUtils.escapeHtmlTags(input)
        
        // Assert
        XCTAssertEqual(result, expected, "Should handle newlines and tabs correctly")
    }
    
    // MARK: - Regex Pattern Tests
    
    func testHtmlDetectionRegex_VariousFormats() {
        let testCases = [
            ("<div>", true),
            ("<div/>", true),
            ("<div />", true),
            ("<div class=\"test\">", true),
            ("< div>", false), // Space after < should not match
            ("<>", false), // Empty tag should not match
            ("<<div>", true), // Should match the valid part
            ("text < div", false), // No valid HTML tag
            ("<script>", true),
            ("</script>", true),
            ("<!-- comment -->", true)
        ]
        
        for (input, shouldMatch) in testCases {
            let result = HtmlEscapeUtils.escapeHtmlTags(input)
            
            if shouldMatch {
                XCTAssertNotEqual(result, input, "'\(input)' should be detected as containing HTML and escaped")
            } else {
                XCTAssertEqual(result, input, "'\(input)' should NOT be detected as containing HTML")
            }
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testThreadSafety_ConcurrentEscaping() {
        let expectation = XCTestExpectation(description: "Concurrent escaping should be thread-safe")
        expectation.expectedFulfillmentCount = 10
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()
        
        for i in 0..<10 {
            group.enter()
            queue.async {
                let input = "<div>Test \(i) with <script>HTML</script></div>"
                let expected = "\\<div>Test \(i) with \\<script>HTML\\</script>\\</div>"
                
                let result = HtmlEscapeUtils.escapeHtmlTags(input)
                XCTAssertEqual(result, expected, "Thread \(i) should escape correctly")
                
                expectation.fulfill()
                group.leave()
            }
        }
        
        group.wait()
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Mock Models for Testing

struct MockAutoTestModel: HtmlEscapable {
    var name: String
    var description: String?
    var steps: [String]
    
    mutating func escapeHtmlProperties() {
        self.name = HtmlEscapeUtils.escapeHtmlTags(self.name) ?? self.name
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.steps = HtmlEscapeUtils.escapeHtmlInStringArray(self.steps) ?? self.steps
    }
}

struct MockStepModel: HtmlEscapable {
    var title: String?
    var description: String?
    var expected: String?
    
    mutating func escapeHtmlProperties() {
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.expected = HtmlEscapeUtils.escapeHtmlTags(self.expected)
    }
}

// MARK: - Integration Tests

extension HtmlEscapeUtilsTests {
    
    func testIntegration_CompleteWorkflow() {
        // Arrange - Simulate real-world API model data
        var mockModel = MockAutoTestModel(
            name: "<script>alert('XSS')</script> Test Case",
            description: "<div>This is a <b>test</b> description with <i>HTML</i> tags</div>",
            steps: [
                "<p>First step with HTML</p>",
                "Normal step without HTML",
                "<ul><li>List item 1</li><li>List item 2</li></ul>"
            ]
        )
        
        // Act
        mockModel.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(
            mockModel.name,
            "\\<script>alert('XSS')\\</script> Test Case",
            "Name should be properly escaped"
        )
        
        XCTAssertEqual(
            mockModel.description,
            "\\<div>This is a \\<b>test\\</b> description with \\<i>HTML\\</i> tags\\</div>",
            "Description should be properly escaped"
        )
        
        let expectedSteps = [
            "\\<p>First step with HTML\\</p>",
            "Normal step without HTML",
            "\\<ul>\\<li>List item 1\\</li>\\<li>List item 2\\</li>\\</ul>"
        ]
        XCTAssertEqual(mockModel.steps, expectedSteps, "All steps should be properly escaped")
    }
    
    func testIntegration_WithEnvironmentVariableDisabled() {
        // Arrange
        setenv("NO_ESCAPE_HTML", "true", 1)
        
        var mockModel = MockAutoTestModel(
            name: "<script>Test</script>",
            description: "<div>Description</div>",
            steps: ["<p>Step</p>"]
        )
        
        let originalModel = mockModel
        
        // Act
        mockModel.escapeHtmlProperties()
        
        // Assert - Should remain unchanged
        XCTAssertEqual(mockModel.name, originalModel.name)
        XCTAssertEqual(mockModel.description, originalModel.description)
        XCTAssertEqual(mockModel.steps, originalModel.steps)
    }
    
    func testIntegration_RealApiWorkflow() {
        // Arrange - Test the complete workflow with real API models
        let projectId = UUID()
        var autoTestModel = AutoTestPostModel(
            externalId: "integration-test",
            projectId: projectId,
            name: "<script>Integration Test</script>",
            description: "<div>Integration test with <b>HTML</b></div>"
        )
        
        var resultModel = AutoTestResultsForTestRunModel(
            configurationId: UUID(),
            autoTestExternalId: "integration-test",
            outcome: .passed,
            message: "<p>Test passed with <em>success</em></p>",
            trace: "<pre>No errors</pre>"
        )
        
        var updateModel = TestResultUpdateV2Request(
            comment: "<div>Updated comment with <strong>HTML</strong></div>"
        )
        
        // Act
        autoTestModel.escapeHtmlProperties()
        resultModel.escapeHtmlProperties()
        updateModel.escapeHtmlProperties()
        
        // Assert
        XCTAssertEqual(autoTestModel.name, "\\<script>Integration Test\\</script>")
        XCTAssertEqual(autoTestModel.description, "\\<div>Integration test with \\<b>HTML\\</b>\\</div>")
        
        XCTAssertEqual(resultModel.message, "\\<p>Test passed with \\<em>success\\</em>\\</p>")
        XCTAssertEqual(resultModel.trace, "\\<pre>No errors\\</pre>")
        
        XCTAssertEqual(updateModel.comment, "\\<div>Updated comment with \\<strong>HTML\\</strong>\\</div>")
    }
} 