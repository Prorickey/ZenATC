//
//  AccountSheet.swift
//  ZenATC
//

import SwiftUI
import StoreKit

struct AccountSheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                if !authManager.isSignedIn {
                    signInSection
                } else if authManager.isSignedIn && !purchaseManager.isPro {
                    accountSection
                    proSection
                } else {
                    accountSection
                    proStatusSection
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Sections

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
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                Task { await signIn() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)

            Button {
                Task { await createAccount() }
            } label: {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
        } header: {
            Text("Sign In")
        }
    }

    private var accountSection: some View {
        Section {
            Text(authManager.userEmail ?? "")
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                try? authManager.signOut()
            } label: {
                Text("Sign Out")
            }
        } header: {
            Text("Account")
        }
    }

    private var proSection: some View {
        Section {
            ForEach(purchaseManager.products) { product in
                Button {
                    Task { await purchase(product) }
                } label: {
                    HStack {
                        Text(product.displayName)
                        Spacer()
                        Text(product.displayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isLoading)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("Upgrade to Pro")
        } footer: {
            Text("Subscriptions renew automatically. Cancel anytime in Settings.")
        }
    }

    private var proStatusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text("Pro ✓")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Subscription")
        }
    }

    // MARK: - Actions

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createAccount() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.createAccount(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
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
