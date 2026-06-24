// Wait for DOM to load
document.addEventListener("DOMContentLoaded", () => {
  const terminalContainer = document.getElementById("terminal-container");
  const connectionStatus = document.getElementById("connection-status");
  const statusDot = document.querySelector(".dot");
  const disconnectOverlay = document.getElementById("disconnect-overlay");
  const reconnectBtn = document.getElementById("btn-reconnect");
  const demoButtons = document.querySelectorAll(".demo-btn");
  const resetBtn = document.getElementById("btn-reset");

  let socket;
  let term;
  let fitAddon;
  let heartbeatInterval;
  let isTyping = false;

  // 1. Initialize xterm.js
  term = new Terminal({
    cursorBlink: true,
    cursorStyle: "block",
    theme: {
      background: "#0f0f11",
      foreground: "#e3e3e6",
      cursor: "#3b82f6",
      black: "#18181c",
      red: "#ef4444",
      green: "#10b981",
      yellow: "#f59e0b",
      blue: "#3b82f6",
      magenta: "#8b5cf6",
      cyan: "#06b6d4",
      white: "#f3f4f6",
    },
    fontFamily: '"Roboto Mono", "SFMono-Regular", Consolas, "Liberation Mono", Menlo, Courier, monospace',
    fontSize: 14,
    lineHeight: 1.2,
  });

  fitAddon = new window.FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(terminalContainer);
  
  // Re-fit terminal once custom web fonts are fully loaded by the browser
  document.fonts.ready.then(() => {
    if (term && fitAddon) {
      try {
        fitAddon.fit();
        sendResize();
      } catch (e) {
        console.error("Error re-fitting terminal after font load:", e);
      }
    }
  });

  // Use ResizeObserver to handle terminal fitting and resizing robustly
  const resizeObserver = new ResizeObserver(() => {
    if (term && fitAddon) {
      try {
        fitAddon.fit();
        sendResize();
      } catch (e) {
        console.error("Error fitting terminal:", e);
      }
    }
  });
  resizeObserver.observe(terminalContainer);

  // 2. Connect to WebSocket
  function connect() {
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const host = window.location.host;
    const wsUrl = `${protocol}//${host}/ws`;

    console.log(`Connecting to terminal WebSocket at: ${wsUrl}`);
    socket = new WebSocket(wsUrl);

    // Pipe user terminal input to WebSocket
    term.onData((data) => {
      if (socket && socket.readyState === WebSocket.OPEN && !isTyping) {
        socket.send(data);
      }
    });

    socket.onopen = () => {
      console.log("WebSocket connection established.");
      
      // Mark UI as connected
      connectionStatus.textContent = "Connected";
      statusDot.className = "dot connected";
      disconnectOverlay.classList.add("hidden");
      enableButtons();

      // Initial fit triggered by ResizeObserver automatically

      // Start keep-alive heartbeats to prevent Cloud Run timeouts
      startHeartbeat();
    };

    socket.onmessage = (event) => {
      try {
        // Check if the message is a control JSON (like pong)
        const data = JSON.parse(event.data);
        if (data && data.type === "pong") {
          return; // Ignore keep-alive heartbeats
        }
      } catch (e) {
        // Not a JSON control message, proceed to write to terminal
      }
      // Write incoming data from PTY to xterm
      term.write(event.data);
    };

    socket.onclose = (event) => {
      console.log(`WebSocket connection closed (code: ${event.code}).`);
      
      // Mark UI as disconnected
      connectionStatus.textContent = "Disconnected";
      statusDot.className = "dot disconnected";
      disconnectOverlay.classList.remove("hidden");
      disableButtons();

      // Clean up heartbeat
      stopHeartbeat();
    };

    socket.onerror = (error) => {
      console.error("WebSocket error:", error);
    };
  }

  // 3. Handle Resizing
  function sendResize() {
    if (socket && socket.readyState === WebSocket.OPEN) {
      const size = {
        type: "resize",
        cols: term.cols,
        rows: term.rows
      };
      socket.send(JSON.stringify(size));
    }
  }

  // Resizing is handled automatically by the ResizeObserver on the container

  // 4. Keep-Alive Heartbeat (Ping)
  function startHeartbeat() {
    heartbeatInterval = setInterval(() => {
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: "ping" }));
      }
    }, 30000); // Send ping every 30 seconds
  }

  function stopHeartbeat() {
    if (heartbeatInterval) {
      clearInterval(heartbeatInterval);
      heartbeatInterval = null;
    }
  }

  // 5. Simulated Typing Engine
  async function simulateTyping(command) {
    if (isTyping || !socket || socket.readyState !== WebSocket.OPEN) return;
    
    isTyping = true;
    disableButtons();

    // Step A: Send Ctrl+C to abort any running command and get a clean prompt
    socket.send("\x03"); 
    await new Promise((resolve) => setTimeout(resolve, 300)); // Wait for shell to clear

    // Step B: Type characters sequentially
    for (let i = 0; i < command.length; i++) {
      const char = command[i];
      socket.send(char);
      
      // Variable typing delay for realism (20ms - 45ms)
      const delay = Math.floor(Math.random() * 25) + 20;
      await new Promise((resolve) => setTimeout(resolve, delay));
    }

    // Step C: Small pause, then hit Enter
    await new Promise((resolve) => setTimeout(resolve, 200));
    socket.send("\r");

    // Re-enable buttons after typing finishes
    isTyping = false;
    enableButtons();
  }

  // 6. Button State Management
  function disableButtons() {
    demoButtons.forEach(btn => btn.disabled = true);
    resetBtn.disabled = true;
  }

  function enableButtons() {
    if (isTyping) return;
    demoButtons.forEach(btn => btn.disabled = false);
    resetBtn.disabled = false;
  }

  // 7. Event Listeners for UI
  demoButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      // Remove active class from all, add to clicked
      demoButtons.forEach(b => b.classList.remove("active"));
      btn.classList.add("active");
      
      const command = btn.getAttribute("data-command");
      simulateTyping(command);
    });
  });

  resetBtn.addEventListener("click", () => {
    // Revert active button styling
    demoButtons.forEach(b => b.classList.remove("active"));
    const command = resetBtn.getAttribute("data-command");
    simulateTyping(command);
  });

  // Reload page to reconnect (spawns a fresh Cloud Run container)
  reconnectBtn.addEventListener("click", () => {
    window.location.reload();
  });

  // Start connection
  connect();
});
