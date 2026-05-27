//
//  ZenATCApp.swift
//  ZenATC
//

import SwiftUI
import CoreGraphics
import CoreText
import FirebaseCore

@main
struct ZenATCApp: App {
    @State private var authManager: AuthManager
    @State private var purchaseManager: PurchaseManager

    init() {
        FirebaseApp.configure()
        _authManager = State(wrappedValue: AuthManager())
        _purchaseManager = State(wrappedValue: PurchaseManager())
        FontLoader.registerAll()
        UIPickerView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authManager: authManager, purchaseManager: purchaseManager)
        }
    }
}

enum FontLoader {
    static func registerAll() {
        load("ABCSchengenCoreVariable-Trial")
        load("GT-Standard-Trial-VF")
    }

    private static func load(_ assetName: String) {
        guard let asset = NSDataAsset(name: assetName),
              let provider = CGDataProvider(data: asset.data as CFData),
              let font = CGFont(provider) else {
            return
        }
        CTFontManagerRegisterGraphicsFont(font, nil)
        #if DEBUG
        print("[Font] Registered: \(font.postScriptName as String? ?? "unknown")")
        #endif
    }
}
