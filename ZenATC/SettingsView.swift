//
//  SettingsView.swift
//  ZenATC
//

import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showSettings = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(themeManager.theme.foreground)
                            .frame(width: 36, height: 36)
                            .background(themeManager.theme.foreground.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                Text("Settings")
                    .font(.gtStandard(size: 28))
                    .fontWeight(.semibold)
                    .foregroundStyle(themeManager.theme.foreground.opacity(0.3))

                Spacer()
            }
        }
    }
}

#Preview {
    @Previewable @State var show = true
    SettingsView(showSettings: $show)
        .environment(ThemeManager())
}
