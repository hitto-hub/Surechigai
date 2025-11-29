//
//  ArrowDemoView.swift
//  Surechigai
//
//  Created on 2025/11/29.
//

import SwiftUI
import MultipeerConnectivity

/// Arrow Demo 画面
/// 1対1でピアの方向・距離を矢印で表示
struct ArrowDemoView: View {
    @StateObject private var viewModel = ArrowViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 状態表示
                statusSection

                Spacer()

                // 矢印 & 距離表示
                if viewModel.connectionState == .measuring {
                    arrowSection
                } else {
                    waitingSection
                }

                Spacer()

                // 接続情報
                connectionInfoSection

                // 開始/停止ボタン
                controlButton
            }
            .padding()
            .navigationTitle("Arrow Demo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .disabled(viewModel.connectionState != .idle)
                }
            }
            .sheet(isPresented: $showSettings) {
                settingsSheet
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

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("プロフィール") {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                        TextField("表示名", text: $viewModel.displayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("他のユーザーに表示される名前です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("接続モード") {
                    Picker("モード", selection: $viewModel.connectionMode) {
                        ForEach(ArrowViewModel.ConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.connectionMode == .server {
                    Section("サーバー設定") {
                        HStack {
                            Text("URL")
                            TextField("http://192.168.1.1:3000", text: $viewModel.serverURL)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .keyboardType(.URL)
                        }

                        HStack {
                            Text("ルーム")
                            TextField("demo", text: $viewModel.roomName)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                        }
                    }

                    Section {
                        Text("サーバー経由モードでは、同じルーム名を設定した端末同士がUWBで接続できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("ローカルモードでは、近くの端末を自動的に検出してUWBで接続します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .presentationDetents([.medium])
    }

    // MARK: - Subviews

    private var statusSection: some View {
        VStack(spacing: 8) {
            // 接続モード表示
            HStack {
                Image(systemName: viewModel.connectionMode == .server ? "server.rack" : "wifi")
                    .foregroundStyle(.secondary)
                Text(viewModel.connectionMode.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(viewModel.connectionState.rawValue)
                    .font(.headline)
            }

            if !viewModel.isUWBSupported {
                Text("⚠️ このデバイスはUWBをサポートしていません")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .idle: return .gray
        case .searching: return .yellow
        case .connecting: return .orange
        case .connected: return .blue
        case .measuring: return .green
        case .polling: return .purple
        }
    }

    private var arrowSection: some View {
        VStack(spacing: 16) {
            // 矢印
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 200, height: 200)

                if let angle = viewModel.directionAngle {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(.blue)
                        .rotationEffect(.radians(Double(angle)))
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray)
                }
            }

            // 距離
            VStack(spacing: 4) {
                Text(viewModel.formattedDistance)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if !viewModel.hasDirection {
                    Text("方向を取得できません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var waitingSection: some View {
        VStack(spacing: 16) {
            if viewModel.connectionState == .polling {
                // サーバーモード：ルーム待機中
                Image(systemName: "server.rack")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("ルーム「\(viewModel.roomName)」で待機中...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // サーバーから取得したピア
                if !viewModel.serverPeers.isEmpty {
                    VStack(spacing: 8) {
                        Text("ルーム内のデバイス:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.serverPeers, id: \.userId) { peer in
                            Button {
                                viewModel.connectToServerPeer(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text(peer.displayName)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            } else {
                // Multipeerモード：検索中
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("ピアを検索しています...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // 発見されたピア
                if !viewModel.discoveredPeers.isEmpty {
                    VStack(spacing: 8) {
                        Text("発見されたデバイス:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.discoveredPeers, id: \.displayName) { peer in
                            Button {
                                viewModel.connectToPeer(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text(peer.displayName)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var connectionInfoSection: some View {
        Group {
            if let peer = viewModel.connectedPeer {
                HStack {
                    Image(systemName: "person.fill")
                    Text(peer.displayName)
                        .font(.headline)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var controlButton: some View {
        Button {
            if viewModel.connectionState == .idle {
                viewModel.startSearching()
            } else {
                viewModel.stopSearching()
            }
        } label: {
            HStack {
                Image(systemName: viewModel.connectionState == .idle ? "play.fill" : "stop.fill")
                Text(viewModel.connectionState == .idle ? "開始" : "停止")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.connectionState == .idle ? Color.blue : Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!viewModel.isUWBSupported)
    }
}

#Preview {
    ArrowDemoView()
}
