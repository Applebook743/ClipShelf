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
    var isPinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case text
        case filePaths
        case imageData
        case sourcePath
        case createdAt
        case isPinned
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        text: String? = nil,
        filePaths: [String] = [],
        imageData: Data? = nil,
        sourcePath: String? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.filePaths = filePaths
        self.imageData = imageData
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        filePaths = try container.decode([String].self, forKey: .filePaths)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}
