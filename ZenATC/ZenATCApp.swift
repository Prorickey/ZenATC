//
//  ZenATCApp.swift
//  ZenATC
//

import SwiftUI
import CoreGraphics
import CoreText

@main
struct ZenATCApp: App {
    @State private var purchaseManager = PurchaseManager()

    init() {
        FontLoader.registerAll()
        UIPickerView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView(purchaseManager: purchaseManager)
        }
    }
}

enum FontLoader {
    static func registerAll() {
        registerFont(assetName: "ABCSchengenCoreVariable-Trial", fileName: "ABCSchengenCoreVariable-Trial")
        registerFont(assetName: "ABCGravityCyrillicUprightVariable-Trial", fileName: "ABCGravityCyrillicUprightVariable-Trial")
        registerFont(assetName: "GT-Standard-Trial-VF", fileName: "GT-Standard-Trial-VF")
    }

    private static func registerFont(assetName: String, fileName: String) {
        if let asset = NSDataAsset(name: assetName),
           let provider = CGDataProvider(data: asset.data as CFData),
           let font = CGFont(provider) {
            CTFontManagerRegisterGraphicsFont(font, nil)
            #if DEBUG
            print("[Font] Registered asset: \(font.postScriptName as String? ?? "unknown")")
            #endif
            return
        }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Fonts"),
              let provider = CGDataProvider(url: url as CFURL),
              let font = CGFont(provider) else {
            return
        }

        CTFontManagerRegisterGraphicsFont(font, nil)
        #if DEBUG
        print("[Font] Registered bundle: \(font.postScriptName as String? ?? "unknown")")
        #endif
    }
}
