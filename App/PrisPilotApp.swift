//
//  PrisPilotApp.swift
//  PrisPilot
//
//  Created by Joshua James O’Connor on 20/08/2026.
//

import SwiftData
import SwiftUI

@main
struct PrisPilotApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: AppSnapshotRecord.self)
            AppStore.shared.configurePersistence(container: modelContainer)
        } catch {
            fatalError("Failed to create SwiftData container: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppStore.shared)
        }
        .modelContainer(modelContainer)
    }
}
