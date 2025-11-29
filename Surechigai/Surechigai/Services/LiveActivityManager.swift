//
//  LiveActivityManager.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import ActivityKit
import Combine

/// Live Activity の制御を担当
/// iOS 18.4+ でバックグラウンドでのUWB測距を継続するために必要
@MainActor
final class LiveActivityManager: ObservableObject {

    // MARK: - Published Properties

    /// Live Activity が実行中かどうか
    @Published private(set) var isActivityRunning = false

    /// 現在のすれ違いカウント（Activity表示用）
    @Published var surechigaiCount: Int = 0

    /// エラーメッセージ
    @Published var errorMessage: String?

    // MARK: - Private Properties

    // 実際のActivity（SurechigaiWidgetExtensionで定義が必要）
    // private var currentActivity: Activity<SurechigaiActivityAttributes>?

    // MARK: - Singleton

    static let shared = LiveActivityManager()

    private init() {}

    // MARK: - Public Methods

    /// Live Activity がサポートされているか
    var isSupported: Bool {
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// Live Activity を開始
    /// - Parameter roomName: ルーム/イベント名
    func startActivity(roomName: String) {
        guard isSupported else {
            errorMessage = "Live Activityがサポートされていません"
            return
        }

        // TODO: 実際のActivity開始ロジック
        // Widget Extension で SurechigaiActivityAttributes を定義後に実装

        /*
        if #available(iOS 16.2, *) {
            let attributes = SurechigaiActivityAttributes(roomName: roomName)
            let state = SurechigaiActivityAttributes.ContentState(
                surechigaiCount: 0,
                lastSurechigaiTime: nil
            )

            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                isActivityRunning = true
                print("🟢 Live Activity started")
            } catch {
                print("❌ Failed to start Live Activity: \(error)")
                errorMessage = error.localizedDescription
            }
        }
        */

        // 仮実装（Activity未定義の間）
        isActivityRunning = true
        print("🟢 Live Activity started (mock)")
    }

    /// Live Activity を更新
    func updateActivity(surechigaiCount: Int, lastSurechigaiTime: Date?) {
        guard isActivityRunning else { return }

        self.surechigaiCount = surechigaiCount

        // TODO: 実際のActivity更新ロジック
        /*
        if #available(iOS 16.2, *) {
            Task {
                let state = SurechigaiActivityAttributes.ContentState(
                    surechigaiCount: surechigaiCount,
                    lastSurechigaiTime: lastSurechigaiTime
                )
                await currentActivity?.update(
                    ActivityContent(state: state, staleDate: nil)
                )
            }
        }
        */

        print("🔄 Live Activity updated: count=\(surechigaiCount)")
    }

    /// Live Activity を終了
    func stopActivity() {
        guard isActivityRunning else { return }

        // TODO: 実際のActivity終了ロジック
        /*
        if #available(iOS 16.2, *) {
            Task {
                await currentActivity?.end(nil, dismissalPolicy: .immediate)
                currentActivity = nil
            }
        }
        */

        isActivityRunning = false
        print("🔴 Live Activity stopped")
    }
}

// MARK: - Activity Attributes（Widget Extension側で定義）
// ※実際のWidget Extensionを追加した時にそちらに移動

/*
import ActivityKit

struct SurechigaiActivityAttributes: ActivityAttributes {
    /// 固定のコンテキスト
    let roomName: String

    /// 動的な状態
    struct ContentState: Codable, Hashable {
        let surechigaiCount: Int
        let lastSurechigaiTime: Date?
    }
}
*/
