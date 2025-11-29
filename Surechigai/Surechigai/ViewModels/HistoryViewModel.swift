//
//  HistoryViewModel.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import Foundation
import Combine

/// 履歴画面のViewModel
/// すれ違いログの表示・管理
@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 今日のログ
    @Published private(set) var todayRecords: [SurechigaiRecord] = []

    /// 全ログ
    @Published private(set) var allRecords: [SurechigaiRecord] = []

    /// 日別サマリー
    @Published private(set) var dailySummary: [DailySummary] = []

    /// 今日のユニークすれ違い人数
    @Published private(set) var todayUniqueCount: Int = 0

    /// 表示モード
    @Published var displayMode: DisplayMode = .today

    enum DisplayMode: String, CaseIterable {
        case today = "今日"
        case all = "すべて"
        case summary = "サマリー"
    }

    // MARK: - Private Properties

    private let logger = SurechigaiLogger.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupBindings()
        refresh()
    }

    // MARK: - Public Methods

    /// データを更新
    func refresh() {
        todayRecords = logger.todayRecords
        allRecords = logger.allRecords
        todayUniqueCount = logger.todayUniqueCount
        updateDailySummary()
    }

    /// レコードを削除
    func deleteRecord(_ record: SurechigaiRecord) {
        logger.deleteRecord(record)
        refresh()
    }

    /// 全レコードを削除
    func deleteAllRecords() {
        logger.deleteAllRecords()
        refresh()
    }

    /// 古いレコードを削除
    func deleteOldRecords(olderThanDays days: Int) {
        logger.deleteOldRecords(olderThanDays: days)
        refresh()
    }

    // MARK: - Private Methods

    private func setupBindings() {
        logger.$allRecords
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func updateDailySummary() {
        let summary = logger.dailySummary()
        dailySummary = summary.map { item in
            DailySummary(
                date: item.date,
                totalCount: item.count,
                uniquePeerCount: item.uniquePeers
            )
        }
    }
}

// MARK: - Supporting Types

struct DailySummary: Identifiable {
    var id: Date { date }
    let date: Date
    let totalCount: Int
    let uniquePeerCount: Int

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d (E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}
