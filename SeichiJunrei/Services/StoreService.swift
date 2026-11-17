import Foundation
import Observation
import StoreKit
import SeichiCore

/// App 内购买的商品 ID（上架前请在 App Store Connect 创建同名商品）
enum StoreProductID {
    static let pass7 = "com.xianlisi.seichijunrei.pass7"
    static let pass30 = "com.xianlisi.seichijunrei.pass30"
    static let lifetime = "com.xianlisi.seichijunrei.lifetime"

    static let all = [pass7, pass30, lifetime]
    /// 非续期订阅（旅行通行证）对应的天数
    static let passDays: [String: Int] = [pass7: 7, pass30: 30]
}

/// StoreKit 2：加载商品、购买、恢复、监听交易，并计算当前权益。
@Observable
final class StoreService {
    static let shared = StoreService()

    private(set) var products: [Product] = []
    private(set) var entitlement: Entitlement = .free(remaining: AccessPolicy.freeSceneLimit)
    private(set) var allowance: FreeSceneAllowance
    private(set) var isLoadingProducts = false
    private(set) var productsUnavailable = false

    @ObservationIgnored private var hasLifetime = false
    @ObservationIgnored private var passExpiry: Date?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var debugOverride: Entitlement?
    private static let allowanceKey = "freeSceneAllowance"

    /// 收费是否开启（关闭时为免费公测期）
    let paywallEnabled: Bool

    init(defaults: UserDefaults = .standard, paywallEnabled: Bool = AppConfig.paywallEnabled) {
        self.defaults = defaults
        self.paywallEnabled = paywallEnabled
        if let data = defaults.data(forKey: Self.allowanceKey),
           let saved = try? JSONDecoder().decode(FreeSceneAllowance.self, from: data) {
            allowance = saved
        } else {
            allowance = FreeSceneAllowance()
        }
        #if DEBUG
        // UI 测试：SEICHI_ENTITLEMENT=lifetime|pass|free，SEICHI_FREE_USED=n
        let env = ProcessInfo.processInfo.environment
        if let n = env["SEICHI_FREE_USED"].flatMap(Int.init) {
            allowance = FreeSceneAllowance(usedSpotIDs: (0..<n).map { "debug-\($0)" })
        }
        switch env["SEICHI_ENTITLEMENT"] {
        case "lifetime": debugOverride = .lifetime
        case "pass": debugOverride = .pass(until: Date().addingTimeInterval(7 * 86_400))
        default: break
        }
        #endif
        recomputeEntitlement()
    }

    /// App 启动时调用：开始监听交易并刷新权益与商品
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            // 免费公测期不需要加载商品（App Store Connect 里也可以先不创建内购商品）
            if paywallEnabled { await loadProducts() }
        }
    }

    // MARK: 商品

    @MainActor
    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: StoreProductID.all)
            products = StoreProductID.all.compactMap { id in loaded.first { $0.id == id } }
            productsUnavailable = products.isEmpty
        } catch {
            productsUnavailable = true
        }
    }

    // MARK: 购买与恢复

    enum PurchaseOutcome: Equatable {
        case success, pending, cancelled
        case failed(String)
    }

    @MainActor
    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("verification")
                }
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 恢复购买：与 App Store 同步后重新计算权益。返回是否有可用权益。
    @MainActor
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refreshEntitlements()
        return entitlement.isUnlimited
    }

    /// 从全部交易记录计算权益（通行证需要完整历史才能正确顺延）
    @MainActor
    func refreshEntitlements() async {
        var lifetime = false
        var passes: [PassPurchase] = []
        for await result in Transaction.all {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == StoreProductID.lifetime {
                lifetime = true
            } else if let days = StoreProductID.passDays[t.productID] {
                passes.append(PassPurchase(purchaseDate: t.purchaseDate, days: days))
            }
        }
        hasLifetime = lifetime
        passExpiry = AccessPolicy.passExpiry(passes)
        recomputeEntitlement()
    }

    // MARK: 免费额度

    /// 能否进入该名场面的取景模式
    func canEnterScene(_ spotID: String) -> Bool {
        recomputeEntitlement()
        return allowance.canEnter(spotID, entitlement: entitlement)
    }

    /// 进入取景模式时调用：免费用户会消耗一次额度（同一处不重复扣）
    func recordSceneEntry(_ spotID: String) {
        guard !entitlement.isUnlimited else { return }
        // 在副本上修改，只有真的新增了一处时才写回（避免无谓地触发界面刷新）
        var updated = allowance
        guard updated.consume(spotID), updated != allowance else { return }
        allowance = updated
        if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: Self.allowanceKey) }
        recomputeEntitlement()
    }

    private func recomputeEntitlement() {
        if let debugOverride { entitlement = debugOverride; return }
        let next = AccessPolicy.entitlement(now: Date(), hasLifetime: hasLifetime, passExpiry: passExpiry,
                                            freeUsed: allowance.usedSpotIDs.count, freeLimit: allowance.limit,
                                            paywallEnabled: paywallEnabled)
        if next != entitlement { entitlement = next }
    }
}
