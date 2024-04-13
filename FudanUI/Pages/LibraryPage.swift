import SwiftUI
import FudanKit
import ViewUtils

struct LibraryPage: View {
    var body: some View {
        AsyncContentView { _ in
            return try await LibraryAPI.getLibrary()
        } content: { libraries in
            List {
                ForEach(libraries) { library in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(library.name)
                            Text(library.openTime)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center) {
                            CircularProgressView(value: library.current, total: library.capacity)
                            Text("\(String(library.current)) / \(String(library.capacity))")
                                .font(.footnote)
                        }
                        .frame(minWidth: 80) // for alignment
                    }
                }
            }
            .navigationTitle("Library Popularity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        LibraryPage()
    }
}
