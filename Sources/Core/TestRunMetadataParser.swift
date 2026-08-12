import Foundation
import AdaptersApi
import os.log

struct TestRunLinkConfig: Codable, Equatable {
    var url: String
    var title: String?
    var description: String?
    var type: String?
}

enum TestRunMetadataParser {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TestItAdapter",
        category: "TestRunMetadataParser"
    )

    static func parseTags(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.lowercased() != "null"
        else {
            return []
        }

        if raw.hasPrefix("[") {
            guard let data = raw.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data)
            else {
                logger.warning("Invalid JSON for testRunTags: \(raw)")
                return []
            }
            return array
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseLinks(_ raw: String?) -> [TestRunLinkConfig] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw.lowercased() != "null"
        else {
            return []
        }

        guard let data = raw.data(using: .utf8) else {
            logger.warning("Invalid encoding for testRunLinks")
            return []
        }

        do {
            let links = try JSONDecoder().decode([TestRunLinkConfig].self, from: data)
            let valid = links.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if valid.count != links.count {
                logger.warning("Some testRunLinks entries were skipped due to empty url")
            }
            return valid.map {
                TestRunLinkConfig(
                    url: $0.url.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: $0.title,
                    description: $0.description,
                    type: $0.type
                )
            }
        } catch {
            logger.warning("Invalid JSON for testRunLinks: \(error.localizedDescription)")
            return []
        }
    }

    static func toCreateLinkApiModels(_ links: [TestRunLinkConfig]) -> [CreateLinkApiModel] {
        links.map {
            CreateLinkApiModel(
                title: $0.title,
                url: $0.url,
                description: $0.description,
                type: AdaptersApi.LinkType(rawValue: $0.type ?? "") ?? .related
            )
        }
    }

    static func toUpdateLinkApiModels(_ links: [TestRunLinkConfig]) -> [UpdateLinkApiModel] {
        links.map {
            UpdateLinkApiModel(
                id: nil,
                title: $0.title,
                url: $0.url,
                description: $0.description,
                type: AdaptersApi.LinkType(rawValue: $0.type ?? "") ?? .related
            )
        }
    }

    static func mergeTags(existing: [String], incoming: [String]) -> [String] {
        var result = existing
        for tag in incoming where !result.contains(tag) {
            result.append(tag)
        }
        return result
    }

    static func mergeLinks(existing: [UpdateLinkApiModel], incoming: [UpdateLinkApiModel]) -> [UpdateLinkApiModel] {
        var result = existing
        let existingUrls = Set(existing.map(\.url))
        for link in incoming where !existingUrls.contains(link.url) {
            result.append(link)
        }
        return result
    }
}
