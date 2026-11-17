import Foundation

/// 收费模式：免费体验若干处名场面 → 旅行通行证（非续期，7/30 天，可叠加）或终身买断。
/// 这里只放纯逻辑，StoreKit 交互在 App 层。
public enum Entitlement: Equatable, Sendable {
    case lifetime
    case pass(until: Date)
    case free(remaining: Int)

    /// 是否不限次数使用名场面模式
    public var isUnlimited: Bool {
        switch self {
        case .lifetime, .pass: return true
        case .free: return false
        }
    }
}

/// 一笔通行证购买
public struct PassPurchase: Equatable, Sendable {
    public var purchaseDate: Date
    public var days: Int
    public init(purchaseDate: Date, days: Int) { self.purchaseDate = purchaseDate; self.days = days }
}

public enum AccessPolicy {
    /// 免费可体验的不同名场面数量
    public static let freeSceneLimit = 3

    /// 计算通行证到期时间。连续购买会顺延：新购买从“上一张到期时间”和“购买时间”中较晚的那个开始计算。
    public static func passExpiry(_ purchases: [PassPurchase], calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        var expiry: Date?
        for p in purchases.sorted(by: { $0.purchaseDate < $1.purchaseDate }) where p.days > 0 {
            let start = max(expiry ?? p.purchaseDate, p.purchaseDate)
            expiry = calendar.date(byAdding: .day, value: p.days, to: start)
        }
        return expiry
    }

    public static func entitlement(now: Date, hasLifetime: Bool, passExpiry: Date?,
                                   freeUsed: Int, freeLimit: Int = freeSceneLimit) -> Entitlement {
        if hasLifetime { return .lifetime }
        if let e = passExpiry, e > now { return .pass(until: e) }
        return .free(remaining: max(0, freeLimit - freeUsed))
    }
}

/// 免费体验额度：按“不同的名场面”计数，同一处名场面重复进入不再扣次数。
public struct FreeSceneAllowance: Codable, Equatable, Sendable {
    public private(set) var usedSpotIDs: [String]
    public var limit: Int

    public init(usedSpotIDs: [String] = [], limit: Int = AccessPolicy.freeSceneLimit) {
        self.usedSpotIDs = usedSpotIDs; self.limit = limit
    }

    public var remaining: Int { max(0, limit - usedSpotIDs.count) }

    public func canEnter(_ spotID: String) -> Bool {
        usedSpotIDs.contains(spotID) || usedSpotIDs.count < limit
    }

    /// 记录一次体验。返回 false 表示额度已用完且该名场面未体验过。
    @discardableResult
    public mutating func consume(_ spotID: String) -> Bool {
        if usedSpotIDs.contains(spotID) { return true }
        guard usedSpotIDs.count < limit else { return false }
        usedSpotIDs.append(spotID)
        return true
    }

    /// 在当前权益下能否进入某个名场面的取景模式
    public func canEnter(_ spotID: String, entitlement: Entitlement) -> Bool {
        entitlement.isUnlimited || canEnter(spotID)
    }
}
