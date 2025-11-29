//
//  Peer.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import NearbyInteraction

/// ピア（他のユーザー/デバイス）を表すモデル
struct Peer: Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var discoveryToken: NIDiscoveryToken?

    /// 最後に測定された距離（メートル）
    var lastDistance: Float?

    /// 最後に測定された方向（ラジアン）
    var lastDirection: simd_float3?

    /// 最後の更新時刻
    var lastUpdated: Date?

    /// 接続状態
    var connectionState: ConnectionState = .disconnected

    enum ConnectionState: String {
        case disconnected = "未接続"
        case connecting = "接続中..."
        case connected = "接続済み"
        case measuring = "測距中"
    }

    init(id: UUID = UUID(), displayName: String, discoveryToken: NIDiscoveryToken? = nil) {
        self.id = id
        self.displayName = displayName
        self.discoveryToken = discoveryToken
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.id == rhs.id
    }
}
