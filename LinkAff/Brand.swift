import SwiftUI

enum Brand {
    static let name = "Affiliate Link Helper"
    static let bundleID = "com.simplelifesolution.affiliatehelper"
    static let appGroupID = "group.com.simplelifesolution.affiliatehelper"
    static let subIDPrefixes = ["ios", "affiliate", "shop"]
    static let accent = Color("AccentColor")
}

enum ShareChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiktok, facebook, line, instagram
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tiktok: "TikTok"
        case .facebook: "Facebook"
        case .line: "LINE"
        case .instagram: "Instagram"
        }
    }
}
struct TrackingRequest: Codable, Equatable, Sendable {
    let channel: ShareChannel
    let subIdPrefixes: [String]
}
