//
//  SurechigaiModeView.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import SwiftUI

/// すれ違いモード画面
/// モードのON/OFF、設定、ステータス表示
struct SurechigaiModeView: View {
    @StateObject private var viewModel = SurechigaiModeViewModel()
    @State private var showSettings = false
    @State private var showNearbyList = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // メインカード（ON/OFFトグル）
                    mainControlCard

                    // ステータスカード
                    statusCard

                    // 近くにいる人カード
                    if viewModel.isModeEnabled {
                        nearbyPeersCard
                    }

                    // 今日のすれ違いカード
                    todayCard

                    // 最新のすれ違い
                    if let latest = viewModel.latestSurechigai {
                        latestSurechigaiCard(latest)
                    }

                    // ルーム設定（オプション）
                    roomSettingCard
                }
                .padding()
            }
            .navigationTitle("すれ違いモード")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
            }
            .sheet(isPresented: $showNearbyList) {
                nearbyListSheet
            }
            .alert("エラー", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var mainControlCard: some View {
        VStack(spacing: 16) {
            // 接続モード表示
            HStack {
                Image(systemName: viewModel.connectionMode == .server ? "server.rack" : "wifi")
                    .foregroundStyle(.secondary)
                Text(viewModel.connectionMode.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 大きなON/OFFトグル
            ZStack {
                Circle()
                    .fill(viewModel.isModeEnabled ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .shadow(color: viewModel.isModeEnabled ? .green.opacity(0.5) : .clear, radius: 20)

                Image(systemName: viewModel.isModeEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.isModeEnabled.toggle()
                }
            }

            Text(viewModel.isModeEnabled ? "ON" : "OFF")
                .font(.title2.bold())
                .foregroundStyle(viewModel.isModeEnabled ? .green : .secondary)

            if !viewModel.isUWBSupported {
                Text("⚠️ UWB非対応デバイス")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                Text("ステータス")
                    .font(.headline)
                Spacer()
            }

            Text(viewModel.statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                StatusBadge(
                    icon: "person.2.fill",
                    value: "\(viewModel.connectedPeerCount)",
                    label: "接続中"
                )

                StatusBadge(
                    icon: "location.fill",
                    value: "\(viewModel.nearbyPeerCount)",
                    label: "近く"
                )

                if viewModel.isLiveActivityRunning {
                    StatusBadge(
                        icon: "livephoto",
                        value: "ON",
                        label: "Live"
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var nearbyPeersCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                Text("近くにいる人")
                    .font(.headline)
                Spacer()

                if !viewModel.nearbyPeerDetails.isEmpty {
                    Button {
                        showNearbyList = true
                    } label: {
                        Text("すべて表示")
                            .font(.caption)
                    }
                }
            }

            if viewModel.nearbyPeerDetails.isEmpty {
                HStack {
                    Image(systemName: "person.slash")
                        .foregroundStyle(.secondary)
                    Text("近くにいる人はいません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(viewModel.nearbyPeerDetails.prefix(3)) { peer in
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)
                        Text(peer.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(peer.formattedDistance)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var todayCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                Text("今日のすれ違い")
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(viewModel.todaySurechigaiCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("人")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func latestSurechigaiCard(_ record: SurechigaiRecord) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                Text("最新のすれ違い")
                    .font(.headline)
                Spacer()
                Text(record.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.peerDisplayName)
                        .font(.title3.bold())
                    Text("距離: \(record.formattedDistance)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.green.opacity(0.1), .blue.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var roomSettingCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "door.left.hand.open")
                Text("ルーム/イベント")
                    .font(.headline)
                Spacer()
            }

            TextField("ルーム名（オプション）", text: $viewModel.roomName)
                .textFieldStyle(.roundedBorder)
                .disabled(viewModel.isModeEnabled)

            Text("同じルーム名の人とのすれ違いをグループ化できます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Nearby List Sheet

    private var nearbyListSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.nearbyPeerDetails) { peer in
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(peer.displayName)
                                .font(.headline)
                            Text("距離: \(peer.formattedDistance)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("近くにいる人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        showNearbyList = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                // 表示名
                Section("プロフィール") {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                        TextField("表示名", text: $viewModel.displayName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(viewModel.isModeEnabled)
                    }
                    Text("他のユーザーに表示される名前です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 接続モード
                Section("接続モード") {
                    Picker("モード", selection: $viewModel.connectionMode) {
                        ForEach(SurechigaiModeViewModel.ConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.isModeEnabled)

                    if viewModel.connectionMode == .server {
                        HStack {
                            Text("サーバーURL")
                            TextField("http://...", text: $viewModel.serverURL)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.URL)
                                .disabled(viewModel.isModeEnabled)
                        }
                    }
                }

                // すれ違い判定条件
                Section("すれ違い判定条件") {
                    VStack(alignment: .leading) {
                        Text("判定距離: \(String(format: "%.1f", viewModel.thresholdDistance)) m")
                        Slider(value: $viewModel.thresholdDistance, in: 1...10, step: 0.5)
                    }

                    VStack(alignment: .leading) {
                        Text("判定時間: \(Int(viewModel.thresholdDuration)) 秒")
                        Slider(value: $viewModel.thresholdDuration, in: 1...10, step: 1)
                    }

                    VStack(alignment: .leading) {
                        Text("クールダウン: \(Int(viewModel.cooldownDuration)) 秒")
                        Slider(value: $viewModel.cooldownDuration, in: 10...300, step: 10)
                    }
                }

                // 通知設定
                Section("通知") {
                    Toggle("すれ違い時に通知", isOn: $viewModel.notificationsEnabled)
                    Toggle("バイブレーション", isOn: $viewModel.hapticEnabled)
                }

                // 説明
                Section {
                    Text("・判定距離以内に入り、判定時間以上近くにいるとすれ違いとして記録されます")
                    Text("・同じ人との連続検出を防ぐため、クールダウン時間が設定されています")
                    Text("・サーバー経由モードでは、同じルームの人同士がすれ違いを検出できます")
                } header: {
                    Text("説明")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        showSettings = false
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatusBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    SurechigaiModeView()
}
