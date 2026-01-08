//! Chatbot Example - Local AI chatbot with streaming
//!
//! Demonstrates a simple chat interface using ziew.ai.stream()
//! Build with: zig build -Dai=true chatbot
//!
//! Usage: ./zig-out/bin/chatbot <path-to-model.gguf>

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get model path from args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: chatbot <path-to-model.gguf>\n", .{});
        std.debug.print("\nDownload a model from HuggingFace:\n", .{});
        std.debug.print("  https://huggingface.co/models?search=gguf\n", .{});
        return;
    }

    const model_path = args[1];
    std.debug.print("[chatbot] Loading model: {s}\n", .{model_path});

    // Create the app window
    var app = try ziew.App.init(allocator, .{
        .title = "Ziew Chatbot",
        .width = 600,
        .height = 500,
        .debug = true,
    });
    defer app.deinit();

    // Initialize AI bridge with the model
    var ai_bridge = ziew.ai_bridge.AiBridge.init(allocator, app.window, model_path) catch |err| {
        std.debug.print("[chatbot] Failed to load model: {any}\n", .{err});
        return;
    };
    defer ai_bridge.deinit();

    std.debug.print("[chatbot] Model loaded! Opening window...\n", .{});

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
    \\    .status {
    \\      text-align: center;
    \\      padding: 0.5rem;
    \\      color: #888;
    \\      font-size: 0.875rem;
    \\    }
    \\  </style>
    \\</head>
    \\<body>
    \\  <div id="messages">
    \\    <div class="status">Type a message to start chatting!</div>
    \\  </div>
    \\  <div id="input-area">
    \\    <input type="text" id="prompt" placeholder="Type your message..." autofocus>
    \\    <button id="send">Send</button>
    \\  </div>
    \\
    \\  <script>
    \\    const messages = document.getElementById('messages');
    \\    const promptInput = document.getElementById('prompt');
    \\    const sendBtn = document.getElementById('send');
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
    \\    async function sendMessage() {
    \\      const prompt = promptInput.value.trim();
    \\      if (!prompt || isGenerating) return;
    \\
    \\      // Clear initial status
    \\      const status = messages.querySelector('.status');
    \\      if (status) status.remove();
    \\
    \\      // Add user message
    \\      addMessage(prompt, 'user');
    \\      promptInput.value = '';
    \\
    \\      // Add assistant message placeholder
    \\      const assistantDiv = addMessage('', 'assistant');
    \\
    \\      isGenerating = true;
    \\      sendBtn.disabled = true;
    \\
    \\      try {
    \\        // Stream the response
    \\        for await (const token of ziew.ai.stream(prompt, { maxTokens: 256 })) {
    \\          assistantDiv.textContent += token;
    \\          messages.scrollTop = messages.scrollHeight;
    \\        }
    \\      } catch (err) {
    \\        assistantDiv.textContent = 'Error: ' + err.message;
    \\        assistantDiv.style.color = '#f66';
    \\      }
    \\
    \\      isGenerating = false;
    \\      sendBtn.disabled = false;
    \\      promptInput.focus();
    \\    }
    \\
    \\    sendBtn.addEventListener('click', sendMessage);
    \\    promptInput.addEventListener('keypress', (e) => {
    \\      if (e.key === 'Enter') sendMessage();
    \\    });
    \\
    \\    // Check if AI is available
    \\    if (!ziew.ai.available()) {
    \\      addMessage('AI not available. Build with -Dai=true', 'assistant');
    \\    }
    \\  </script>
    \\</body>
    \\</html>
;
