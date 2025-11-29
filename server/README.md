# Surechigai Token Server

NIDiscoveryToken を交換するための REST API サーバー。

## セットアップ

```bash
cd server
npm install
```

## 起動

```bash
# 開発モード（ホットリロード）
npm run dev

# 本番モード
npm start
```

デフォルトで `http://localhost:3000` で起動します。

## API エンドポイント

### Health Check

```
GET /
```

レスポンス:
```json
{
  "name": "Surechigai Token Server",
  "version": "1.0.0",
  "status": "running"
}
```

### Statistics

```
GET /stats
```

レスポンス:
```json
{
  "totalTokens": 5,
  "roomCount": 2,
  "uptime": 3600
}
```

---

### Token API

#### Token 登録

```
POST /ni/token
Content-Type: application/json

{
  "userId": "user-123",
  "displayName": "田中太郎",
  "room": "ictsc-2024",
  "token": "Base64エンコードされたNIDiscoveryToken"
}
```

レスポンス:
```json
{
  "success": true,
  "userId": "user-123",
  "room": "ictsc-2024",
  "expiresAt": "2024-01-01T12:30:00.000Z"
}
```

#### Token 取得

```
GET /ni/token?room=ictsc-2024&excludeUserId=user-123
```

レスポンス:
```json
{
  "tokens": [
    {
      "userId": "user-456",
      "displayName": "佐藤花子",
      "token": "Base64エンコードされたtoken"
    }
  ]
}
```

#### Token 削除

```
DELETE /ni/token?userId=user-123&room=ictsc-2024
```

レスポンス:
```json
{
  "success": true,
  "deleted": true
}
```

#### Token リフレッシュ

```
POST /ni/token/refresh
Content-Type: application/json

{
  "userId": "user-123",
  "room": "ictsc-2024",
  "token": "Base64エンコードされたtoken"
}
```

---

### Room API

#### ルーム一覧

```
GET /ni/rooms
```

レスポンス:
```json
{
  "rooms": [
    {
      "name": "ictsc-2024",
      "userCount": 5
    },
    {
      "name": "lab-meeting",
      "userCount": 3
    }
  ]
}
```

#### ルーム削除

```
DELETE /ni/rooms/ictsc-2024
```

レスポンス:
```json
{
  "success": true,
  "deletedTokens": 5
}
```

---

## Token の有効期限

- デフォルト: 30分
- 期限切れの Token は自動的にクリーンアップされます
- `/ni/token/refresh` で有効期限を延長できます

## iOS アプリとの連携

iOS アプリの `TokenAPIClient.swift` と連携するために:

1. サーバーを起動
2. iOS アプリで `TokenAPIClient` を設定:

```swift
await TokenAPIClient.shared.configure(
    baseURL: URL(string: "http://your-server:3000")!,
    userId: "unique-user-id"
)
await TokenAPIClient.shared.joinRoom("your-room-name")
```

## 本番環境へのデプロイ

### 環境変数

```bash
PORT=3000  # サーバーポート
```

### Docker

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY dist ./dist
CMD ["node", "dist/index.js"]
```

### 注意事項

- 現在はインメモリストアを使用（再起動でデータ消失）
- 本番環境では Redis などの永続化ストレージを推奨
- CORS 設定を適切に制限してください
