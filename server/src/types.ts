/**
 * Token Entry - ユーザーのdiscoveryToken情報
 */
export interface TokenEntry {
  userId: string;
  displayName: string;
  token: string; // Base64 encoded NIDiscoveryToken
  room: string;
  createdAt: Date;
  expiresAt: Date;
}

/**
 * Room - ルーム/イベント情報
 */
export interface Room {
  name: string;
  createdAt: Date;
  userCount: number;
}

/**
 * API Request/Response types
 */
export interface RegisterTokenRequest {
  userId: string;
  displayName?: string;
  room: string;
  token: string; // Base64 encoded
}

export interface TokenListResponse {
  tokens: Array<{
    userId: string;
    displayName: string;
    token: string;
  }>;
}

export interface RoomListResponse {
  rooms: Array<{
    name: string;
    userCount: number;
  }>;
}

export interface ApiError {
  error: string;
  message: string;
}
