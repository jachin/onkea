//
//  OnekaApp.swift
//  Oneka
//
//  Created by Jachin Rupe on 3/20/26.
//

import SwiftUI

@main
struct OnekaApp: App {
    @StateObject private var sidebarNavigation = SidebarNavigationModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sidebarNavigation)
        }
        .commands {
            OpenSiteCommands()
            SidebarTabCommands(navigationModel: sidebarNavigation)
            InsertImageCommands(navigationModel: sidebarNavigation)
        }

        Settings {
            PreferencesView()
        }
    }
}
