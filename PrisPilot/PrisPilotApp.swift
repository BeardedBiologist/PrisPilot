//
//  PrisPilotApp.swift
//  PrisPilot
//
//  Created by Joshua James O’Connor on 20/08/2026.
//

import SwiftUI

@main
struct PrisPilotApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppStore.shared)
        }
    }
}
