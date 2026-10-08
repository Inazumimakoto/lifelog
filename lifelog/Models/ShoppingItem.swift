import Foundation

/// 日付をまたいで残る買い物リスト。仕様は docs/requirements.md の買い物リストを参照。
struct ShoppingItem: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var quantity: String
    var note: String
    var placeID: UUID?
    var createdAt: Date
    var purchasedAt: Date?
    var purchaseCount: Int
    var familyID: UUID?

    var isPurchased: Bool { purchasedAt != nil }
    /// Only explicit buy-again copies share purchase frequency; equal titles stay independent.
    var effectiveFamilyID: UUID { familyID ?? id }

    init(id: UUID = UUID(),
         title: String,
         quantity: String = "",
         note: String = "",
         placeID: UUID? = nil,
         createdAt: Date = Date(),
         purchasedAt: Date? = nil,
         purchaseCount: Int = 0,
         familyID: UUID? = nil) {
        self.id = id
        self.title = title
        self.quantity = quantity
        self.note = note
        self.placeID = placeID
        self.createdAt = createdAt
        self.purchasedAt = purchasedAt
        self.purchaseCount = purchaseCount
        self.familyID = familyID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, quantity, note, placeID, createdAt, purchasedAt, purchaseCount, familyID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        quantity = try values.decode(String.self, forKey: .quantity)
        note = try values.decode(String.self, forKey: .note)
        placeID = try values.decodeIfPresent(UUID.self, forKey: .placeID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        purchasedAt = try values.decodeIfPresent(Date.self, forKey: .purchasedAt)
        // Old exported or stored payloads did not include frequency or copy identity.
        purchaseCount = try values.decodeIfPresent(Int.self, forKey: .purchaseCount) ?? 0
        familyID = try values.decodeIfPresent(UUID.self, forKey: .familyID)
    }
}
