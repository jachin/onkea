//
//  YouGoHugoApp.swift
//  YouGoHugo
//
//  Created by Jachin Rupe on 3/20/26.
//

import SwiftUI
import SwiftData

@main
struct YouGoHugoApp: App {
    @StateObject private var sidebarNavigation = SidebarNavigationModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sidebarNavigation)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            SidebarTabCommands(navigationModel: sidebarNavigation)
        }

        Settings {
            PreferencesView()
        }
        .modelContainer(sharedModelContainer)
    }
}
