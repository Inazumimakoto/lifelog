import SwiftUI

/// Common paging and dismissal chrome for letter photos, including missing-photo pages.
struct FullscreenPhotoGallery<Page: View>: View {
    let photoCount: Int
    @Binding private var selectedIndex: Int
    let showsPageCount: Bool
    let onClose: () -> Void
    private let page: (Int) -> Page

    init(photoCount: Int,
         selectedIndex: Binding<Int>,
         showsPageCount: Bool = true,
         onClose: @escaping () -> Void,
         @ViewBuilder page: @escaping (Int) -> Page) {
        self.photoCount = photoCount
        _selectedIndex = selectedIndex
        self.showsPageCount = showsPageCount
        self.onClose = onClose
        self.page = page
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(0..<photoCount, id: \.self) { index in
                    page(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()

                if showsPageCount {
                    Text("\(selectedIndex + 1) / \(photoCount)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }
}
