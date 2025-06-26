import Foundation

/// HTML escape utility for preventing XSS attacks
/// Escapes HTML tags in strings and objects
public class HtmlEscapeUtils {
    
    private static let NO_ESCAPE_HTML_ENV_VAR = "NO_ESCAPE_HTML"
    
    // Regex pattern to detect HTML tags
    private static let htmlTagPattern = try! NSRegularExpression(
        pattern: "<\\S.*?(?:>|\\/?>)",
        options: .caseInsensitive
    )
    
    // Regex patterns to escape only non-escaped characters
    private static let lessThanPattern = try! NSRegularExpression(
        pattern: "(?<!\\\\)<",
        options: []
    )
    
    private static let greaterThanPattern = try! NSRegularExpression(
        pattern: "(?<!\\\\)>",
        options: []
    )
    
    /// Escapes HTML tags to prevent XSS attacks.
    /// First checks if the string contains HTML tags using regex pattern.
    /// Only performs escaping if HTML tags are detected.
    /// Escapes all < as \\< and > as \\> only if they are not already escaped.
    /// Uses regex with negative lookbehind to avoid double escaping.
    /// - Parameter text: The text to escape
    /// - Returns: Escaped text or original text if escaping is disabled or no HTML tags found
    public static func escapeHtmlTags(_ text: String?) -> String? {
        guard let text = text else { return nil }
        
        // Check if escaping is disabled via environment variable
        if let noEscapeHtml = ProcessInfo.processInfo.environment[NO_ESCAPE_HTML_ENV_VAR],
           noEscapeHtml.lowercased() == "true" {
            return text
        }
        
        // First check if the string contains HTML tags
        let range = NSRange(location: 0, length: text.utf16.count)
        if htmlTagPattern.firstMatch(in: text, options: [], range: range) == nil {
            return text // No HTML tags found, return original string
        }
        
        // Use regex with negative lookbehind to escape only non-escaped characters
        let textRange = NSRange(location: 0, length: text.utf16.count)
        var result = lessThanPattern.stringByReplacingMatches(
            in: text,
            options: [],
            range: textRange,
            withTemplate: "\\\\<"
        )
        
        let resultRange = NSRange(location: 0, length: result.utf16.count)
        result = greaterThanPattern.stringByReplacingMatches(
            in: result,
            options: [],
            range: resultRange,
            withTemplate: "\\\\>"
        )
        
        return result
    }
    
    /// Escapes HTML tags in string arrays
    /// - Parameter array: Array of strings to process
    /// - Returns: Array with escaped strings
    public static func escapeHtmlInStringArray(_ array: [String]?) -> [String]? {
        guard let array = array else { return nil }
        
        // Check if escaping is disabled via environment variable
        if let noEscapeHtml = ProcessInfo.processInfo.environment[NO_ESCAPE_HTML_ENV_VAR],
           noEscapeHtml.lowercased() == "true" {
            return array
        }
        
        return array.map { escapeHtmlTags($0) ?? $0 }
    }
}

/// Protocol for objects that support HTML escaping
/// Objects implementing this protocol can have their string properties escaped
public protocol HtmlEscapable {
    mutating func escapeHtmlProperties()
}

// MARK: - API Model Extensions

import testit_api_client

// Extend API models to support HTML escaping
extension AutoTestPutModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.name = HtmlEscapeUtils.escapeHtmlTags(self.name) ?? self.name
        self.namespace = HtmlEscapeUtils.escapeHtmlTags(self.namespace)
        self.classname = HtmlEscapeUtils.escapeHtmlTags(self.classname)
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.externalKey = HtmlEscapeUtils.escapeHtmlTags(self.externalKey)
        
        // Handle steps array
        if var stepsArray = self.steps {
            for i in 0..<stepsArray.count {
                stepsArray[i].escapeHtmlProperties()
            }
            self.steps = stepsArray
        }
        
        // Handle setup array
        if var setupArray = self.setup {
            for i in 0..<setupArray.count {
                setupArray[i].escapeHtmlProperties()
            }
            self.setup = setupArray
        }
        
        // Handle teardown array
        if var teardownArray = self.teardown {
            for i in 0..<teardownArray.count {
                teardownArray[i].escapeHtmlProperties()
            }
            self.teardown = teardownArray
        }
        
        // Handle labels array
        if var labelsArray = self.labels {
            for i in 0..<labelsArray.count {
                labelsArray[i].escapeHtmlProperties()
            }
            self.labels = labelsArray
        }
        
        // Handle links array
        if var linksArray = self.links {
            for i in 0..<linksArray.count {
                linksArray[i].escapeHtmlProperties()
            }
            self.links = linksArray
        }
    }
}

