import Foundation

/// 購入先名はユーザー作成コンテンツとして保存し、翻訳しない。
struct ShoppingPlace: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var orderIndex: Int

    init(id: UUID = UUID(), name: String, orderIndex: Int = 0) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
    }
}
