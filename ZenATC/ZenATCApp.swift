//
//  ZenATCApp.swift
//  ZenATC
//

import SwiftUI
import CoreGraphics
import CoreText
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct ZenATCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @State private var authManager = AuthManager()
    @State private var purchaseManager = PurchaseManager()

    init() {
        FontLoader.registerAll()
        UIPickerView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(purchaseManager)
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
