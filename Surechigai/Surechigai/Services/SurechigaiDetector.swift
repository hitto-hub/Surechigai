//
//  SurechigaiDetector.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import Combine

/// すれ違い判定ロジックを担当
/// 距離・時間の条件に基づいてすれ違いを検出し、イベントを発行
@MainActor
final class SurechigaiDetector: ObservableObject {

    // MARK: - Configuration

    /// すれ違いと判定する最大距離（メートル）
    var thresholdDistance: Float = 3.0

    /// すれ違いと判定する最小継続時間（秒）
    var thresholdDuration: TimeInterval = 2.0

    /// 同じ相手との再検出までのクールダウン（秒）
    var cooldownDuration: TimeInterval = 60.0

    // MARK: - Published Properties

    /// 検出されたすれ違い（新しいものがPublish）
    @Published private(set) var lastDetectedSurechigai: SurechigaiRecord?

    /// 現在近くにいるピア（閾値内）
    @Published private(set) var nearbyPeers: Set<UUID> = []

    // MARK: - Private Properties

    /// ピアが近くに来た時刻
    private var entryTimes: [UUID: Date] = [:]

    /// ピアの最小距離記録
    private var minimumDistances: [UUID: Float] = [:]

    /// 最後にすれ違いを記録した時刻（クールダウン用）
    private var lastSurechigaiTimes: [UUID: Date] = [:]

    /// すれ違い検出コールバック
    var onSurechigaiDetected: ((SurechigaiRecord) -> Void)?

    // MARK: - Singleton

    static let shared = SurechigaiDetector()

    private init() {}

    // MARK: - Public Methods

    /// 測定結果を処理してすれ違いを判定
    /// - Parameters:
    ///   - peerId: ピアID
    ///   - peerName: ピアの表示名
    ///   - measurement: 測定結果
    ///   - roomName: ルーム名（オプション）
    func processMeasurement(
        peerId: UUID,
        peerName: String,
        measurement: NearbyMeasurement,
        roomName: String? = nil
    ) {
        guard let distance = measurement.distance else { return }

        let now = Date()

        if distance <= thresholdDistance {
            // 閾値内に入った

            if !nearbyPeers.contains(peerId) {
                // 新しく近づいてきた
                nearbyPeers.insert(peerId)
                entryTimes[peerId] = now
                minimumDistances[peerId] = distance
                print("📍 Peer entered range: \(peerName) at \(distance)m")
            } else {
                // 継続して近くにいる - 最小距離を更新
                if let currentMin = minimumDistances[peerId], distance < currentMin {
                    minimumDistances[peerId] = distance
                }

                // すれ違い判定
                if let entryTime = entryTimes[peerId] {
                    let duration = now.timeIntervalSince(entryTime)

                    if duration >= thresholdDuration {
                        // クールダウンチェック
                        if let lastTime = lastSurechigaiTimes[peerId],
                           now.timeIntervalSince(lastTime) < cooldownDuration {
                            // クールダウン中なのでスキップ
                            return
                        }

                        // すれ違い検出！
                        let record = SurechigaiRecord(
                            peerId: peerId,
                            peerDisplayName: peerName,
                            timestamp: entryTime,
                            minimumDistance: minimumDistances[peerId] ?? distance,
                            duration: duration,
                            roomName: roomName
                        )

                        lastDetectedSurechigai = record
                        lastSurechigaiTimes[peerId] = now
                        onSurechigaiDetected?(record)

                        print("🎉 Surechigai detected: \(peerName) (distance: \(record.formattedDistance), duration: \(Int(duration))s)")

                        // エントリータイムをリセット（連続検出防止）
                        entryTimes[peerId] = now
                    }
                }
            }
        } else {
            // 閾値外に出た
            if nearbyPeers.contains(peerId) {
                nearbyPeers.remove(peerId)
                entryTimes.removeValue(forKey: peerId)
                minimumDistances.removeValue(forKey: peerId)
                print("👋 Peer left range: \(peerName)")
            }
        }
    }

    /// ピアを削除（セッション終了時など）
    func removePeer(_ peerId: UUID) {
        nearbyPeers.remove(peerId)
        entryTimes.removeValue(forKey: peerId)
        minimumDistances.removeValue(forKey: peerId)
    }

    /// 全ピアをリセット
    func reset() {
        nearbyPeers.removeAll()
        entryTimes.removeAll()
        minimumDistances.removeAll()
        lastSurechigaiTimes.removeAll()
    }

    /// 設定を更新
    func updateSettings(
        thresholdDistance: Float? = nil,
        thresholdDuration: TimeInterval? = nil,
        cooldownDuration: TimeInterval? = nil
    ) {
        if let dist = thresholdDistance {
            self.thresholdDistance = dist
        }
        if let dur = thresholdDuration {
            self.thresholdDuration = dur
        }
        if let cool = cooldownDuration {
            self.cooldownDuration = cool
        }
    }
}
