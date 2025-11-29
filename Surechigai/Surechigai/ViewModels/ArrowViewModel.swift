//
//  ArrowViewModel.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine

/// Arrow Demo 画面のViewModel
/// 1対1でピアの方向・距離をリアルタイム表示
@MainActor
final class ArrowViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 接続中のピア
    @Published private(set) var connectedPeer: Peer?

    /// 現在の距離（メートル）
    @Published private(set) var distance: Float?

    /// 現在の方向（ラジアン）水平面での角度
    @Published private(set) var directionAngle: Float?

    /// 接続状態
    @Published private(set) var connectionState: ConnectionState = .idle

    /// UWBがサポートされているか
    @Published private(set) var isUWBSupported: Bool = false

    /// エラーメッセージ
    @Published var errorMessage: String?

    /// 発見されたピア一覧
    @Published private(set) var discoveredPeers: [MCPeerID] = []

    /// サーバー経由で発見されたピア一覧
    @Published private(set) var serverPeers: [TokenEntry] = []

    /// 接続モード
    @Published var connectionMode: ConnectionMode = .multipeer

    /// サーバーURL（サーバーモード用）
    @Published var serverURL: String = "http://192.168.1.1:3000"

    /// ルーム名（サーバーモード用）
    @Published var roomName: String = "demo"

    /// 自分の表示名
    @Published var displayName: String = UIDevice.current.name

    /// 接続モードの種類
    enum ConnectionMode: String, CaseIterable {
        case multipeer = "ローカル (Multipeer)"
        case server = "サーバー経由"
    }

    enum ConnectionState: String {
        case idle = "待機中"
        case searching = "検索中..."
        case connecting = "接続中..."
        case connected = "接続済み"
        case measuring = "測距中"
        case polling = "ルーム待機中..."
    }

    // MARK: - Private Properties

    private let nearbyManager = NearbySessionManager.shared
    private let multipeerManager = MultipeerManager.shared
    private let tokenClient = TokenAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

    private var currentPeerMCID: MCPeerID?
    private var pollingTask: Task<Void, Never>?
    private var userId: String = UUID().uuidString

    // MARK: - Initialization

    init() {
        isUWBSupported = nearbyManager.isSupported
        setupBindings()
    }

    // MARK: - Public Methods

    /// 検索を開始
    func startSearching() {
        guard isUWBSupported else {
            errorMessage = "このデバイスはUWBをサポートしていません"
            return
        }

        switch connectionMode {
        case .multipeer:
            startMultipeerSearching()
        case .server:
            startServerMode()
        }
    }

    /// 検索・接続を停止
    func stopSearching() {
        // 共通の停止処理
        nearbyManager.stopAllSessions()
        connectedPeer = nil
        distance = nil
        directionAngle = nil

        switch connectionMode {
        case .multipeer:
            multipeerManager.stop()
        case .server:
            stopServerMode()
        }

        connectionState = .idle
    }

    /// Multipeer: 特定のピアに接続
    func connectToPeer(_ peerID: MCPeerID) {
        multipeerManager.invitePeer(peerID)
        connectionState = .connecting
    }

    // MARK: - Multipeer Mode

    private func startMultipeerSearching() {
        multipeerManager.setup(displayName: displayName)
        multipeerManager.start()
        connectionState = .searching
    }

    // MARK: - Server Mode

    private func startServerMode() {
        guard let url = URL(string: serverURL) else {
            errorMessage = "無効なサーバーURLです"
            return
        }

        connectionState = .connecting

        Task {
            do {
                // サーバーに接続設定
                await tokenClient.configure(baseURL: url, userId: userId)
                await tokenClient.setDisplayName(displayName)
                await tokenClient.joinRoom(roomName)

                // 自分のトークンを生成して登録
                let myToken = nearbyManager.generateDiscoveryToken()
                if let token = myToken {
                    try await tokenClient.registerToken(token)
                    print("✅ 自分のトークンを登録しました")
                } else {
                    errorMessage = "Discovery Token の生成に失敗しました"
                    connectionState = .idle
                    return
                }

                connectionState = .polling
                startPolling()

            } catch {
                errorMessage = "サーバー接続に失敗: \(error.localizedDescription)"
                connectionState = .idle
            }
        }
    }

    private func stopServerMode() {
        pollingTask?.cancel()
        pollingTask = nil
        serverPeers = []

        Task {
            try? await tokenClient.unregisterToken()
            await tokenClient.leaveRoom()
        }
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let tokens = try await tokenClient.fetchTokens()
                    await MainActor.run {
                        self.serverPeers = tokens
                    }
                } catch {
                    print("⚠️ Polling error: \(error)")
                }

                // 3秒ごとにポーリング（ただし接続済みならより長く）
                let interval: UInt64 = self.connectionState == .measuring ? 10_000_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    /// Server: 特定のピアに接続（重複接続防止）
    func connectToServerPeer(_ entry: TokenEntry) {
        // 既に接続中の場合はスキップ
        if connectionState == .measuring {
            print("⚠️ Already connected, skipping")
            return
        }

        // NIセッションを開始
        let peerUUID = UUID()
        nearbyManager.startSession(with: peerUUID, peerToken: entry.token)

        connectedPeer = Peer(
            id: peerUUID,
            displayName: entry.displayName
        )
        connectedPeer?.discoveryToken = entry.token

        connectionState = .measuring
    }

    /// 距離の表示用フォーマット
    var formattedDistance: String {
        guard let dist = distance else { return "---" }
        if dist < 1.0 {
            return String(format: "%.0f cm", dist * 100)
        } else {
            return String(format: "%.2f m", dist)
        }
    }

    /// 方向が取れているか
    var hasDirection: Bool {
        directionAngle != nil
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Multipeerの発見ピアを購読
        multipeerManager.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredPeers)

        // 接続ピアの変化を購読
        multipeerManager.$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                guard let self = self else { return }
                if let firstPeer = peers.first {
                    self.currentPeerMCID = firstPeer
                    self.connectionState = .connected

                    // Peer オブジェクトを作成
                    let uuid = self.multipeerManager.getUUID(for: firstPeer)
                    self.connectedPeer = Peer(
                        id: uuid,
                        displayName: firstPeer.displayName
                    )
                } else {
                    self.currentPeerMCID = nil
                    self.connectedPeer = nil
                    if self.connectionState != .idle && self.connectionState != .searching {
                        self.connectionState = .searching
                    }
                }
            }
            .store(in: &cancellables)

        // discoveryToken受信時の処理
        multipeerManager.onTokenReceived = { [weak self] peerID, token in
            guard let self = self else { return }
            Task { @MainActor in
                let uuid = self.multipeerManager.getUUID(for: peerID)
                self.nearbyManager.startSession(with: uuid, peerToken: token)
                self.connectionState = .measuring

                // Peer の token を更新
                self.connectedPeer?.discoveryToken = token
            }
        }

        // 測定結果の購読
        nearbyManager.$measurements
            .receive(on: DispatchQueue.main)
            .sink { [weak self] measurements in
                guard let self = self,
                      let peer = self.connectedPeer,
                      let measurement = measurements[peer.id] else { return }

                self.distance = measurement.distance
                self.directionAngle = measurement.horizontalAngleRadians
            }
            .store(in: &cancellables)

        // エラーの購読
        nearbyManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .assign(to: &$errorMessage)

        multipeerManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .assign(to: &$errorMessage)
    }
}
