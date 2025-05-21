import Foundation

/**
 * The marker protocol for model objects with attachments.
 */
protocol ResultWithAttachments {
    /**
     * Gets attachments.
     *
     * @return the attachments
     */
    func getAttachments() -> [String]
} 