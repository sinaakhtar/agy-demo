const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const pty = require('node-pty');
const path = require('path');
const os = require('os');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ noServer: true });

const PORT = process.env.PORT || 8080;

// Resolve demo repo path.
// Inside Docker it will be /workspace/todo-app
// Locally it will be sibling to backend
const DEFAULT_DEMO_REPO_PATH = path.resolve(__dirname, '../demo-repo');
const DEMO_REPO_PATH = process.env.DEMO_REPO_PATH || DEFAULT_DEMO_REPO_PATH;

console.log(`Configured Demo Repo Path: ${DEMO_REPO_PATH}`);

// Serve static frontend files
app.use(express.static(path.join(__dirname, '../frontend')));

// WebSocket Upgrade handler
server.on('upgrade', (request, socket, head) => {
  const pathname = new URL(request.url, `http://${request.headers.host}`).pathname;

  if (pathname === '/ws') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

wss.on('connection', (ws) => {
  console.log('New client connected to terminal session');

  // Determine shell (bash on Linux/macOS, powershell/cmd on Windows)
  const shell = os.platform() === 'win32' ? 'powershell.exe' : 'bash';

  // Set up environment variables for the shell
  const env = Object.assign({}, process.env, {
    TERM: 'xterm-256color',
    HOME: '/home/demo',
    GOOGLE_APPLICATION_CREDENTIALS: '/home/demo/.config/gcloud/application_default_credentials.json',
    // Ensure the agy CLI path is in PATH if installed in ~/.local/bin
    PATH: `${process.env.PATH || ''}:${path.join(os.homedir(), '.local/bin')}`,
  });

  // Spawn the pseudoterminal (PTY)
  const ptyProcess = pty.spawn(shell, [], {
    name: 'xterm-color',
    cols: 80,
    rows: 24,
    cwd: DEMO_REPO_PATH,
    env: env,
  });

  // Pipe PTY output to WebSocket
  ptyProcess.onData((data) => {
    try {
      ws.send(data);
    } catch (err) {
      console.error('Error sending PTY data to WebSocket:', err);
    }
  });

  // Handle incoming WebSocket messages
  ws.on('message', (message) => {
    try {
      // Check if message is a control JSON (e.g. resize)
      const data = message.toString();
      if (data.startsWith('{') && data.endsWith('}')) {
        const parsed = JSON.parse(data);
        if (parsed.type === 'resize') {
          ptyProcess.resize(parsed.cols, parsed.rows);
          console.log(`Resized terminal to ${parsed.cols}x${parsed.rows}`);
          return;
        }
        if (parsed.type === 'ping') {
          // Keep-alive heartbeat response
          ws.send(JSON.stringify({ type: 'pong' }));
          return;
        }
      }
      
      // Otherwise, write raw keypresses/input to PTY
      ptyProcess.write(message);
    } catch (err) {
      // In case JSON parsing fails or write fails, treat as raw input
      ptyProcess.write(message);
    }
  });

  // Handle terminal exit
  ptyProcess.onExit(({ exitCode, signal }) => {
    console.log(`PTY process exited with code ${exitCode}, signal ${signal}`);
    try {
      ws.close();
    } catch (err) {}
  });

  // Clean up on WebSocket close
  ws.on('close', () => {
    console.log('Client disconnected. Killing PTY process.');
    try {
      ptyProcess.kill();
    } catch (err) {}
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
    try {
      ptyProcess.kill();
    } catch (e) {}
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Terminal server running on http://0.0.0.0:${PORT}`);
});
