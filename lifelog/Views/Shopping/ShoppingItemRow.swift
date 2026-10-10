import SwiftUI

/// The entire row toggles purchase state; editing stays in the trailing menu.
struct ShoppingItemRow: View {
    let item: ShoppingItem
    let isChecked: Bool
    let placeName: String?
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 12) {
                    AnimatedCheckmark(isCompleted: isChecked,
                                      color: .accentColor,
                                      size: 24,
                                      providesHapticFeedback: false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title)
                            .font(.body)
                            .strikethrough(isChecked)
                            .foregroundStyle(isChecked ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        if !item.quantity.isEmpty || placeName != nil {
                            HStack(spacing: 8) {
                                if !item.quantity.isEmpty {
                                    Text(verbatim: item.quantity)
                                }
                                if let placeName {
                                    Text(verbatim: placeName)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !item.note.isEmpty {
                            Text(verbatim: item.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                // Include the cell's leading and vertical margins in its purchase target.
                .padding(.leading, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: item.title)
                                + Text(verbatim: ", ")
                                + (isChecked ? Text("購入を取り消す") : Text("購入済みにする")))
            .accessibilityValue(Text(verbatim: [item.quantity, placeName ?? "", item.note]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")))
            .accessibilityAddTraits(isChecked ? .isSelected : [])
            .accessibilityIdentifier("shopping.toggle.\(item.id.uuidString)")

            Menu {
                Button("商品を編集", systemImage: "pencil", action: onEdit)
                Button("削除", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 16)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("商品の操作"))
            .disabled(isChecked)
        }
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets())
    }
}
