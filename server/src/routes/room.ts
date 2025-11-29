import { Hono } from 'hono';
import { tokenStore } from '../store';
import type { RoomListResponse } from '../types';

const roomRoutes = new Hono();

/**
 * GET /ni/rooms
 * アクティブなルーム一覧を取得
 */
roomRoutes.get('/', (c) => {
  const rooms = tokenStore.getRooms();

  const response: RoomListResponse = {
    rooms: rooms.map((room) => ({
      name: room.name,
      userCount: room.userCount,
    })),
  };

  return c.json(response);
});

/**
 * DELETE /ni/rooms/:name
 * ルームを削除（ルーム内の全Tokenを削除）
 */
roomRoutes.delete('/:name', (c) => {
  const name = c.req.param('name');

  if (!name) {
    return c.json(
      { error: 'validation_error', message: 'room name is required' },
      400
    );
  }

  const count = tokenStore.clearRoom(name);

  return c.json({
    success: true,
    deletedTokens: count,
  });
});

export { roomRoutes };
