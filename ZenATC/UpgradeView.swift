//
//  UpgradeView.swift
//  ZenATC
//

import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(ThemeManager.self) private var themeManager
    let authManager: AuthManager
    let purchaseManager: PurchaseManager
    @Binding var showUpgrade: Bool

    @State private var selectedPlan = 1 // 0 = monthly, 1 = annual
    @State private var showAuthPage = false

    private let accent = Color(red: 0.878, green: 0.298, blue: 0.149)
    private let bestValueGreen = Color(red: 0.694, green: 0.847, blue: 0.725)

    private let perks: [(title: String, subtitle: String)] = [
        ("5 PRO Audio packs",         "More moods and soundtracks"),
        ("Custom ATC radio filters",  "Make the ATC audio mellow or crisp"),
        ("50 more airports",          "Get 50 more of your favorite airports"),
    ]

    var body: some View {
        ZStack {
            themeManager.theme.background.ignoresSafeArea()

            GeometryReader { geo in
                HStack(spacing: 0) {
                    mainPage
                        .frame(width: geo.size.width)

                    authPage
                        .frame(width: geo.size.width)
                }
                .frame(width: geo.size.width * 2, alignment: .leading)
                .offset(x: showAuthPage ? -geo.size.width : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: showAuthPage)
            }
        }
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    perksSection
                        .padding(.top, 32)

                    plansSection
                        .padding(.top, 36)

                    upgradeButton
                        .padding(.top, 32)

                    finePrint
                        .padding(.top, 16)
                }
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Upgrade to PRO")
                .font(.system(size: 34.77, weight: .bold))
                .foregroundStyle(accent)

            Spacer()

            Button {
                showUpgrade = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42.24, height: 42.24)
                    .background(accent.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Perks

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(perks.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "plus.app.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(accent)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(perks[i].title)
                            .font(.system(size: 19.68, weight: .semibold))
                            .foregroundStyle(accent)

                        Text(perks[i].subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(accent.opacity(0.7))
                    }
                }
            }

            Text("+ 7 custom app colors, icons, and more")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 19)
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 12) {
            ForEach(purchaseManager.products.indices, id: \.self) { i in
                let product = purchaseManager.products[i]
                let isAnnual = product.subscription?.subscriptionPeriod.unit == .year
                let isSelected = selectedPlan == i

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedPlan = i
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(product.displayName)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(isSelected ? themeManager.theme.background : accent)

                                if isAnnual {
                                    Text("$3.50 / mo")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(isSelected ? bestValueGreen : accent.opacity(0.75))
                                } else {
                                    Text(product.displayPrice + " / mo")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(isSelected ? bestValueGreen : accent.opacity(0.75))
                                }
                            }

                            Spacer()

                            Text(product.displayPrice + (isAnnual ? " / yr" : " / mo"))
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(isSelected ? themeManager.theme.background : accent)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isSelected ? accent : accent.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(accent.opacity(isSelected ? 0 : 0.25), lineWidth: 1.5)
                        )

                        if isAnnual {
                            Text("Best Value")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(bestValueGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(accent, lineWidth: 1.5)
                                )
                                .padding(.top, -10)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 19)
    }

    // MARK: - Upgrade Button

    private var upgradeButton: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                showAuthPage = true
            }
        } label: {
            Text("Upgrade now")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.theme.background)
                .frame(width: 255, height: 76)
                .background(accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Fine Print

    private var finePrint: some View {
        VStack(spacing: 8) {
            Text("Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 12))
                .foregroundStyle(accent.opacity(0.55))
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Restore Purchases") {}
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent.opacity(0.7))

                Button("Terms of Service") {}
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent.opacity(0.7))

                Button("Privacy Policy") {}
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 19)
        .buttonStyle(.plain)
    }

    // MARK: - Auth Page

    private var authPage: some View {
        AuthFlowPage(
            themeManager: themeManager,
            authManager: authManager,
            purchaseManager: purchaseManager,
            preselectedPlanIndex: selectedPlan,
            onBack: {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    showAuthPage = false
                }
            },
            onDone: { showUpgrade = false }
        )
    }
}

// MARK: - Auth Flow Page

private struct AuthFlowPage: View {
    let themeManager: ThemeManager
    let authManager: AuthManager
    let purchaseManager: PurchaseManager
    var preselectedPlanIndex: Int = 1
    let onBack: () -> Void
    let onDone: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let accent = Color(red: 0.878, green: 0.298, blue: 0.149)

    private var bg: Color { themeManager.theme.background }
    private var fg: Color { themeManager.theme.foreground }

    private var selectedProduct: Product? {
        let idx = preselectedPlanIndex < purchaseManager.products.count
            ? preselectedPlanIndex : 0
        return purchaseManager.products.isEmpty ? nil : purchaseManager.products[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            authHeader

            if !authManager.isSignedIn {
                signInContent
            } else if !purchaseManager.isPro {
                confirmContent
            } else {
                proContent
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg.ignoresSafeArea())
        .onChange(of: purchaseManager.isPro) {
            if purchaseManager.isPro { onDone() }
        }
    }

    // MARK: - Auth Header

    private var authHeader: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                onDone()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42.24, height: 42.24)
                    .background(accent.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
    }

    // MARK: - Sign In

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Log In")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)

            Text("Sign in or create a new account")
                .font(.system(size: 14))
                .foregroundStyle(accent.opacity(0.6))
                .padding(.top, 4)
                .padding(.bottom, 28)

            themedField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            themedSecureField("Password", text: $password)
                .padding(.top, 12)
                .textContentType(.password)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
            }

            actionButton("Log In", disabled: isLoading || email.isEmpty || password.isEmpty) {
                Task { await logIn() }
            }
            .padding(.top, 24)
        }
    }

    // MARK: - Confirm Purchase

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confirm Plan")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)
                .padding(.bottom, 4)

            Text(authManager.userEmail ?? "")
                .font(.system(size: 14))
                .foregroundStyle(accent.opacity(0.6))
                .padding(.bottom, 28)

            if let product = selectedProduct {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                        Text(product.displayPrice)
                            .font(.system(size: 14))
                            .foregroundStyle(accent.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.2), lineWidth: 1))
                )
                .padding(.bottom, 24)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                actionButton("Purchase", disabled: isLoading) {
                    Task { await purchase(product) }
                }
            }
        }
    }

    // MARK: - Pro

    private var proContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(accent)
                .padding(.bottom, 4)

            Text("You're Pro")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(accent)

            Text(authManager.userEmail ?? "")
                .font(.system(size: 14))
                .foregroundStyle(accent.opacity(0.6))

            Button {
                try? authManager.signOut()
                onDone()
            } label: {
                Text("Sign Out")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Helpers

    private func themedField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 16))
            .foregroundStyle(fg)
            .tint(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fg.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(fg.opacity(0.2), lineWidth: 1))
            )
    }

    private func themedSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.system(size: 16))
            .foregroundStyle(fg)
            .tint(accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fg.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(fg.opacity(0.2), lineWidth: 1))
            )
    }

    private func actionButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(bg)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(bg)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(disabled ? accent.opacity(0.35) : accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func logIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            let code = (error as NSError).code
            // 17011 = userNotFound — create the account instead
            if code == 17011 {
                do {
                    try await authManager.createAccount(email: email, password: password)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func purchase(_ product: Product) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await purchaseManager.purchase(product)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    @Previewable @State var show = true
    UpgradeView(
        authManager: AuthManager(),
        purchaseManager: PurchaseManager(),
        showUpgrade: $show
    )
    .environment(ThemeManager())
}
