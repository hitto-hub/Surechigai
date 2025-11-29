import { Hono } from 'hono';
import { tokenStore } from '../store';
import type { RegisterTokenRequest, TokenListResponse } from '../types';

const tokenRoutes = new Hono();

/**
 * POST /ni/token
 * discoveryToken を登録
 */
tokenRoutes.post('/', async (c) => {
  try {
    const body = await c.req.json<RegisterTokenRequest>();

    // Validation
    if (!body.userId || !body.room || !body.token) {
      return c.json(
        { error: 'validation_error', message: 'userId, room, token are required' },
        400
      );
    }

    // Token の形式チェック（Base64）
    try {
      atob(body.token);
    } catch {
      return c.json(
        { error: 'validation_error', message: 'token must be valid Base64' },
        400
      );
    }

    const entry = tokenStore.register(
      body.userId,
      body.displayName || body.userId,
      body.token,
      body.room
    );

    return c.json({
      success: true,
      userId: entry.userId,
      room: entry.room,
      expiresAt: entry.expiresAt.toISOString(),
    });
  } catch (error) {
    console.error('Error registering token:', error);
    return c.json(
      { error: 'server_error', message: 'Failed to register token' },
      500
    );
  }
});

/**
 * GET /ni/token
 * ルーム内のTokenリストを取得
 * Query params:
 *   - room: ルーム名（必須）
 *   - excludeUserId: 除外するユーザーID（オプション）
 */
tokenRoutes.get('/', (c) => {
  const room = c.req.query('room');
  const excludeUserId = c.req.query('excludeUserId');

  if (!room) {
    return c.json(
      { error: 'validation_error', message: 'room query parameter is required' },
      400
    );
  }

  const entries = tokenStore.getTokensInRoom(room, excludeUserId);

  const response: TokenListResponse = {
    tokens: entries.map((entry) => ({
      userId: entry.userId,
      displayName: entry.displayName,
      token: entry.token,
    })),
  };

  return c.json(response);
});

/**
 * DELETE /ni/token
 * Token を削除
 * Query params:
 *   - userId: ユーザーID（必須）
 *   - room: ルーム名（必須）
 */
tokenRoutes.delete('/', (c) => {
  const userId = c.req.query('userId');
  const room = c.req.query('room');

  if (!userId || !room) {
    return c.json(
      { error: 'validation_error', message: 'userId and room are required' },
      400
    );
  }

  const deleted = tokenStore.unregister(userId, room);

  return c.json({
    success: true,
    deleted,
  });
});

/**
 * POST /ni/token/refresh
 * Token の有効期限を延長（再登録）
 */
tokenRoutes.post('/refresh', async (c) => {
  try {
    const body = await c.req.json<RegisterTokenRequest>();

    if (!body.userId || !body.room || !body.token) {
      return c.json(
        { error: 'validation_error', message: 'userId, room, token are required' },
        400
      );
    }

    const entry = tokenStore.register(
      body.userId,
      body.displayName || body.userId,
      body.token,
      body.room
    );

    return c.json({
      success: true,
      expiresAt: entry.expiresAt.toISOString(),
    });
  } catch (error) {
    console.error('Error refreshing token:', error);
    return c.json(
      { error: 'server_error', message: 'Failed to refresh token' },
      500
    );
  }
});

export { tokenRoutes };
