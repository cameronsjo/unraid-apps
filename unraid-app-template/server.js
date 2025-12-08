/**
 * Sample Express server for Unraid deployment template.
 * Replace this with your actual application.
 */

const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 3000;
const APP_NAME = process.env.APP_NAME || 'unraid-app';
const VERSION = process.env.VERSION || 'development';

/**
 * Simple HTTP server with health check endpoint.
 */
const server = http.createServer((req, res) => {
  const timestamp = new Date().toISOString();

  // Health check endpoint
  if (req.url === '/health' || req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      timestamp,
      uptime: process.uptime(),
    }));
    return;
  }

  // Info endpoint
  if (req.url === '/info') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      app: APP_NAME,
      version: VERSION,
      node: process.version,
      hostname: os.hostname(),
      platform: os.platform(),
      arch: os.arch(),
      uptime: process.uptime(),
      memory: {
        total: Math.round(os.totalmem() / 1024 / 1024) + ' MB',
        free: Math.round(os.freemem() / 1024 / 1024) + ' MB',
        used: Math.round((os.totalmem() - os.freemem()) / 1024 / 1024) + ' MB',
      },
    }));
    return;
  }

  // Default response
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${APP_NAME}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #e4e4e4;
    }
    .container {
      text-align: center;
      padding: 2rem;
    }
    h1 {
      font-size: 3rem;
      margin-bottom: 1rem;
      background: linear-gradient(90deg, #00d9ff, #00ff88);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
    }
    .version {
      font-size: 1.2rem;
      opacity: 0.7;
      margin-bottom: 2rem;
    }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      background: rgba(0, 255, 136, 0.1);
      border: 1px solid rgba(0, 255, 136, 0.3);
      padding: 0.5rem 1rem;
      border-radius: 2rem;
      color: #00ff88;
    }
    .dot {
      width: 8px;
      height: 8px;
      background: #00ff88;
      border-radius: 50%;
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
    .links {
      margin-top: 2rem;
      display: flex;
      gap: 1rem;
      justify-content: center;
    }
    .links a {
      color: #00d9ff;
      text-decoration: none;
      padding: 0.5rem 1rem;
      border: 1px solid #00d9ff;
      border-radius: 0.5rem;
      transition: all 0.2s;
    }
    .links a:hover {
      background: rgba(0, 217, 255, 0.1);
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>${APP_NAME}</h1>
    <p class="version">Version: ${VERSION}</p>
    <div class="status">
      <span class="dot"></span>
      Running on Unraid
    </div>
    <div class="links">
      <a href="/health">Health Check</a>
      <a href="/info">System Info</a>
    </div>
  </div>
</body>
</html>
  `);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   ${APP_NAME.padEnd(52)}   ║
║   Version: ${VERSION.padEnd(44)}   ║
║                                                            ║
║   Server listening on http://0.0.0.0:${String(PORT).padEnd(21)}   ║
║                                                            ║
║   Endpoints:                                               ║
║     GET /         - Web interface                          ║
║     GET /health   - Health check                           ║
║     GET /info     - System info                            ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
  `);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
