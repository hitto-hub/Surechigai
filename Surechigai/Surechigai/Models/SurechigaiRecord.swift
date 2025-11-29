//
//  SurechigaiRecord.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation

/// すれ違いログ1件を表すモデル
struct SurechigaiRecord: Identifiable, Codable {
    let id: UUID

    /// すれ違った相手のID
    let peerId: UUID

    /// すれ違った相手の表示名
    let peerDisplayName: String

    /// すれ違いが検出された時刻
    let timestamp: Date

    /// すれ違い時の最小距離（メートル）
    let minimumDistance: Float

    /// すれ違いの継続時間（秒）
    let duration: TimeInterval

    /// イベント/ルーム名（オプション）
    let roomName: String?

    init(
        id: UUID = UUID(),
        peerId: UUID,
        peerDisplayName: String,
        timestamp: Date = Date(),
        minimumDistance: Float,
        duration: TimeInterval,
        roomName: String? = nil
    ) {
        self.id = id
        self.peerId = peerId
        self.peerDisplayName = peerDisplayName
        self.timestamp = timestamp
        self.minimumDistance = minimumDistance
        self.duration = duration
        self.roomName = roomName
    }
}

// MARK: - Convenience
extension SurechigaiRecord {
    /// 時刻を表示用にフォーマット
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    /// 日付を表示用にフォーマット
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: timestamp)
    }

    /// 距離を表示用にフォーマット
    var formattedDistance: String {
        if minimumDistance < 1.0 {
            return String(format: "%.0f cm", minimumDistance * 100)
        } else {
            return String(format: "%.1f m", minimumDistance)
        }
    }
}
