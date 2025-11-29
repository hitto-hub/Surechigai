//
//  ContentView.swift
//  Surechigai
//
//  Created by hitto on 2025/11/29.
//

import SwiftUI

/// メインのTabView
/// 3つのタブ: Arrow Demo / すれ違いモード / 履歴
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Arrow Demo タブ
            ArrowDemoView()
                .tabItem {
                    Label("Arrow", systemImage: "arrow.up.circle.fill")
                }
                .tag(0)

            // すれ違いモード タブ
            SurechigaiModeView()
                .tabItem {
                    Label("すれ違い", systemImage: "figure.walk.circle.fill")
                }
                .tag(1)

            // 履歴 タブ
            HistoryView()
                .tabItem {
                    Label("履歴", systemImage: "clock.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
