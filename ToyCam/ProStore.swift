import Foundation
import StoreKit

/// StoreKit 2 래퍼 — 평생 단일 상품(PRO 카트리지) 구매·복원·권한 추적.
/// `isPro` 가 필터 24종/동영상/미세조정을 해제한다.
@MainActor
final class ProStore: ObservableObject {
    static let lifetimeID = "com.toycam.app.pro.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isPro = false
    @Published private(set) var loading = true
    @Published var purchasing = false

    private var updates: Task<Void, Never>?

    init() {
        updates = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlement()
            loading = false
        }
    }

    var displayPrice: String { product?.displayPrice ?? "$3.99" }

    func loadProduct() async {
        product = try? await Product.products(for: [Self.lifetimeID]).first
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                    return isPro
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var pro = UserDefaults.standard.bool(forKey: Self.devKey)
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.lifetimeID,
               transaction.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
    }

    // MARK: 개발 테스트용 로컬 해제 (UI 노출 없음)

    private static let devKey = "toycam.devProUnlock"

    @discardableResult
    func toggleDevPro() -> Bool {
        let new = !UserDefaults.standard.bool(forKey: Self.devKey)
        UserDefaults.standard.set(new, forKey: Self.devKey)
        Task { await refreshEntitlement() }
        return new
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
