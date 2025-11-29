//
//  TokenAPIClient.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import NearbyInteraction

/// サーバーとの discoveryToken 交換を担当
/// REST API で token の登録・取得を行う
actor TokenAPIClient {

    // MARK: - Configuration

    /// APIのベースURL
    var baseURL: URL?

    /// 現在のユーザーID
    var userId: String?

    /// 表示名
    var displayName: String?

    /// 現在のルーム/イベント名
    var currentRoom: String?

    // MARK: - Singleton

    static let shared = TokenAPIClient()

    private init() {}

    // MARK: - Public Methods

    /// 設定を更新
    func configure(baseURL: URL, userId: String) {
        self.baseURL = baseURL
        self.userId = userId
    }

    /// 表示名を設定
    func setDisplayName(_ name: String) {
        self.displayName = name
    }

    /// ルームに参加
    func joinRoom(_ room: String) {
        self.currentRoom = room
    }

    /// ルームから退出
    func leaveRoom() {
        self.currentRoom = nil
    }

    /// 自分の discoveryToken を登録
    /// POST /ni/token
    func registerToken(_ token: NIDiscoveryToken) async throws {
        guard let baseURL = baseURL,
              let userId = userId,
              let room = currentRoom else {
            throw TokenAPIError.notConfigured
        }

        // Token をシリアライズ
        guard let tokenData = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else {
            throw TokenAPIError.serializationFailed
        }

        let base64Token = tokenData.base64EncodedString()

        // リクエスト作成
        var request = URLRequest(url: baseURL.appendingPathComponent("ni/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "userId": userId,
            "displayName": displayName ?? userId,
            "room": room,
            "token": base64Token,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 送信
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TokenAPIError.serverError
        }

        print("✅ Token registered successfully")
    }

    /// ルーム内の他ユーザーの token を取得
    /// GET /ni/token?room=xxx
    func fetchTokens() async throws -> [TokenEntry] {
        guard let baseURL = baseURL,
              let userId = userId,
              let room = currentRoom else {
            throw TokenAPIError.notConfigured
        }

        // URLを作成
        var components = URLComponents(url: baseURL.appendingPathComponent("ni/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "room", value: room),
            URLQueryItem(name: "excludeUserId", value: userId)
        ]

        guard let url = components.url else {
            throw TokenAPIError.invalidURL
        }

        // リクエスト
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TokenAPIError.serverError
        }

        // パース
        let decoder = JSONDecoder()
        let tokenList = try decoder.decode(TokenListResponse.self, from: data)

        // Token をデシリアライズ
        var entries: [TokenEntry] = []
        for item in tokenList.tokens {
            guard let tokenData = Data(base64Encoded: item.token),
                  let niToken = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NIDiscoveryToken.self,
                    from: tokenData
                  ) else {
                continue
            }

            entries.append(TokenEntry(
                userId: item.userId,
                displayName: item.displayName,
                token: niToken
            ))
        }

        print("📥 Fetched \(entries.count) tokens from server")
        return entries
    }

    /// ルームから自分の token を削除
    /// DELETE /ni/token
    func unregisterToken() async throws {
        guard let baseURL = baseURL,
              let userId = userId,
              let room = currentRoom else {
            throw TokenAPIError.notConfigured
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("ni/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "room", value: room)
        ]

        guard let url = components.url else {
            throw TokenAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TokenAPIError.serverError
        }

        print("✅ Token unregistered successfully")
    }
}

// MARK: - Supporting Types

struct TokenEntry {
    let userId: String
    let displayName: String
    let token: NIDiscoveryToken
}

struct TokenListResponse: Codable {
    let tokens: [TokenItem]
}

struct TokenItem: Codable {
    let userId: String
    let displayName: String
    let token: String // Base64 encoded
}

enum TokenAPIError: Error, LocalizedError {
    case notConfigured
    case serializationFailed
    case invalidURL
    case serverError
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "APIが設定されていません"
        case .serializationFailed:
            return "Tokenのシリアライズに失敗しました"
        case .invalidURL:
            return "無効なURLです"
        case .serverError:
            return "サーバーエラーが発生しました"
        case .decodingFailed:
            return "レスポンスの解析に失敗しました"
        }
    }
}
