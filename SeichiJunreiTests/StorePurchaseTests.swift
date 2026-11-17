import XCTest
import StoreKit
import StoreKitTest
import SeichiCore
@testable import SeichiJunrei

/// 用 StoreKitTest 在模拟器中跑真实的 StoreKit 2 购买流程（使用 SeichiJunrei.storekit 本地配置）。
final class StorePurchaseTests: XCTestCase {
    var session: SKTestSession!
    var defaults: UserDefaults!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SeichiJunrei", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defaults = UserDefaults(suiteName: "StorePurchaseTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
    }

    @MainActor func makeStore() -> StoreService { StoreService(defaults: defaults) }

    @MainActor func testProductsLoadWithPrices() async throws {
        let store = makeStore()
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), StoreProductID.all)
        XCTAssertEqual(store.products.first { $0.id == StoreProductID.lifetime }?.type, .nonConsumable)
        XCTAssertEqual(store.products.first { $0.id == StoreProductID.pass7 }?.type, .nonRenewable)
        XCTAssertFalse(store.productsUnavailable)
    }

    @MainActor func testFreeAllowanceThenLocked() async throws {
        let store = makeStore()
        await store.refreshEntitlements()
        XCTAssertEqual(store.entitlement, .free(remaining: 3))
        for id in ["a", "b", "c"] {
            XCTAssertTrue(store.canEnterScene(id))
            store.recordSceneEntry(id)
        }
        XCTAssertEqual(store.entitlement, .free(remaining: 0))
        XCTAssertFalse(store.canEnterScene("d"))
        XCTAssertTrue(store.canEnterScene("a"), "体验过的名场面可以再次进入")
        // 额度持久化
        XCTAssertEqual(StoreService(defaults: defaults).allowance.remaining, 0)
    }

    @MainActor func testBuyingWeekPassUnlocksAndStacks() async throws {
        let store = makeStore()
        await store.loadProducts()
        let pass7 = try XCTUnwrap(store.products.first { $0.id == StoreProductID.pass7 })

        let first = await store.purchase(pass7)
        XCTAssertEqual(first, .success)
        guard case .pass(let until1) = store.entitlement else { return XCTFail("应为通行证：\(store.entitlement)") }
        XCTAssertEqual(until1.timeIntervalSinceNow, 7 * 86_400, accuracy: 3_600)

        let second = await store.purchase(pass7)
        XCTAssertEqual(second, .success)
        guard case .pass(let until2) = store.entitlement else { return XCTFail("应为通行证") }
        XCTAssertEqual(until2.timeIntervalSinceNow, 14 * 86_400, accuracy: 3_600, "连续购买应顺延")
        XCTAssertTrue(store.canEnterScene("any-spot"))
    }

    @MainActor func testBuyingLifetimeUnlocksForever() async throws {
        let store = makeStore()
        await store.loadProducts()
        let lifetime = try XCTUnwrap(store.products.first { $0.id == StoreProductID.lifetime })
        let outcome = await store.purchase(lifetime)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(store.entitlement, .lifetime)

        // 新的实例（相当于重启 App / 恢复购买）也能从交易记录得到终身权益
        let restored = makeStore()
        let ok = await restored.restore()
        XCTAssertTrue(ok)
        XCTAssertEqual(restored.entitlement, .lifetime)
    }

    @MainActor func testRefundRevokesLifetime() async throws {
        let store = makeStore()
        await store.loadProducts()
        let lifetime = try XCTUnwrap(store.products.first { $0.id == StoreProductID.lifetime })
        _ = await store.purchase(lifetime)
        XCTAssertEqual(store.entitlement, .lifetime)

        let tx = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreProductID.lifetime })
        try session.refundTransaction(identifier: UInt(tx.identifier))
        await store.refreshEntitlements()
        XCTAssertEqual(store.entitlement, .free(remaining: 3), "退款后应失去权益")
    }
}
