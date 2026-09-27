//
//  ResoluxMacApp.swift
//  ResoluxMac
//
//  Created by Luiz Neto on 27/09/26.
//

import SwiftUI

@main
struct ResoluxMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 700)
        #if os(macOS)
        // Barra de titulo fora: e a aurora que chega ate o topo, com os
        // semaforos flutuando por cima dela -- mesmo truque do Mevolit.
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
