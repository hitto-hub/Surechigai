//
//  SurechigaiModeViewModel.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine
import UserNotifications

/// すれ違いモード画面のViewModel
/// モードのON/OFF、すれ違い検出の管理
@MainActor
final class SurechigaiModeViewModel: ObservableObject {

    // MARK: - Published Properties

    /// すれ違いモードがONかどうか
    @Published var isModeEnabled = false {
        didSet {
            if isModeEnabled {
                startSurechigaiMode()
            } else {
                stopSurechigaiMode()
            }
        }
    }

    /// 接続中のピア数
    @Published private(set) var connectedPeerCount: Int = 0

    /// 現在近くにいるピア数
    @Published private(set) var nearbyPeerCount: Int = 0

    /// 今日のすれ違いカウント
    @Published private(set) var todaySurechigaiCount: Int = 0

    /// 現在のルーム名
    @Published var roomName: String = ""

    /// 状態メッセージ
    @Published private(set) var statusMessage: String = "モードがOFFです"

    /// エラーメッセージ
    @Published var errorMessage: String?

    /// 設定: すれ違い判定距離（メートル）
    @Published var thresholdDistance: Float = 3.0 {
        didSet {
            surechigaiDetector.thresholdDistance = thresholdDistance
            saveSettings()
        }
    }

    /// 設定: すれ違い判定時間（秒）
    @Published var thresholdDuration: TimeInterval = 2.0 {
        didSet {
            surechigaiDetector.thresholdDuration = thresholdDuration
            saveSettings()
        }
    }

    /// 設定: クールダウン時間（秒）
    @Published var cooldownDuration: TimeInterval = 60.0 {
        didSet {
            surechigaiDetector.cooldownDuration = cooldownDuration
            saveSettings()
        }
    }

    /// 設定: 通知を有効にするか
    @Published var notificationsEnabled: Bool = true {
        didSet { saveSettings() }
    }

    /// 設定: バイブレーションを有効にするか
    @Published var hapticEnabled: Bool = true {
        didSet { saveSettings() }
    }

    /// UWBがサポートされているか
    @Published private(set) var isUWBSupported: Bool = false

    /// Live Activityが実行中か
    @Published private(set) var isLiveActivityRunning: Bool = false

    /// 接続モード
    @Published var connectionMode: ConnectionMode = .multipeer {
        didSet { saveSettings() }
    }

    /// サーバーURL
    @Published var serverURL: String = "http://192.168.1.1:3000" {
        didSet { saveSettings() }
    }

    /// 自分の表示名
    @Published var displayName: String = UIDevice.current.name {
        didSet { saveSettings() }
    }

    /// サーバー経由で取得したピア
    @Published private(set) var serverPeers: [TokenEntry] = []

    /// 近くにいるピアの詳細リスト
    @Published private(set) var nearbyPeerDetails: [NearbyPeerInfo] = []

    /// 最新のすれ違い
    @Published private(set) var latestSurechigai: SurechigaiRecord?

    /// 接続モードの種類
    enum ConnectionMode: String, CaseIterable, Codable {
        case multipeer = "ローカル"
        case server = "サーバー経由"
    }

    // MARK: - Private Properties

    private let nearbyManager = NearbySessionManager.shared
    private let multipeerManager = MultipeerManager.shared
    private let surechigaiDetector = SurechigaiDetector.shared
    private let surechigaiLogger = SurechigaiLogger.shared
    private let liveActivityManager = LiveActivityManager.shared
    private let tokenClient = TokenAPIClient.shared

    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?
    private var userId = UUID().uuidString

    /// MCPeerID → Peer のマッピング
    private var peerMapping: [MCPeerID: Peer] = [:]

    /// サーバーモード用: userId → UUID のマッピング
    private var serverPeerUUIDs: [String: UUID] = [:]

    /// 近くにいるピアの距離情報
    private var peerDistances: [UUID: Float] = [:]

