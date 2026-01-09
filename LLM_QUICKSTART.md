# Ziew LLM Quickstart

Quick reference for AI assistants building apps with Ziew.

## What is Ziew?

Lightweight desktop app framework. Write HTML/CSS/JS, get native apps in ~300KB. Think Electron but 500x smaller.

- **Webview:** Uses native system webview (WebKit on Mac/Linux, Edge WebView2 on Windows)
- **Backend:** Optional - most apps are pure frontend with JS APIs
- **AI:** Optional local LLM via llama.cpp

## CLI Commands

```bash
ziew init myapp                    # Create new project
ziew init myapp --template=phaser  # With game template
ziew init myapp --style=pico       # With CSS framework
ziew dev                           # Dev server with hot reload
ziew build                         # Build for current platform
ziew ship                          # Build for all platforms (outputs to dist/)
ziew plugin add sqlite notify      # Enable plugins
ziew plugin list                   # Show available plugins
```

## Project Structure

```
myapp/
├── ziew.zon          # Project config (name, version, plugins)
├── src/
│   ├── index.html    # Entry point
│   ├── style.css
│   └── app.js
└── dist/             # Built binaries (after ziew ship)
```

## ziew.zon Config

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .plugins = .{ "sqlite", "notify" },
}
```

## JavaScript APIs

All APIs are async and available on the global `ziew` object.

### File System
```javascript
const content = await ziew.fs.readFile('./data.json');
await ziew.fs.writeFile('./output.txt', 'Hello');
const files = await ziew.fs.readDir('./assets');
const exists = await ziew.fs.exists('./config.json');
```

### Dialogs
```javascript
const path = await ziew.dialog.open({ filters: ['*.txt', '*.md'] });
const savePath = await ziew.dialog.save({ defaultName: 'export.json' });
await ziew.dialog.alert('Done!', 'Export complete.');
const ok = await ziew.dialog.confirm('Delete this file?');
```

### Shell
```javascript
const result = await ziew.shell.exec('ls -la');
await ziew.shell.open('https://example.com');  // Open in default browser
```

### Clipboard
```javascript
await ziew.clipboard.write('copied text');
const text = await ziew.clipboard.read();
```

### Window
```javascript
await ziew.window.setTitle('New Title');
await ziew.window.setSize(800, 600);
await ziew.window.center();
await ziew.window.minimize();
await ziew.window.close();
```

## Plugins

Only enabled plugins are bundled. Add via CLI or edit ziew.zon directly.

| Plugin | Description | JS Namespace |
|--------|-------------|--------------|
| sqlite | Embedded database | `ziew.db` |
| notify | System notifications | `ziew.notify` |
| keychain | Secure credential storage | `ziew.keychain` |
| hotkeys | Global keyboard shortcuts | `ziew.hotkeys` |
| gamepad | Game controller input | `ziew.gamepad` |
| serial | Serial port communication | `ziew.serial` |
| ai | Local LLM (llama.cpp) | `ziew.ai` |
| piper | Text-to-speech | `ziew.tts` |
| lua | LuaJIT scripting | `ziew.lua` |
| steamworks | Steam integration | `ziew.steam` |

### Plugin Examples

**SQLite:**
```javascript
const db = await ziew.db.open('app.db');
await db.exec('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)');
await db.run('INSERT INTO users (name) VALUES (?)', ['Alice']);
const users = await db.query('SELECT * FROM users');
```

**Notifications:**
```javascript
await ziew.notify.send('Title', 'Message body');
```

**Hotkeys:**
```javascript
ziew.hotkeys.register('Ctrl+Shift+P', () => {
  console.log('Hotkey pressed!');
});
```

**Gamepad:**
```javascript
ziew.gamepad.on('connected', (pad) => console.log('Controller connected:', pad.id));
ziew.gamepad.on('button', (btn, pressed) => console.log(btn, pressed));
```

**AI (Local LLM):**
```javascript
// Streaming response
for await (const token of ziew.ai.stream('Tell me a joke')) {
  output.textContent += token;
}

// One-shot completion
const response = await ziew.ai.complete('Summarize this: ...');
```

**Steamworks:**
```javascript
await ziew.steam.init();
const name = ziew.steam.user.getName();
await ziew.steam.achievements.unlock('FIRST_WIN');
```

## Templates

### Phaser (2D games)
```bash
ziew init mygame --template=phaser
```
Sets up Phaser 3 with a basic scene. Good for 2D sprite-based games.

### Kaplay (2D games)
```bash
ziew init mygame --template=kaplay
```
Sets up Kaplay (formerly Kaboom.js). Simpler API, great for quick prototypes.

### Three.js (3D)
```bash
ziew init myapp --template=three
```
Sets up Three.js with a basic 3D scene.

## CSS Frameworks

```bash
ziew init myapp --style=pico    # Pico CSS - minimal, semantic
ziew init myapp --style=water   # Water.css - classless
ziew init myapp --style=simple  # Simple.css - classless
```

## Common Patterns

### Save/Load Game Data
```javascript
const SAVE_FILE = './save.json';

async function saveGame(data) {
  await ziew.fs.writeFile(SAVE_FILE, JSON.stringify(data, null, 2));
}

async function loadGame() {
  if (await ziew.fs.exists(SAVE_FILE)) {
    const content = await ziew.fs.readFile(SAVE_FILE);
    return JSON.parse(content);
  }
  return null;
}
```

### Settings with Defaults
```javascript
async function getSettings() {
  try {
    const content = await ziew.fs.readFile('./settings.json');
    return { ...defaultSettings, ...JSON.parse(content) };
  } catch {
    return defaultSettings;
  }
}
```

### Secure API Keys
```javascript
// Store securely (uses system keychain)
await ziew.keychain.set('myapp', 'api_key', 'sk-...');

// Retrieve
const apiKey = await ziew.keychain.get('myapp', 'api_key');
```

## Resources

| Resource | Location |
|----------|----------|
| Full documentation | https://ziew.sh/docs |
| Plugin details | https://ziew.sh/plugins |
| Examples | `~/dev/ziew/ziew/examples/` |
| Source code | https://github.com/ziews/ziew |

## Troubleshooting

**"Plugin not found"** - Run `ziew plugin add <name>` then rebuild.

**"Cannot find ziew"** - The `ziew` object is injected at runtime. It won't exist if you open the HTML directly in a browser.

**Large binary size** - Check which plugins are enabled. Each plugin adds to size. Remove unused ones from ziew.zon.

**Hot reload not working** - Make sure you're using `ziew dev`, not opening the HTML file directly.