extension AutoTestPostModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.name = HtmlEscapeUtils.escapeHtmlTags(self.name) ?? self.name
        self.namespace = HtmlEscapeUtils.escapeHtmlTags(self.namespace)
        self.classname = HtmlEscapeUtils.escapeHtmlTags(self.classname)
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.externalKey = HtmlEscapeUtils.escapeHtmlTags(self.externalKey)
        
        // Handle steps array
        if var stepsArray = self.steps {
            for i in 0..<stepsArray.count {
                stepsArray[i].escapeHtmlProperties()
            }
            self.steps = stepsArray
        }
        
        // Handle setup array
        if var setupArray = self.setup {
            for i in 0..<setupArray.count {
                setupArray[i].escapeHtmlProperties()
            }
            self.setup = setupArray
        }
        
        // Handle teardown array
        if var teardownArray = self.teardown {
            for i in 0..<teardownArray.count {
                teardownArray[i].escapeHtmlProperties()
            }
            self.teardown = teardownArray
        }
        
        // Handle labels array
        if var labelsArray = self.labels {
            for i in 0..<labelsArray.count {
                labelsArray[i].escapeHtmlProperties()
            }
            self.labels = labelsArray
        }
        
        // Handle links array
        if var linksArray = self.links {
            for i in 0..<linksArray.count {
                linksArray[i].escapeHtmlProperties()
            }
            self.links = linksArray
        }
    }
}

extension AutoTestStepModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.expected = HtmlEscapeUtils.escapeHtmlTags(self.expected)
        self.testData = HtmlEscapeUtils.escapeHtmlTags(self.testData)
        
        // Handle attachments array if present
        // Attachments usually contain file data, so we might not want to escape them
        // but if they have descriptive text fields, those should be escaped
    }
}

extension LabelPostModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.name = HtmlEscapeUtils.escapeHtmlTags(self.name) ?? self.name
        self.value = HtmlEscapeUtils.escapeHtmlTags(self.value) ?? self.value
    }
}

extension LinkPostModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        // URL field should not be escaped as it might break the URL
        // self.url = HtmlEscapeUtils.escapeHtmlTags(self.url)
    }
}

extension AutoTestResultsForTestRunModel: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.message = HtmlEscapeUtils.escapeHtmlTags(self.message)
        self.trace = HtmlEscapeUtils.escapeHtmlTags(self.trace)
        
        // Handle setup results
        if var setupResults = self.setupResults {
            for i in 0..<setupResults.count {
                setupResults[i].escapeHtmlProperties()
            }
            self.setupResults = setupResults
        }
        
        // Handle teardown results
        if var teardownResults = self.teardownResults {
            for i in 0..<teardownResults.count {
                teardownResults[i].escapeHtmlProperties()
            }
            self.teardownResults = teardownResults
        }
        
        // Handle step results
        if var stepResults = self.stepResults {
            for i in 0..<stepResults.count {
                stepResults[i].escapeHtmlProperties()
            }
            self.stepResults = stepResults
        }
        
        // Handle links
        if var links = self.links {
            for i in 0..<links.count {
                links[i].escapeHtmlProperties()
            }
            self.links = links
        }
    }
}

extension StepResult: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.title = HtmlEscapeUtils.escapeHtmlTags(self.title)
        self.description = HtmlEscapeUtils.escapeHtmlTags(self.description)
        self.info = HtmlEscapeUtils.escapeHtmlTags(self.info)
        
        // Handle parameters if they exist
        if let parameters = self.parameters {
            self.parameters = HtmlEscapeUtils.escapeHtmlInStringArray(parameters)
        }
    }
}

extension FixtureResult: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        // Escape string properties in FixtureResult if any exist
        // This depends on the actual structure of FixtureResult
    }
}

extension TestResultUpdateV2Request: HtmlEscapable {
    public mutating func escapeHtmlProperties() {
        self.comment = HtmlEscapeUtils.escapeHtmlTags(self.comment)
        
        // Handle step results
        if var stepResults = self.stepResults {
            for i in 0..<stepResults.count {
                stepResults[i].escapeHtmlProperties()
            }
            self.stepResults = stepResults
        }
        
        // Handle setup results
        if var setupResults = self.setupResults {
            for i in 0..<setupResults.count {
                setupResults[i].escapeHtmlProperties()
            }
            self.setupResults = setupResults
        }
        
        // Handle teardown results
        if var teardownResults = self.teardownResults {
            for i in 0..<teardownResults.count {
                teardownResults[i].escapeHtmlProperties()
            }
            self.teardownResults = teardownResults
        }
    }
} 