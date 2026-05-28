//
//  AirportsListView.swift
//  ZenATC
//

import SwiftUI

struct AirportsListView: View {
    @Binding var showAirports: Bool
    @Binding var currentAirportIndex: Int
    @Binding var showUpgrade: Bool
    @Environment(ThemeManager.self) private var themeManager

    private let freeAirports = Airport.all.filter { !$0.isPro }
    private let proAirports  = Airport.all.filter {  $0.isPro }

    var body: some View {
        ZStack(alignment: .top) {
            themeManager.theme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(alignment: .center) {
                        Text("All Airports")
                            .font(.gtStandard(size: 32))
                            .fontWeight(.heavy)
                            .foregroundStyle(themeManager.theme.foreground)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                showAirports = false
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(themeManager.theme.foreground.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(themeManager.theme.foreground)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    // Free airports
                    AirportDivider()
                    ForEach(freeAirports) { airport in
                        AirportRow(airport: airport) {
                            if let idx = Airport.all.firstIndex(where: { $0.id == airport.id }) {
                                currentAirportIndex = idx
                            }
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                showAirports = false
                            }
                        }
                        AirportDivider()
                    }

                    // PRO section divider
                    ProSectionRow {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            showAirports = false
                            showUpgrade = true
                        }
                    }
                    AirportDivider()

                    // Pro airports
                    ForEach(proAirports) { airport in
                        AirportRow(airport: airport, dimmed: true, action: {})
                        AirportDivider()
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Airport Row

private struct AirportRow: View {
    let airport: Airport
    var dimmed: Bool = false
    let action: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                Text(airport.code.uppercased())
                    .font(.airportCode(size: 60, width: 80))
                    .foregroundStyle(themeManager.theme.foreground.opacity(dimmed ? 0.38 : 1.0))
                    .lineLimit(1)

                Spacer()

                Text(airport.city)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(themeManager.theme.foreground.opacity(dimmed ? 0.38 : 0.82))
            }
            .padding(.horizontal, 20)
            .frame(height: 84)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
    }
}

// MARK: - PRO Section Row

private struct ProSectionRow: View {
    let onUpgrade: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            Text("Included in")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(themeManager.theme.foreground.opacity(0.65))

            Text("PRO")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(themeManager.theme.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(themeManager.theme.foreground)
                .clipShape(Capsule())

            Spacer()

            Button(action: onUpgrade) {
                HStack(spacing: 5) {
                    Text("Upgrade")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(themeManager.theme.background)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(themeManager.theme.foreground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
    }
}

#Preview {
    AirportsListView(
        showAirports: .constant(true),
        currentAirportIndex: .constant(0),
        showUpgrade: .constant(false)
    )
    .environment(ThemeManager())
}

// MARK: - Dashed Divider

private struct AirportDivider: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(
                themeManager.theme.foreground.opacity(0.28),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5, 4])
            )
        }
        .frame(height: 1)
    }
}