    /// 設定保存用のキー
    private let settingsKey = "SurechigaiModeSettings"

    // MARK: - Initialization

    init() {
        isUWBSupported = nearbyManager.isSupported
        loadSettings()
        setupBindings()
        updateTodayCount()
        requestNotificationPermission()
    }

    // MARK: - Public Methods

    /// 今日のカウントを更新
    func updateTodayCount() {
        todaySurechigaiCount = surechigaiLogger.todayUniqueCount
    }

    /// 通知権限をリクエスト
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            } else {
                print(granted ? "✅ Notification permission granted" : "❌ Notification permission denied")
            }
        }
    }

    // MARK: - Private Methods

    private func startSurechigaiMode() {
        guard isUWBSupported else {
            errorMessage = "このデバイスはUWBをサポートしていません"
            isModeEnabled = false
            return
        }

        switch connectionMode {
        case .multipeer:
            startMultipeerMode()
        case .server:
            startServerMode()
        }

        // Live Activity開始
        let activityRoomName = roomName.isEmpty ? "すれ違いモード" : roomName
        liveActivityManager.startActivity(roomName: activityRoomName)

        print("🟢 Surechigai mode started (\(connectionMode.rawValue))")
    }

    private func startMultipeerMode() {
        multipeerManager.setup(displayName: displayName)
        multipeerManager.start()
        statusMessage = "ピアを検索中..."
    }

    private func startServerMode() {
        guard let url = URL(string: serverURL) else {
            errorMessage = "無効なサーバーURLです"
            isModeEnabled = false
            return
        }

        statusMessage = "サーバーに接続中..."

        Task {
            do {
                await tokenClient.configure(baseURL: url, userId: userId)
                await tokenClient.setDisplayName(displayName)
                await tokenClient.joinRoom(roomName.isEmpty ? "default" : roomName)

                // トークン生成・登録
                if let token = nearbyManager.generateDiscoveryToken() {
                    try await tokenClient.registerToken(token)
                    statusMessage = "ルームで待機中..."
                    startPolling()
                } else {
                    errorMessage = "トークン生成に失敗しました"
                    isModeEnabled = false
                }
            } catch {
                errorMessage = "サーバー接続エラー: \(error.localizedDescription)"
                isModeEnabled = false
            }
        }
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let tokens = try await tokenClient.fetchTokens()
                    await MainActor.run {
                        self.serverPeers = tokens
                        self.connectedPeerCount = tokens.count

                        // 新しいピアのみセッションを開始（既存はスキップ）
                        var currentUserIds = Set<String>()
                        for entry in tokens {
                            currentUserIds.insert(entry.userId)

                            // 既にセッションがあるかチェック
                            if self.serverPeerUUIDs[entry.userId] != nil {
                                // 既存のセッションがあるのでスキップ
                                continue
                            }

                            // 新しいピア → セッション開始
                            let peerUUID = UUID()
                            self.serverPeerUUIDs[entry.userId] = peerUUID

                            // 距離トラッキング用
                            self.peerDistances[peerUUID] = nil

                            self.nearbyManager.startSession(with: peerUUID, peerToken: entry.token)
                            print("📡 New session for: \(entry.displayName)")
                        }

                        // 退出したピアのセッションを停止
                        let exitedUserIds = Set(self.serverPeerUUIDs.keys).subtracting(currentUserIds)
                        for userId in exitedUserIds {
                            if let peerUUID = self.serverPeerUUIDs[userId] {
                                self.nearbyManager.stopSession(for: peerUUID)
                                self.peerDistances.removeValue(forKey: peerUUID)
                                self.serverPeerUUIDs.removeValue(forKey: userId)
                                print("👋 Session ended for userId: \(userId)")
                            }
                        }
                    }
                } catch {
                    print("⚠️ Polling error: \(error)")
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopSurechigaiMode() {
        // 共通の停止処理
        nearbyManager.stopAllSessions()
        liveActivityManager.stopActivity()
        surechigaiDetector.reset()

        // モード別の停止処理
        switch connectionMode {
        case .multipeer:
            multipeerManager.stop()
        case .server:
            pollingTask?.cancel()
            pollingTask = nil
            serverPeers = []
            Task {
                try? await tokenClient.unregisterToken()
                await tokenClient.leaveRoom()
            }
        }

        // 状態リセット
        peerMapping.removeAll()
        serverPeerUUIDs.removeAll()
        peerDistances.removeAll()
        nearbyPeerDetails.removeAll()
        connectedPeerCount = 0
        nearbyPeerCount = 0
        statusMessage = "モードがOFFです"

        print("🔴 Surechigai mode stopped")
    }

    private func setupBindings() {
        // 接続ピア数の購読
        multipeerManager.$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self = self else { return }
                if self.connectionMode == .multipeer {
                    self.connectedPeerCount = peers.count
                }
                self.updateStatusMessage()
            }
            .store(in: &cancellables)

        // discoveryToken受信時
        multipeerManager.onTokenReceived = { [weak self] mcPeerID, token in
            guard let self = self else { return }
            Task { @MainActor in
                let uuid = self.multipeerManager.getUUID(for: mcPeerID)

                // Peer を作成/更新
                let peer = Peer(
                    id: uuid,
                    displayName: mcPeerID.displayName,
                    discoveryToken: token
                )
                self.peerMapping[mcPeerID] = peer

                // NISession開始
                self.nearbyManager.startSession(with: uuid, peerToken: token)
            }
        }

        // 測定結果の購読 → すれ違い判定
        nearbyManager.onMeasurementUpdated = { [weak self] peerId, measurement in
            guard let self = self else { return }
            Task { @MainActor in
                // Peer名を取得（Multipeerモード or サーバーモード）
                let peerName = self.getPeerName(for: peerId)

                // 距離を記録
                if let distance = measurement.distance {
                    self.peerDistances[peerId] = distance
                    self.updateNearbyPeerDetails()
                }

                // すれ違い判定
                self.surechigaiDetector.processMeasurement(
                    peerId: peerId,
                    peerName: peerName,
                    measurement: measurement,
                    roomName: self.roomName.isEmpty ? nil : self.roomName
                )
            }
        }

        // ピア削除時
        nearbyManager.onPeerRemoved = { [weak self] peerId in
            guard let self = self else { return }
            Task { @MainActor in
                self.surechigaiDetector.removePeer(peerId)
                self.peerDistances.removeValue(forKey: peerId)
                self.updateNearbyPeerDetails()
            }
        }

        // 近くにいるピア数の購読
        surechigaiDetector.$nearbyPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self = self else { return }
                self.nearbyPeerCount = peers.count
                self.updateStatusMessage()
                self.updateNearbyPeerDetails()
            }
            .store(in: &cancellables)

        // すれ違い検出時
        surechigaiDetector.onSurechigaiDetected = { [weak self] record in
            guard let self = self else { return }
            Task { @MainActor in
                // ログに保存
                self.surechigaiLogger.addRecord(record)

                // カウント更新
                self.todaySurechigaiCount = self.surechigaiLogger.todayUniqueCount

                // 最新のすれ違いを更新
                self.latestSurechigai = record

                // Live Activity更新
                self.liveActivityManager.updateActivity(
                    surechigaiCount: self.todaySurechigaiCount,
                    lastSurechigaiTime: record.timestamp
                )

                // ローカル通知を送る
                if self.notificationsEnabled {
                    self.sendNotification(for: record)
                }

                // バイブレーション
                if self.hapticEnabled {
                    self.triggerHaptic()
                }
            }
        }

        // Live Activity状態
        liveActivityManager.$isActivityRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLiveActivityRunning)

        // 今日のカウント
        surechigaiLogger.$todayUniqueCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$todaySurechigaiCount)

        // エラーの購読
        nearbyManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .assign(to: &$errorMessage)
    }

    private func updateNearbyPeerDetails() {
        var details: [NearbyPeerInfo] = []

        for peerId in surechigaiDetector.nearbyPeers {
            let name = getPeerName(for: peerId)
            let distance = peerDistances[peerId]

            details.append(NearbyPeerInfo(
                id: peerId,
                displayName: name,
                distance: distance,
                isInRange: true
            ))
        }

        nearbyPeerDetails = details.sorted { ($0.distance ?? Float.infinity) < ($1.distance ?? Float.infinity) }
    }

    /// ピアIDから表示名を取得（Multipeerモード / サーバーモード両対応）
    private func getPeerName(for peerId: UUID) -> String {
        // Multipeerモード: peerMappingから検索
        if let name = peerMapping.values.first(where: { $0.id == peerId })?.displayName {
            return name
        }

        // サーバーモード: serverPeerUUIDsからuserIdを逆引きして、serverPeersから名前を取得
        if let userId = serverPeerUUIDs.first(where: { $0.value == peerId })?.key,
           let entry = serverPeers.first(where: { $0.userId == userId }) {
            return entry.displayName
        }

        return "Unknown"
    }

    private func sendNotification(for record: SurechigaiRecord) {
        let content = UNMutableNotificationContent()
        content.title = "すれ違い検出 🎉"
        content.body = "\(record.peerDisplayName)さんとすれ違いました（\(record.formattedDistance)）"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: record.id.uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification error: \(error)")
            }
        }
    }

    private func triggerHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func updateStatusMessage() {
        if !isModeEnabled {
            statusMessage = "モードがOFFです"
        } else if connectedPeerCount == 0 {
            statusMessage = connectionMode == .multipeer ? "ピアを検索中..." : "ルームで待機中..."
        } else if nearbyPeerCount > 0 {
            statusMessage = "\(nearbyPeerCount)人が近くにいます"
        } else {
            statusMessage = "\(connectedPeerCount)人と接続中"
        }
    }

    // MARK: - Settings Persistence

    private func saveSettings() {
        let settings = SurechigaiSettings(
            thresholdDistance: thresholdDistance,
            thresholdDuration: thresholdDuration,
            cooldownDuration: cooldownDuration,
            notificationsEnabled: notificationsEnabled,
            hapticEnabled: hapticEnabled,
            connectionMode: connectionMode,
            serverURL: serverURL,
            displayName: displayName
        )

        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(SurechigaiSettings.self, from: data) else {
            return
        }

        thresholdDistance = settings.thresholdDistance
        thresholdDuration = settings.thresholdDuration
        cooldownDuration = settings.cooldownDuration
        notificationsEnabled = settings.notificationsEnabled
        hapticEnabled = settings.hapticEnabled
        connectionMode = settings.connectionMode
        serverURL = settings.serverURL
        if let savedName = settings.displayName, !savedName.isEmpty {
            displayName = savedName
        }

        // Detectorにも反映
        surechigaiDetector.thresholdDistance = thresholdDistance
        surechigaiDetector.thresholdDuration = thresholdDuration
        surechigaiDetector.cooldownDuration = cooldownDuration
    }
}

// MARK: - Supporting Types

/// 近くにいるピアの情報
struct NearbyPeerInfo: Identifiable {
    let id: UUID
    let displayName: String
    let distance: Float?
    let isInRange: Bool

    var formattedDistance: String {
        guard let dist = distance else { return "---" }
        if dist < 1.0 {
            return String(format: "%.0f cm", dist * 100)
        } else {
            return String(format: "%.1f m", dist)
        }
    }
}

/// 設定の永続化用構造体
private struct SurechigaiSettings: Codable {
    let thresholdDistance: Float
    let thresholdDuration: TimeInterval
    let cooldownDuration: TimeInterval
    let notificationsEnabled: Bool
    let hapticEnabled: Bool
    let connectionMode: SurechigaiModeViewModel.ConnectionMode
    let serverURL: String
    let displayName: String?
}
