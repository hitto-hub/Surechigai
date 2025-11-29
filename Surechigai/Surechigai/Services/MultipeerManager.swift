//
//  MultipeerManager.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import MultipeerConnectivity
import NearbyInteraction
import Combine

/// Multipeer Connectivity を使ってピア検出・接続・discoveryToken交換を行う
@MainActor
final class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// 発見されたピア一覧
    @Published private(set) var discoveredPeers: [MCPeerID] = []

    /// 接続済みピア一覧
    @Published private(set) var connectedPeers: [MCPeerID] = []

    /// ブラウジング中かどうか
    @Published private(set) var isBrowsing = false

    /// アドバタイジング中かどうか
    @Published private(set) var isAdvertising = false

    /// エラーメッセージ
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let serviceType = "surechigai-uwb"
    private var myPeerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    /// discoveryToken を受信した時のコールバック
    var onTokenReceived: ((MCPeerID, NIDiscoveryToken) -> Void)?

    /// ピア → UUID のマッピング
    private var peerIdMapping: [MCPeerID: UUID] = [:]

    /// 自分のユニークID（Multipeer競合回避用）
    private var myUniqueId: String = ""

    // MARK: - Singleton

    static let shared = MultipeerManager()

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// 初期化（自分の表示名を設定）
    func setup(displayName: String) {
        // ユニークIDを生成（競合回避用）
        myUniqueId = String(UUID().uuidString.prefix(4))
        let uniqueDisplayName = "\(displayName)-\(myUniqueId)"

        myPeerID = MCPeerID(displayName: uniqueDisplayName)

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        browser.delegate = self

        print("📱 MultipeerManager setup: \(displayName)")
    }

    /// ピア検出・接続受付を開始
    func start() {
        startAdvertising()
        startBrowsing()
    }

    /// ピア検出・接続受付を停止
    func stop() {
        stopAdvertising()
        stopBrowsing()
        session.disconnect()
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
    }

    /// アドバタイジング開始
    func startAdvertising() {
        advertiser.startAdvertisingPeer()
        isAdvertising = true
        print("📢 Started advertising")
    }

    /// アドバタイジング停止
    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
        print("🔇 Stopped advertising")
    }

    /// ブラウジング開始
    func startBrowsing() {
        browser.startBrowsingForPeers()
        isBrowsing = true
        print("🔍 Started browsing")
    }

    /// ブラウジング停止
    func stopBrowsing() {
        browser.stopBrowsingForPeers()
        isBrowsing = false
        print("🔍 Stopped browsing")
    }

    /// ピアに接続をリクエスト
    func invitePeer(_ peerID: MCPeerID) {
        browser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 30
        )
        print("📨 Invited peer: \(peerID.displayName)")
    }

    /// discoveryToken を接続済み全ピアに送信
    func sendDiscoveryToken(_ token: NIDiscoveryToken) {
        guard !connectedPeers.isEmpty else { return }

        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else {
            print("❌ Failed to serialize discovery token")
            return
        }

        do {
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            print("📤 Sent discovery token to \(connectedPeers.count) peers")
        } catch {
            print("❌ Failed to send token: \(error)")
            errorMessage = "Token送信に失敗: \(error.localizedDescription)"
        }
    }

    /// 特定ピアに discoveryToken を送信
    func sendDiscoveryToken(_ token: NIDiscoveryToken, to peerID: MCPeerID) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else {
            print("❌ Failed to serialize discovery token")
            return
        }

        do {
            try session.send(data, toPeers: [peerID], with: .reliable)
            print("📤 Sent discovery token to \(peerID.displayName)")
        } catch {
            print("❌ Failed to send token: \(error)")
        }
    }

    /// MCPeerID から UUID を取得（なければ作成）
    func getUUID(for peerID: MCPeerID) -> UUID {
        if let uuid = peerIdMapping[peerID] {
            return uuid
        }
        let uuid = UUID()
        peerIdMapping[peerID] = uuid
        return uuid
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                connectedPeers.removeAll { $0 == peerID }
            case .connecting:
                print("🔄 Connecting to: \(peerID.displayName)")
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                // 接続したら discoveryToken を送信
                if let token = NearbySessionManager.shared.myDiscoveryToken {
                    sendDiscoveryToken(token, to: peerID)
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            // discoveryToken の受信を試みる
            if let token = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NIDiscoveryToken.self,
                from: data
            ) {
                print("📥 Received discovery token from: \(peerID.displayName)")
                onTokenReceived?(peerID, token)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // 未使用
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // 未使用
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // 未使用
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("📨 Received invitation from: \(peerID.displayName)")
            // 自動で招待を受け入れる
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("❌ Failed to start advertising: \(error)")
            errorMessage = "アドバタイジング開始に失敗: \(error.localizedDescription)"
            isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            print("🔍 Found peer: \(peerID.displayName)")
            if !discoveredPeers.contains(peerID) {
                discoveredPeers.append(peerID)
            }

            // 招待の競合を避けるため、辞書順で小さい方だけが招待を送る
            // 両方から招待を送ると接続が不安定になる
            if myPeerID.displayName < peerID.displayName {
                print("📨 I will invite (my name < peer name)")
                invitePeer(peerID)
            } else {
                print("⏳ Waiting for invitation (my name > peer name)")
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("👋 Lost peer: \(peerID.displayName)")
            discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("❌ Failed to start browsing: \(error)")
            errorMessage = "ブラウジング開始に失敗: \(error.localizedDescription)"
            isBrowsing = false
        }
    }
}
