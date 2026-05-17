import Foundation

struct ClipItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case text
        case file
        case image
    }

    var id: UUID
    var kind: Kind
    var title: String
    var text: String?
    var filePaths: [String]
    var imageData: Data?
    var sourcePath: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        text: String? = nil,
        filePaths: [String] = [],
        imageData: Data? = nil,
        sourcePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.filePaths = filePaths
        self.imageData = imageData
        self.sourcePath = sourcePath
        self.createdAt = createdAt
    }
}
