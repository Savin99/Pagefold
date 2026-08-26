import SwiftUI
import SwiftData

@main
struct PagefoldApp: App {
    var body: some Scene {
        WindowGroup {
            FoldersView()
                .tint(Theme.accent)
        }
        // Undo включён: системный жест «встряхнуть для отмены» работает в полях ввода
        .modelContainer(for: [Folder.self, Card.self, CardImage.self], isUndoEnabled: true)
    }
}
