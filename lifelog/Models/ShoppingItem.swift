import Foundation

/// 日付をまたいで残る買い物リスト。仕様は docs/requirements.md の買い物リストを参照。
struct ShoppingItem: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var quantity: String
    var note: String
    var placeID: UUID?
    var createdAt: Date

    init(id: UUID = UUID(),
         title: String,
         quantity: String = "",
         note: String = "",
         placeID: UUID? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.quantity = quantity
        self.note = note
        self.placeID = placeID
        self.createdAt = createdAt
    }
}
