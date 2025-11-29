# Surechigai - すれ違い検出アプリ

iPhone同士のUWB（Ultra Wideband）を使って、ピアの方向・距離表示とすれ違い検出を行うアプリです。

## プロジェクト構成

```
Surechigai/
├── Surechigai/                    # Xcodeプロジェクト
│   └── Surechigai/                # iOSアプリ本体
│       ├── Models/
│       ├── Views/
│       ├── ViewModels/
│       └── Services/
└── server/                        # Token交換サーバー（Node.js）
```

## 機能

### 1. Arrow Demo（矢印UIデモ）
- 1対1でピアの方向・距離をリアルタイム表示
- **ローカルモード**: Multipeer Connectivity による自動接続
- **サーバー経由モード**: REST API による token 交換
- UWBによる高精度測距（数cmレベル）

#### 接続モードの選択

Arrow Demo 画面右上の⚙️ボタンから設定画面を開けます：

| モード | 説明 | 用途 |
|--------|------|------|
| ローカル (Multipeer) | Wi-Fi/Bluetooth で直接接続 | 同じ部屋にいる場合 |
| サーバー経由 | REST API でトークン交換 | 異なるネットワーク、ルーム管理が必要な場合 |

### 2. すれ違いモード
- バックグラウンドでのすれ違い検出（iOS 18.4+）
- **ローカルモード** / **サーバー経由モード** 対応
- Live Activity によるステータス表示
- すれ違いログの自動記録
- **ローカル通知**（すれ違い検出時）
- **近くにいる人のリアルタイム表示**
- 設定の永続化

#### すれ違い検出の設定

| 設定 | デフォルト | 説明 |
|------|----------|------|
| 判定距離 | 3.0 m | この距離以内でカウント |
| 判定時間 | 2 秒 | この時間以上近くにいるとカウント |
| クールダウン | 60 秒 | 同じ人との再検出までの待ち時間 |
| 通知 | ON | すれ違い時にローカル通知 |
| バイブレーション | ON | すれ違い時に振動 |

### 3. 履歴
- すれ違い履歴の閲覧
- 日別サマリー
- ルーム/イベント単位でのグループ化

---

## サーバーのセットアップ

```bash
cd server
npm install
npm run dev
```

サーバー起動時にローカルIPアドレスが表示されます：
```
📡 Server running on:
   - http://localhost:3000
   - http://192.168.1.xxx:3000  ← iOSアプリはこちらを使用
```

### Arrow Demo でサーバー経由モードを使う

1. サーバーを起動
2. iOSアプリの Arrow Demo 画面で⚙️をタップ
3. 「サーバー経由」モードを選択
4. サーバーURLに `http://<表示されたIP>:3000` を入力
5. 同じルーム名を2台で設定
6. 両方で「開始」をタップ

詳細は [server/README.md](./server/README.md) を参照。

---

## iOSアプリの設定

### Info.plist に追加が必要なキー

```xml
<!-- Nearby Interaction -->
<key>NSNearbyInteractionAllowOnceUsageDescription</key>
<string>近くにいる人との距離と方向を測定するために必要です</string>

<!-- Nearby Interaction (継続的な使用) -->
<key>NSNearbyInteractionUsageDescription</key>
<string>すれ違い検出のために近くのデバイスとの距離を測定します</string>

<!-- Bluetooth -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>近くのデバイスを検出するために必要です</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>近くのデバイスと通信するために必要です</string>

<!-- Local Network -->
<key>NSLocalNetworkUsageDescription</key>
<string>近くのデバイスと接続するために必要です</string>
<key>NSBonjourServices</key>
<array>
    <string>_surechigai-uwb._tcp</string>
    <string>_surechigai-uwb._udp</string>
</array>
```

### Background Modes（Capabilities で有効化）

- [x] Uses Nearby Interaction（iOS 18.4+ でバックグラウンド測距に必要）
- [x] Background processing（オプション）

---

## 動作要件

- iOS 16.0 以上（Arrow Demo）
- iOS 18.4 以上（バックグラウンドすれ違い検出）
- U1 / U2 チップ搭載デバイス（iPhone 11 以降）

## すれ違い判定ロジック

```
判定条件:
- 距離: 3m 以内（設定可能）
- 時間: 2秒以上近くにいる（設定可能）
- クールダウン: 同じ相手との再検出まで60秒

フロー:
1. ピアが閾値距離内に入る → エントリー時刻を記録
2. 継続的に距離を測定 → 最小距離を更新
3. 閾値時間を超える → すれ違いとして記録
4. ピアが閾値外に出る → ステートをリセット
```

## 今後の実装予定

- [ ] Widget Extension（Live Activity の実装）
- [x] サーバー連携（REST API で token 交換）
- [x] ローカル通知
- [ ] カメラアシスト（方向が取れない場合の補完）
- [ ] Apple Watch 対応
- [ ] プッシュ通知（APNs）

## 開発メモ

### discoveryToken について
- `NIDiscoveryToken` はセッションごとに生成される
- `NSKeyedArchiver` でシリアライズして交換可能
- 有効期限付きで扱い、永続IDとして使わない

### バックグラウンド動作の制約
- iOS 18.4+ で `Uses Nearby Interaction` が必要
- Live Activity 実行中のみバックグラウンド測距が継続
- 完全な24h常駐は不可能（OS制約）
