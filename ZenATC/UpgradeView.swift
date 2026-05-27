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
    @State private var showUpgradeFlow = false

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
        .sheet(isPresented: $showUpgradeFlow) {
            UpgradeFlowSheet(
                authManager: authManager,
                purchaseManager: purchaseManager,
                preselectedPlanIndex: selectedPlan
            )
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
            showUpgradeFlow = true
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
}

// MARK: - Upgrade Flow Sheet

private struct UpgradeFlowSheet: View {
    let authManager: AuthManager
    let purchaseManager: PurchaseManager
    var preselectedPlanIndex: Int = 1

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var selectedProduct: Product? {
        let idx = preselectedPlanIndex < purchaseManager.products.count
            ? preselectedPlanIndex
            : 0
        return purchaseManager.products.isEmpty ? nil : purchaseManager.products[idx]
    }

    var body: some View {
        NavigationStack {
            Form {
                if !authManager.isSignedIn {
                    signInSection
                } else if !purchaseManager.isPro {
                    accountSection
                    plansSection
                } else {
                    proSection
                }
            }
            .navigationTitle("ZenATC Pro")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .onChange(of: authManager.isSignedIn) {
            if authManager.isSignedIn && purchaseManager.isPro {
                dismiss()
            }
        }
    }

    private var signInSection: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $password)
                .textContentType(.password)

            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button {
                Task { await logIn() }
            } label: {
                label("Log In")
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
        } header: {
            Text("Log in to upgrade")
        }
    }

    private var accountSection: some View {
        Section {
            Text(authManager.userEmail ?? "").foregroundStyle(.secondary)
        } header: {
            Text("Signed in as")
        }
    }

    private var plansSection: some View {
        Section {
            if let product = selectedProduct {
                Button {
                    Task { await purchase(product) }
                } label: {
                    HStack {
                        Text(product.displayName)
                        Spacer()
                        Text(product.displayPrice + " / mo").foregroundStyle(.secondary)
                    }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Text(error).foregroundStyle(.red).font(.caption)
            }
        } header: {
            Text("Confirm plan")
        }
    }

    private var proSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text("Pro ✓").foregroundStyle(.secondary)
            }
            Text(authManager.userEmail ?? "").foregroundStyle(.secondary)
            Button(role: .destructive) {
                try? authManager.signOut()
            } label: {
                Text("Sign Out")
            }
        } header: {
            Text("Account")
        }
    }

    private func label(_ title: String) -> some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
    }

    private func logIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            let code = (error as NSError).code
            // 17011 = userNotFound — account doesn't exist yet, create it
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
