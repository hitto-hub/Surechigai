import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { tokenRoutes } from './routes/token';
import { roomRoutes } from './routes/room';
import { tokenStore } from './store';

const app = new Hono();

// Middleware
app.use('*', logger());
app.use('*', cors({
  origin: '*', // 本番環境では適切に制限
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));

// Health check
app.get('/', (c) => {
  return c.json({
    name: 'Surechigai Token Server',
    version: '1.0.0',
    status: 'running',
  });
});

// Stats endpoint
app.get('/stats', (c) => {
  const stats = tokenStore.getStats();
  return c.json({
    ...stats,
    uptime: process.uptime(),
  });
});

// API Routes
app.route('/ni/token', tokenRoutes);
app.route('/ni/rooms', roomRoutes);

// 404 handler
app.notFound((c) => {
  return c.json(
    { error: 'not_found', message: 'Endpoint not found' },
    404
  );
});

// Error handler
app.onError((err, c) => {
  console.error('Unhandled error:', err);
  return c.json(
    { error: 'server_error', message: 'Internal server error' },
    500
  );
});

// Start server
const port = parseInt(process.env.PORT || '3000', 10);
const hostname = process.env.HOST || '0.0.0.0';

// Get local IP address for display
import { networkInterfaces } from 'os';
function getLocalIP(): string {
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] || []) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return 'localhost';
}

const localIP = getLocalIP();

console.log(`
🚀 Surechigai Token Server
━━━━━━━━━━━━━━━━━━━━━━━━━━

📡 Server running on:
   - http://localhost:${port}
   - http://${localIP}:${port}  ← iOSアプリはこちらを使用

Available endpoints:
  GET  /              - Health check
  GET  /stats         - Server statistics

  POST /ni/token      - Register discovery token
  GET  /ni/token      - Get tokens in room
  DELETE /ni/token    - Unregister token
  POST /ni/token/refresh - Refresh token expiry

  GET  /ni/rooms      - List active rooms
  DELETE /ni/rooms/:name - Clear room

━━━━━━━━━━━━━━━━━━━━━━━━━━
`);

serve({
  fetch: app.fetch,
  port,
  hostname,
});
