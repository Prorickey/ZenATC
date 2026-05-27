//
//  PurchaseManager.swift
//  ZenATC
//

import StoreKit
import Observation

@Observable
final class PurchaseManager {
    private let productIDs = [
        "com.zenatc.pro.monthly",
        "com.zenatc.pro.annual",
    ]

    private(set) var products: [Product] = []
    private(set) var isPro: Bool = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task {
            await loadProducts()
            await updatePurchaseStatus()
            // Keep listening for transaction updates (renewals, refunds, etc.)
            for await _ in Transaction.updates {
                await updatePurchaseStatus()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        if case .success(let verification) = result {
            let transaction = try verification.payloadValue
            await transaction.finish()
            await updatePurchaseStatus()
        }
    }

    // MARK: - Private

    private func loadProducts() async {
        products = (try? await Product.products(for: productIDs)) ?? []
        // Sort so monthly appears before annual in the UI
        products.sort { $0.price < $1.price }
    }

    private func updatePurchaseStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               productIDs.contains(transaction.productID) {
                hasPro = true
            }
        }
        isPro = hasPro
    }
}
