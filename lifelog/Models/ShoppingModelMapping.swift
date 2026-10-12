import Foundation

// Keep app-only domain types out of SwiftDataModels.swift, which is shared with widgets.
extension ShoppingItem {
    init(sd: SDShoppingItem) {
        self.init(id: sd.id,
                  title: sd.title,
                  note: sd.note,
                  placeID: sd.placeID,
                  createdAt: sd.createdAt)
    }
}

extension SDShoppingItem {
    convenience init(domain: ShoppingItem) {
        self.init(id: domain.id,
                  title: domain.title,
                  note: domain.note,
                  placeID: domain.placeID,
                  createdAt: domain.createdAt)
    }

    func update(from item: ShoppingItem) {
        title = item.title
        note = item.note
        placeID = item.placeID
        createdAt = item.createdAt
    }
}

extension ShoppingPlace {
    init(sd: SDShoppingPlace) {
        self.init(id: sd.id, name: sd.name, orderIndex: sd.orderIndex)
    }
}
