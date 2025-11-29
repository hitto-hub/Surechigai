//
//  NearbySessionManager.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import NearbyInteraction
import Combine

/// NISessionを管理するクラス
/// UWBによる測距の開始・停止・結果取得を担当
@MainActor
final class NearbySessionManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// 現在の測定結果（ピアID → 測定結果）
    @Published private(set) var measurements: [UUID: NearbyMeasurement] = [:]

    /// セッションが実行中かどうか
    @Published private(set) var isRunning = false

    /// エラーメッセージ
    @Published var errorMessage: String?

    /// 自分の discoveryToken
    @Published private(set) var myDiscoveryToken: NIDiscoveryToken?

    // MARK: - Private Properties

    /// NISession（ピアごとに1つ）
    private var sessions: [UUID: NISession] = [:]

    /// ピアID → discoveryToken のマッピング
    private var peerTokens: [UUID: NIDiscoveryToken] = [:]

    /// メインセッション（discoveryToken取得用、保持が必要）
    private var mainSession: NISession?

    /// 測定結果のコールバック
    var onMeasurementUpdated: ((UUID, NearbyMeasurement) -> Void)?

    /// ピアがなくなった時のコールバック
    var onPeerRemoved: ((UUID) -> Void)?

    // MARK: - Singleton

    static let shared = NearbySessionManager()

    private override init() {
        super.init()
        initializeSession()
    }

    // MARK: - Public Methods

    /// UWBがサポートされているかチェック
    var isSupported: Bool {
        if #available(iOS 16.0, *) {
            return NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        } else {
            return NISession.isSupported
        }
    }

    /// セッションを初期化して discoveryToken を取得
    func initializeSession() {
        guard isSupported else {
            errorMessage = "このデバイスはUWBをサポートしていません"
            return
        }

        // デバイス能力をログ出力
        logDeviceCapabilities()

        // メインセッションを作成して discoveryToken を取得
        // 重要: このセッションを使ってrunも行う（トークンとセッションの一致が必須）
        let session = NISession()
        session.delegate = self
        self.mainSession = session
        myDiscoveryToken = session.discoveryToken

        print("🔑 Main session created, discoveryToken: \(myDiscoveryToken != nil ? "available" : "nil")")
    }

    /// ピアとの測距を開始
    /// - Parameters:
    ///   - peerId: ピアのID
    ///   - peerToken: ピアの discoveryToken
    func startSession(with peerId: UUID, peerToken: NIDiscoveryToken) {
        guard isSupported else {
            print("❌ UWB not supported on this device")
            return
        }

        // mainSessionがなければ初期化
        if mainSession == nil {
            print("⚠️ mainSession is nil, reinitializing...")
            initializeSession()
        }

        guard let session = mainSession else {
            print("❌ Failed to get mainSession")
            return
        }

        print("🔧 Starting NI session for peer: \(peerId)")
        print("🔧 Peer token hash: \(peerToken.hashValue)")
        print("🔧 Using mainSession (same session that generated our discoveryToken)")

        // ピア情報を保存
        peerTokens[peerId] = peerToken

        // セッション設定
        // 重要: runを呼ぶセッションは、discoveryTokenを生成したセッションと同じでなければならない
        let config = NINearbyPeerConfiguration(peerToken: peerToken)

        // 注意: EDMはiPhone 15/16のU2チップ同士でのみ動作
        // デフォルトではOFFにして安定性を優先
        /*
        if #available(iOS 17.0, *) {
            let caps = NISession.deviceCapabilities
            if caps.supportsExtendedDistanceMeasurement {
                config.isExtendedDistanceMeasurementEnabled = true
                print("🟢 EDM enabled")
            }
        }
        */

        print("🔧 Running mainSession with config (EDM: disabled for stability)...")
        session.run(config)

        isRunning = true
        currentPeerId = peerId
        print("📡 NISession started for peer: \(peerId)")
    }

    // 現在のピアID（mainSession用）
    private var currentPeerId: UUID?

    /// 特定ピアとのセッションを停止
    func stopSession(for peerId: UUID) {
        // mainSessionを使っているので、セッション自体は停止しない
        // 測定データのみクリア
        measurements.removeValue(forKey: peerId)
        peerTokens.removeValue(forKey: peerId)
        if currentPeerId == peerId {
            currentPeerId = nil
            isRunning = false
        }
        print("🛑 NISession data cleared for peer: \(peerId)")
    }

    /// 全セッションを停止
    func stopAllSessions() {
        // mainSessionを無効化
        mainSession?.invalidate()
        mainSession = nil
        myDiscoveryToken = nil
        currentPeerId = nil

        // 古いsessionsも念のためクリア
        for (peerId, session) in sessions {
            session.invalidate()
            print("🛑 NISession stopped for peer: \(peerId)")
        }
        sessions.removeAll()
        measurements.removeAll()
        peerTokens.removeAll()
        isRunning = false
        print("🛑 All sessions stopped including mainSession")
    }

    /// discoveryToken を Data にシリアライズ
    func serializeToken(_ token: NIDiscoveryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    /// Data から discoveryToken をデシリアライズ
    func deserializeToken(from data: Data) -> NIDiscoveryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }

    /// 新しいセッションを作成して discoveryToken を生成
    /// サーバー経由の token 交換用
    func generateDiscoveryToken() -> NIDiscoveryToken? {
        guard isSupported else {
            errorMessage = "このデバイスはUWBをサポートしていません"
            return nil
        }

        let session = NISession()
        session.delegate = self
        let token = session.discoveryToken

        // 生成したトークンを保持（後で接続時に使う）
        myDiscoveryToken = token

        return token
    }
}

