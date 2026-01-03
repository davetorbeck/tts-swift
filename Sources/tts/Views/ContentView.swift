import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedItem: SidebarItem? = .voices
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(selectedItem: $selectedItem)
                    .environmentObject(state)
                    .frame(width: 180)

                Divider()
            }

            ZStack(alignment: .bottomLeading) {
                detailView
                    .environmentObject(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sidebarVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if state.isSettingUp {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(state.setupState.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(state.setupState == .ready ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(state.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .voices:
            MainContentView()
        case .settings:
            SettingsDetailView()
        case nil:
            MainContentView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
