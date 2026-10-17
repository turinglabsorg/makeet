import SwiftData
import SwiftUI

struct ArchiveHost<Content: View>: View {
    let container: ModelContainer
    @ViewBuilder let content: () -> Content

    var body: some View {
        ArchiveContent(container: container, content: content())
            .id(ObjectIdentifier(container))
    }
}

private struct ArchiveContent<Content: View>: View {
    @State private var container: ModelContainer
    let content: Content

    init(container: ModelContainer, content: Content) {
        _container = State(initialValue: container)
        self.content = content
    }

    var body: some View {
        content.modelContainer(container)
    }
}
