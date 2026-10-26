import SwiftUI

struct LetterPhotoCarousel: View {
    let images: [UIImage]
    @Binding var selectedIndex: Int
    let accentColor: Color
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundColor(accentColor)
                Text("添付写真")
                    .font(.headline)
                Spacer()
                Text("\(images.count)枚")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            TabView(selection: $selectedIndex) {
                ForEach(images.indices, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .tag(index)
                        .onTapGesture(perform: onExpand)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 220)
        }
    }
}
