//
//  HistoryView.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import SwiftUI

/// 履歴画面
/// すれ違いログの一覧表示
struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 今日のサマリー
                todaySummaryHeader

                // セグメントピッカー
                Picker("表示", selection: $viewModel.displayMode) {
                    ForEach(HistoryViewModel.DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // コンテンツ
                contentView
            }
            .navigationTitle("履歴")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("すべて削除", systemImage: "trash")
                        }

                        Button {
                            viewModel.deleteOldRecords(olderThanDays: 30)
                        } label: {
                            Label("30日以上前を削除", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "すべての履歴を削除しますか？",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    viewModel.deleteAllRecords()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は取り消せません")
            }
            .refreshable {
                viewModel.refresh()
            }
        }
    }

    // MARK: - Subviews

    private var todaySummaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(viewModel.todayUniqueCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("人とすれ違い")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "figure.walk")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.1), .purple.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.displayMode {
        case .today:
            recordsList(viewModel.todayRecords)
        case .all:
            recordsList(viewModel.allRecords)
        case .summary:
            summaryList
        }
    }

    private func recordsList(_ records: [SurechigaiRecord]) -> some View {
        Group {
            if records.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(records) { record in
                        RecordRow(record: record)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteRecord(records[index])
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var summaryList: some View {
        Group {
            if viewModel.dailySummary.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.dailySummary) { summary in
                        SummaryRow(summary: summary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("まだ履歴がありません")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("すれ違いモードをONにして\n近くにいる人を検出しましょう")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Supporting Views

struct RecordRow: View {
    let record: SurechigaiRecord

    var body: some View {
        HStack(spacing: 12) {
            // アイコン
            Circle()
                .fill(.blue.gradient)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(record.peerDisplayName.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            // 情報
            VStack(alignment: .leading, spacing: 4) {
                Text(record.peerDisplayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(record.formattedTime, systemImage: "clock")
                    Label(record.formattedDistance, systemImage: "arrow.left.and.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // ルーム名（あれば）
            if let roomName = record.roomName {
                Text(roomName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

struct SummaryRow: View {
    let summary: DailySummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(summary.formattedDate)
                        .font(.headline)
                    if summary.isToday {
                        Text("今日")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                Text("\(summary.totalCount)回のすれ違い")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(summary.uniquePeerCount)")
                    .font(.title2.bold())
                Text("人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HistoryView()
}
