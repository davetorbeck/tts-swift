import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case voices = "Voices"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .voices: return "waveform"
        case .settings: return "gear"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedItem: SidebarItem?

    var body: some View {
        List(SidebarItem.allCases, selection: $selectedItem) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
    }
}
