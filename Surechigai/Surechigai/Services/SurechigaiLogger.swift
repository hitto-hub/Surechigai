//
//  SurechigaiLogger.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import Combine

/// すれ違いログの保存・取得を担当
/// ローカルストレージ（JSON）でログを永続化
@MainActor
final class SurechigaiLogger: ObservableObject {

    // MARK: - Published Properties

    /// 全ログ
    @Published private(set) var allRecords: [SurechigaiRecord] = []

    /// 今日のログ
    @Published private(set) var todayRecords: [SurechigaiRecord] = []

    /// 今日のすれ違い人数（ユニーク）
    @Published private(set) var todayUniqueCount: Int = 0

    // MARK: - Private Properties

    private let fileManager = FileManager.default
    private var logFileURL: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("surechigai_logs.json")
    }

    // MARK: - Singleton

    static let shared = SurechigaiLogger()

    private init() {
        loadRecords()
    }

    // MARK: - Public Methods

    /// ログを追加
    func addRecord(_ record: SurechigaiRecord) {
        allRecords.insert(record, at: 0) // 新しいものを先頭に
        updateTodayRecords()
        saveRecords()
        print("💾 Saved surechigai record: \(record.peerDisplayName)")
    }

    /// 特定日のログを取得
    func records(for date: Date) -> [SurechigaiRecord] {
        let calendar = Calendar.current
        return allRecords.filter { record in
            calendar.isDate(record.timestamp, inSameDayAs: date)
        }
    }

    /// 日別の集計を取得
    func dailySummary() -> [(date: Date, count: Int, uniquePeers: Int)] {
        let calendar = Calendar.current
        var summaryDict: [Date: (count: Int, peers: Set<UUID>)] = [:]

        for record in allRecords {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            if var existing = summaryDict[dayStart] {
                existing.count += 1
                existing.peers.insert(record.peerId)
                summaryDict[dayStart] = existing
            } else {
                summaryDict[dayStart] = (count: 1, peers: [record.peerId])
            }
        }

        return summaryDict
            .map { (date: $0.key, count: $0.value.count, uniquePeers: $0.value.peers.count) }
            .sorted { $0.date > $1.date }
    }

    /// 特定ピアとのすれ違い履歴を取得
    func records(for peerId: UUID) -> [SurechigaiRecord] {
        allRecords.filter { $0.peerId == peerId }
    }

    /// ログを削除
    func deleteRecord(_ record: SurechigaiRecord) {
        allRecords.removeAll { $0.id == record.id }
        updateTodayRecords()
        saveRecords()
    }

    /// 全ログを削除
    func deleteAllRecords() {
        allRecords.removeAll()
        todayRecords.removeAll()
        todayUniqueCount = 0
        saveRecords()
    }

    /// 古いログを削除（指定日数より前）
    func deleteOldRecords(olderThanDays days: Int) {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else { return }

        let originalCount = allRecords.count
        allRecords.removeAll { $0.timestamp < cutoffDate }
        let deletedCount = originalCount - allRecords.count

        if deletedCount > 0 {
            updateTodayRecords()
            saveRecords()
            print("🗑 Deleted \(deletedCount) old records")
        }
    }

    // MARK: - Private Methods

    private func loadRecords() {
        guard fileManager.fileExists(atPath: logFileURL.path) else {
            print("📂 No existing log file")
            return
        }

        do {
            let data = try Data(contentsOf: logFileURL)
            let decoder = JSONDecoder()
            allRecords = try decoder.decode([SurechigaiRecord].self, from: data)
            updateTodayRecords()
            print("📂 Loaded \(allRecords.count) records")
        } catch {
            print("❌ Failed to load records: \(error)")
        }
    }

    private func saveRecords() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(allRecords)
            try data.write(to: logFileURL)
        } catch {
            print("❌ Failed to save records: \(error)")
        }
    }

    private func updateTodayRecords() {
        let calendar = Calendar.current
        let today = Date()

        todayRecords = allRecords.filter { record in
            calendar.isDate(record.timestamp, inSameDayAs: today)
        }

        // ユニークなピア数をカウント
        let uniquePeers = Set(todayRecords.map { $0.peerId })
        todayUniqueCount = uniquePeers.count
    }
}