// MARK: - NISessionDelegate
extension NearbySessionManager: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            print("📍 didUpdate called with \(nearbyObjects.count) objects")

            for object in nearbyObjects {
                // このオブジェクトがどのピアか特定
                guard let peerId = findPeerId(for: object.discoveryToken) else {
                    print("⚠️ Could not find peerId for token")
                    continue
                }

                print("📍 Peer \(peerId): distance=\(object.distance?.description ?? "nil"), direction=\(object.direction?.description ?? "nil")")

                let measurement = NearbyMeasurement(
                    distance: object.distance,
                    direction: object.direction
                )

                measurements[peerId] = measurement
                onMeasurementUpdated?(peerId, measurement)
            }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            for object in nearbyObjects {
                guard let peerId = findPeerId(for: object.discoveryToken) else { continue }

                switch reason {
                case .peerEnded:
                    print("👋 Peer ended session: \(peerId)")
                case .timeout:
                    print("⏰ Peer timeout: \(peerId)")
                @unknown default:
                    print("❓ Peer removed for unknown reason: \(peerId)")
                }

                onPeerRemoved?(peerId)
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            print("⏸ NISession suspended - アプリがバックグラウンドに移行した可能性があります")
            print("💡 UWBが正常に動作するには:")
            print("   - アプリがフォアグラウンドにあること")
            print("   - 設定 > プライバシー > 近くの操作 で許可されていること")
            print("   - 両端末が9m以内にあること")
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            print("▶️ NISession suspension ended - セッションを再開します")

            // サスペンション終了時にセッションを再開
            guard let peerId = currentPeerId,
                  let token = peerTokens[peerId] else {
                print("⚠️ セッション再開に必要な情報がありません")
                return
            }

            let config = NINearbyPeerConfiguration(peerToken: token)

            // EDMは無効化中
            /*
            if #available(iOS 17.0, *) {
                let caps = NISession.deviceCapabilities
                if caps.supportsExtendedDistanceMeasurement {
                    config.isExtendedDistanceMeasurementEnabled = true
                }
            }
            */

            mainSession?.run(config)
            print("🔄 セッション再開: \(peerId)")
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            print("❌ NISession invalidated:")
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            print("   Description: \(error.localizedDescription)")

            // よくあるエラーの説明
            if nsError.domain == "NIError" {
                switch nsError.code {
                case 1:
                    print("💡 エラー: UWBハードウェアが利用できません")
                case 2:
                    print("💡 エラー: セッションが失敗しました。再接続を試してください")
                case 3:
                    print("💡 エラー: セッションがタイムアウトしました")
                case 5:
                    print("💡 エラー: アクティブセッション数の上限に達しました")
                default:
                    break
                }
            }

            // mainSessionが無効化された場合、クリア
            if session === mainSession {
                mainSession = nil
                myDiscoveryToken = nil
                currentPeerId = nil
                isRunning = false
                print("⚠️ mainSession was invalidated, need to reinitialize")
            }

            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Helpers

    private func findPeerId(for token: NIDiscoveryToken) -> UUID? {
        peerTokens.first { $0.value == token }?.key
    }

    /// デバイスのUWB能力をログ出力
    private func logDeviceCapabilities() {
        print("📱 ===== UWB Device Capabilities =====")

        if #available(iOS 16.0, *) {
            let caps = NISession.deviceCapabilities

            print("📱 supportsPreciseDistanceMeasurement: \(caps.supportsPreciseDistanceMeasurement)")
            print("📱 supportsDirectionMeasurement: \(caps.supportsDirectionMeasurement)")
            print("📱 supportsCameraAssistance: \(caps.supportsCameraAssistance)")

            if #available(iOS 17.0, *) {
                print("📱 supportsExtendedDistanceMeasurement (EDM): \(caps.supportsExtendedDistanceMeasurement)")
            }
        } else {
            print("📱 NISession.isSupported: \(NISession.isSupported)")
        }

        print("📱 =====================================")
    }
}
