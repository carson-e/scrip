import ScripCore
import ScripWeb
import SwiftUI

@MainActor
final class AppRuntime: ObservableObject {
    let store: UsageStore
    let sessions: [ProviderID: ProviderWebSession]

    init() {
        let sessions = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { id in
            (id, ProviderWebSession(provider: id))
        })
        self.sessions = sessions
        self.store = UsageStore(fetchers: sessions)
        for session in sessions.values {
            OffscreenWebHost.shared.embed(session.webView)
        }
    }

    func session(for id: ProviderID) -> ProviderWebSession {
        sessions[id]!
    }
}

@main
struct ScripApp: App {
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(runtime.store)
                .environmentObject(runtime)
        } label: {
            MenuBarLabel(store: runtime.store)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "login", for: ProviderID.self) { $id in
            if let id {
                LoginView(providerID: id)
                    .environmentObject(runtime.store)
                    .environmentObject(runtime)
                    .frame(minWidth: 760, minHeight: 560)
            }
        }
        .defaultSize(width: 920, height: 720)
    }
}
