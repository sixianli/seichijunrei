import SwiftUI
import StoreKit
import SeichiCore

/// 付费墙：旅行通行证（7/30 天，不自动续费）与终身解锁。
struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var busyProductID: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statusBadge
                    features
                    productList
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button(L("paywall.restore")) {
                        Task {
                            busyProductID = "restore"
                            let ok = await store.restore()
                            busyProductID = nil
                            message = ok ? L("paywall.restored") : L("paywall.nothingToRestore")
                        }
                    }
                    .font(.footnote)
                    .disabled(busyProductID != nil)
                    .accessibilityIdentifier("restorePurchases")
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }.accessibilityIdentifier("closePaywall")
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.pink.gradient)
            Text(L("paywall.title")).font(.title.bold()).multilineTextAlignment(.center)
            Text(L("paywall.subtitle")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var statusBadge: some View {
        if let text = EntitlementText.status(store.entitlement) {
            Label(text, systemImage: store.entitlement.isUnlimited ? "checkmark.seal.fill" : "gift")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .accessibilityIdentifier("entitlementStatus")
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            feature("camera.viewfinder", L("paywall.feature1"))
            feature("party.popper", L("paywall.feature2"))
            feature("map", L("paywall.feature3"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline)
    }

    @ViewBuilder private var productList: some View {
        if store.products.isEmpty {
            if store.productsUnavailable {
                Text(L("paywall.unavailable")).font(.footnote).foregroundStyle(.secondary)
                Button(L("paywall.retry")) { Task { await store.loadProducts() } }
            } else {
                ProgressView()
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    productButton(product)
                }
            }
        }
    }

    private func productButton(_ product: Product) -> some View {
        let isLifetime = product.id == StoreProductID.lifetime
        return Button {
            Task { await buy(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title(for: product)).font(.headline)
                        if isLifetime {
                            Text(L("paywall.bestValue"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.pink, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(isLifetime ? L("paywall.lifetimeNote") : L("paywall.passNote"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busyProductID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice).font(.headline.monospacedDigit())
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14)
                .stroke(isLifetime ? Color.pink : Color.secondary.opacity(0.3), lineWidth: isLifetime ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyProductID != nil)
        .accessibilityIdentifier("buy-\(product.id)")
    }

    private func title(for product: Product) -> String {
        switch product.id {
        case StoreProductID.pass7: return L("paywall.pass7")
        case StoreProductID.pass30: return L("paywall.pass30")
        case StoreProductID.lifetime: return L("paywall.lifetime")
        default: return product.displayName
        }
    }

    private func buy(_ product: Product) async {
        busyProductID = product.id
        defer { busyProductID = nil }
        switch await store.purchase(product) {
        case .success:
            message = nil
            dismiss()
        case .pending:
            message = L("paywall.pending")
        case .cancelled:
            break
        case .failed(let reason):
            message = L("paywall.purchaseFailed", reason)
        }
    }
}

enum EntitlementText {
    /// 当前权益的一句话说明
    static func status(_ e: Entitlement) -> String? {
        switch e {
        case .lifetime: return L("status.lifetime")
        case .pass(let until):
            return L("status.passUntil", until.formatted(date: .abbreviated, time: .shortened))
        case .free(let remaining): return L("status.freeRemaining", remaining)
        }
    }
}

/// 名场面模式中，免费额度用完时显示的锁定层
struct SceneLockedOverlay: View {
    let tint: Color
    let onShowPaywall: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 40))
            Text(L("locked.title")).font(.title3.bold())
            Text(L("locked.body")).font(.callout).multilineTextAlignment(.center).opacity(0.85)
            Button(action: onShowPaywall) {
                Text(L("locked.cta")).font(.headline)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(tint, in: Capsule())
            }
            .accessibilityIdentifier("showPaywall")
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(Material.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sceneLocked")
    }
}
