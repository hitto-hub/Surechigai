import type { TokenEntry, Room } from './types';

/**
 * In-Memory Token Store
 *
 * 本番環境ではRedisやDBに置き換えることを推奨
 * Token は有効期限付きで管理
 */
class TokenStore {
  private tokens: Map<string, TokenEntry> = new Map();
  private readonly TOKEN_TTL_MS = 30 * 60 * 1000; // 30分

  /**
   * ユーザーのキーを生成（userId + room の組み合わせ）
   */
  private getKey(userId: string, room: string): string {
    return `${room}:${userId}`;
  }

  /**
   * Token を登録
   */
  register(
    userId: string,
    displayName: string,
    token: string,
    room: string
  ): TokenEntry {
    const key = this.getKey(userId, room);
    const now = new Date();

    const entry: TokenEntry = {
      userId,
      displayName: displayName || userId,
      token,
      room,
      createdAt: now,
      expiresAt: new Date(now.getTime() + this.TOKEN_TTL_MS),
    };

    this.tokens.set(key, entry);
    console.log(`📝 Token registered: ${userId} in room "${room}"`);

    return entry;
  }

  /**
   * ルーム内のTokenを取得（自分以外）
   */
  getTokensInRoom(room: string, excludeUserId?: string): TokenEntry[] {
    this.cleanupExpired();

    const result: TokenEntry[] = [];

    for (const entry of this.tokens.values()) {
      if (entry.room === room) {
        if (!excludeUserId || entry.userId !== excludeUserId) {
          result.push(entry);
        }
      }
    }

    return result;
  }

  /**
   * ユーザーのTokenを削除
   */
  unregister(userId: string, room: string): boolean {
    const key = this.getKey(userId, room);
    const deleted = this.tokens.delete(key);

    if (deleted) {
      console.log(`🗑️ Token unregistered: ${userId} from room "${room}"`);
    }

    return deleted;
  }

  /**
   * ルーム内の全Tokenを削除
   */
  clearRoom(room: string): number {
    let count = 0;

    for (const [key, entry] of this.tokens.entries()) {
      if (entry.room === room) {
        this.tokens.delete(key);
        count++;
      }
    }

    console.log(`🗑️ Cleared room "${room}": ${count} tokens removed`);
    return count;
  }

  /**
   * ルーム一覧を取得
   */
  getRooms(): Room[] {
    this.cleanupExpired();

    const roomMap = new Map<string, number>();

    for (const entry of this.tokens.values()) {
      const count = roomMap.get(entry.room) || 0;
      roomMap.set(entry.room, count + 1);
    }

    return Array.from(roomMap.entries()).map(([name, userCount]) => ({
      name,
      createdAt: new Date(),
      userCount,
    }));
  }

  /**
   * 期限切れTokenをクリーンアップ
   */
  private cleanupExpired(): void {
    const now = new Date();
    let cleaned = 0;

    for (const [key, entry] of this.tokens.entries()) {
      if (entry.expiresAt < now) {
        this.tokens.delete(key);
        cleaned++;
      }
    }

    if (cleaned > 0) {
      console.log(`🧹 Cleaned up ${cleaned} expired tokens`);
    }
  }

  /**
   * 統計情報を取得
   */
  getStats(): { totalTokens: number; roomCount: number } {
    this.cleanupExpired();

    const rooms = new Set<string>();
    for (const entry of this.tokens.values()) {
      rooms.add(entry.room);
    }

    return {
      totalTokens: this.tokens.size,
      roomCount: rooms.size,
    };
  }
}

// Singleton instance
export const tokenStore = new TokenStore();
