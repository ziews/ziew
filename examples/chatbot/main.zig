//! Chatbot Example - Local AI chatbot with streaming
//!
//! Demonstrates a simple chat interface using ziew.ai.stream()
//! Build with: zig build -Dai=true chatbot
//!
//! Models are auto-detected from ~/.ziew/models/
//! Just place a .gguf file there and run the app!

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the app window
    var app = try ziew.App.init(allocator, .{
        .title = "Ziew Chatbot",
        .width = 600,
        .height = 500,
        .debug = true,
    });
    defer app.deinit();

    // Initialize AI bridge with auto-detection
    // Will automatically load the first .gguf model found in ~/.ziew/models/
    var ai_bridge = try ziew.ai_bridge.AiBridge.initAuto(allocator, app.window);
    defer ai_bridge.deinit();

    // Bind the AI functions to the webview (must be called after struct is at final location)
    try ai_bridge.bind();

    // Load the chat HTML
    app.loadHtml(chat_html);

    // Run the app
    app.run();
}

const chat_html: [:0]const u8 =
    \\<!DOCTYPE html>
    \\<html>
    \\<head>
    \\  <meta charset="utf-8">
    \\  <title>Ziew Chatbot</title>
    \\  <style>
    \\    * { box-sizing: border-box; margin: 0; padding: 0; }
    \\    body {
    \\      font-family: system-ui, -apple-system, sans-serif;
    \\      background: #1a1a2e;
    \\      color: #eee;
    \\      height: 100vh;
    \\      display: flex;
    \\      flex-direction: column;
    \\    }
    \\    #header {
    \\      padding: 0.75rem 1rem;
    \\      background: #16213e;
    \\      border-bottom: 1px solid #333;
    \\      display: flex;
    \\      justify-content: space-between;
    \\      align-items: center;
    \\    }
    \\    #header h1 {
    \\      font-size: 1rem;
    \\      background: linear-gradient(135deg, #00d4ff, #7b2ff7);
    \\      -webkit-background-clip: text;
    \\      -webkit-text-fill-color: transparent;
    \\    }
    \\    #model-info {
    \\      font-size: 0.75rem;
    \\      color: #666;
    \\    }
    \\    #messages {
    \\      flex: 1;
    \\      overflow-y: auto;
    \\      padding: 1rem;
    \\    }
    \\    .message {
    \\      margin: 0.5rem 0;
    \\      padding: 0.75rem 1rem;
    \\      border-radius: 1rem;
    \\      max-width: 80%;
    \\    }
    \\    .user {
    \\      background: #4a4e69;
    \\      margin-left: auto;
    \\    }
    \\    .assistant {
    \\      background: #22223b;
    \\    }
    \\    .system {
    \\      background: transparent;
    \\      color: #666;
    \\      font-size: 0.875rem;
    \\      text-align: center;
    \\      max-width: 100%;
    \\    }
    \\    #input-area {
    \\      display: flex;
    \\      padding: 1rem;
    \\      gap: 0.5rem;
    \\      background: #16213e;
    \\    }
    \\    #prompt {
    \\      flex: 1;
    \\      padding: 0.75rem 1rem;
    \\      border: none;
    \\      border-radius: 1.5rem;
    \\      background: #1a1a2e;
    \\      color: #eee;
    \\      font-size: 1rem;
    \\    }
    \\    #prompt:focus { outline: 2px solid #4a4e69; }
    \\    button {
    \\      padding: 0.75rem 1.5rem;
    \\      border: none;
    \\      border-radius: 1.5rem;
    \\      background: #4a4e69;
    \\      color: #eee;
    \\      cursor: pointer;
    \\      font-size: 1rem;
    \\    }
    \\    button:hover { background: #5a5e79; }
    \\    button:disabled { opacity: 0.5; cursor: not-allowed; }
    \\    .spinner {
    \\      display: inline-block;
    \\      width: 16px;
    \\      height: 16px;
    \\      border: 2px solid #666;
    \\      border-radius: 50%;
    \\      border-top-color: #00d4ff;
    \\      animation: spin 1s linear infinite;
    \\      margin-right: 8px;
    \\      vertical-align: middle;
    \\    }
    \\    @keyframes spin {
    \\      to { transform: rotate(360deg); }
    \\    }
    \\    .thinking {
    \\      color: #888;
    \\      font-style: italic;
    \\    }
    \\  </style>
    \\</head>
    \\<body>
    \\  <div id="header">
    \\    <h1>Ziew Chatbot</h1>
    \\    <span id="model-info">Loading...</span>
    \\  </div>
    \\  <div id="messages"></div>
    \\  <div id="input-area">
    \\    <input type="text" id="prompt" placeholder="Type your message..." autofocus>
    \\    <button id="send">Send</button>
    \\  </div>
    \\
    \\  <script>
    \\    const messages = document.getElementById('messages');
    \\    const promptInput = document.getElementById('prompt');
    \\    const sendBtn = document.getElementById('send');
    \\    const modelInfo = document.getElementById('model-info');
    \\
    \\    let isGenerating = false;
    \\
    \\    function addMessage(text, role) {
    \\      const div = document.createElement('div');
    \\      div.className = 'message ' + role;
    \\      div.textContent = text;
    \\      messages.appendChild(div);
    \\      messages.scrollTop = messages.scrollHeight;
    \\      return div;
    \\    }
    \\
    \\    async function init() {
    \\      // Check for available models
    \\      try {
    \\        const models = await ziew.ai.models();
    \\        if (models.length === 0) {
    \\          modelInfo.textContent = 'No models found';
    \\          addMessage('No models found in ~/.ziew/models/', 'system');
    \\          addMessage('Place a .gguf file there to start chatting!', 'system');
    \\        } else {
    \\          modelInfo.textContent = models[0];
    \\          addMessage('Model loaded: ' + models[0], 'system');
    \\        }
    \\      } catch (e) {
    \\        modelInfo.textContent = 'AI not available';
    \\        addMessage('AI not available - build with -Dai=true', 'system');
    \\      }
    \\    }
    \\
    \\    async function sendMessage() {
    \\      const prompt = promptInput.value.trim();
    \\      if (!prompt || isGenerating) return;
    \\
    \\      console.log('[chat] Sending:', prompt);
    \\
    \\      // Add user message
    \\      addMessage(prompt, 'user');
    \\      promptInput.value = '';
    \\
    \\      // Add assistant message with spinner
    \\      const assistantDiv = document.createElement('div');
    \\      assistantDiv.className = 'message assistant';
    \\      assistantDiv.innerHTML = '<span class="spinner"></span><span class="thinking">Thinking...</span>';
    \\      messages.appendChild(assistantDiv);
    \\      messages.scrollTop = messages.scrollHeight;
    \\
    \\      isGenerating = true;
    \\      sendBtn.disabled = true;
    \\      sendBtn.textContent = 'Generating...';
    \\
    \\      try {
    \\        console.log('[chat] Starting stream...');
    \\        let gotFirst = false;
    \\        // Stream the response
    \\        for await (const token of ziew.ai.stream(prompt, { maxTokens: 256 })) {
    \\          if (!gotFirst) {
    \\            assistantDiv.innerHTML = '';
    \\            gotFirst = true;
    \\            console.log('[chat] Got first token');
    \\          }
    \\          assistantDiv.textContent += token;
    \\          messages.scrollTop = messages.scrollHeight;
    \\        }
    \\        console.log('[chat] Stream complete');
    \\        if (!gotFirst) {
    \\          assistantDiv.innerHTML = '<span style="color:#f66">No response received</span>';
    \\        }
    \\      } catch (err) {
    \\        console.error('[chat] Error:', err);
    \\        assistantDiv.innerHTML = '';
    \\        assistantDiv.textContent = 'Error: ' + err.message;
    \\        assistantDiv.style.color = '#f66';
    \\      }
    \\
    \\      isGenerating = false;
    \\      sendBtn.disabled = false;
    \\      sendBtn.textContent = 'Send';
    \\      promptInput.focus();
    \\    }
    \\
    \\    sendBtn.addEventListener('click', sendMessage);
    \\    promptInput.addEventListener('keypress', (e) => {
    \\      if (e.key === 'Enter') sendMessage();
    \\    });
    \\
    \\    // Initialize on load
    \\    init();
    \\  </script>
    \\</body>
    \\</html>
;
