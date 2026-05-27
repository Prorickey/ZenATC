//
//  Theme.swift
//  ZenATC
//

import SwiftUI

// MARK: - App Theme

struct AppTheme {
    let background: Color
    let foreground: Color

    static let all: [AppTheme] = [
        // Default
        AppTheme(
            background: Color(red: 177 / 255, green: 216 / 255, blue: 185 / 255),
            foreground: Color(red: 224 / 255, green: 76 / 255, blue: 38 / 255)
        ),
        // Midnight purple
        AppTheme(
            background: Color(hex: "0F3E37"),
            foreground: Color(hex: "C958C5")
        ),
        // Olive green
        AppTheme(
            background: Color(hex: "8FA417"),
            foreground: Color(hex: "1F5412")
        ),
        // Teal
        AppTheme(
            background: Color(hex: "0F8D94"),
            foreground: Color(hex: "312000")
        ),
        // Sage + dark green
        AppTheme(
            background: Color(hex: "B1D8B9"),
            foreground: Color(hex: "256516")
        ),
        // Sand + magenta
        AppTheme(
            background: Color(hex: "D4C996"),
            foreground: Color(hex: "D24BCD")
        ),
    ]
}

@Observable
final class ThemeManager {
    private(set) var currentIndex = 0

    var theme: AppTheme { AppTheme.all[currentIndex] }

    func cycleTheme() {
        currentIndex = (currentIndex + 1) % AppTheme.all.count
    }

    func setTheme(_ index: Int) {
        guard index >= 0 && index < AppTheme.all.count else { return }
        currentIndex = index
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}

// MARK: - Fonts

extension UIFont {
    static func gtStandardAirport(size: CGFloat) -> UIFont {
        UIFont(name: "GTStandardTrialVF-LCompressedBlack", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .black)
    }
}

extension Font {
    static func gtStandard(size: CGFloat) -> Font {
        Font.custom("GT-Standard-Trial-VF", size: size)
    }

    static func gtStandardAirport(size: CGFloat) -> Font {
        Font(UIFont.gtStandardAirport(size: size))
    }

    static func schengenCore(size: CGFloat) -> Font {
        Font.custom("ABCSchengenCoreVariable-Trial", size: size)
    }
}
