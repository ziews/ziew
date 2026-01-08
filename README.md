<p align="center">
  <img src="https://ziew.sh/assets/ziew.png" alt="Ziew" width="120" height="120">
</p>

<h1 align="center">Ziew</h1>

<p align="center">
  <strong>Desktop apps in kilobytes, not megabytes.</strong>
</p>

<p align="center">
  Native performance. Native size.<br>
  Desktop apps, minus the bloat.
</p>

<p align="center">
  <a href="https://github.com/ziews/ziew/blob/main/LICENSE"><img src="https://img.shields.io/github/license/ziews/ziew?style=flat-square" alt="license"></a>
  <img src="https://img.shields.io/badge/binary_size-220KB-brightgreen?style=flat-square" alt="binary size">
  <img src="https://img.shields.io/badge/built_with-Zig-f7a41d?style=flat-square" alt="built with Zig">
  <img src="https://img.shields.io/badge/platforms-Win%20%7C%20Mac%20%7C%20Linux-blue?style=flat-square" alt="platforms">
</p>

<p align="center">
  <a href="https://ziew.sh">Website</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#why-ziew">Why Ziew</a>
</p>

---

> ⚠️ **Early Alpha** — APIs will change. Not production-ready.

## The Post-Electron Era

| Framework | Hello World Size |
|-----------|------------------|
| Electron | ~150 MB |
| Tauri | ~3-5 MB |
| **Ziew** | **220 KB** |

That's **680x smaller** than Electron.

## Why Ziew

- **Tiny binaries** — 220KB hello world, real apps under 2MB
- **Native webviews** — Uses system WebView (WebKit, Edge WebView2)
- **No bundled browser** — Unlike Electron's 150MB Chromium
- **Local AI** — First-class llama.cpp bindings + Piper TTS
- **Lua scripting** — Optional LuaJIT for custom backend logic (+~300KB)
- **Cross-compilation** — `zig build -Dtarget=x86_64-windows` just works
- **Simple toolchain** — Zig is ~40MB, not hundreds

## How It Works

**Most apps:** Use built-in JavaScript APIs — no backend code needed.

```javascript
// Built-in APIs - works out of the box
const files = await ziew.fs.readDir('./docs');
const data = await ziew.fs.readFile('./config.json');

// Local AI - runs on device, no API keys
const summary = await ziew.ai.complete('Summarize this...');

// Stream responses with TTS
for await (const token of ziew.ai.stream(prompt)) {
  output.textContent += token;
}
await ziew.ai.speak('Hello world');  // Text-to-speech
```

**Need custom logic?** Add Lua scripting (~300KB overhead):

```lua
-- backend.lua
function processDocument(path)
  local content = ziew.fs.read(path)
  local summary = ziew.ai.complete("Summarize: " .. content)
  return { text = summary, words = #content }
end
```

```javascript
// Call Lua from JavaScript
const result = await ziew.lua.call('processDocument', './report.md');
```

## Platform Support

| Platform | Webview | Status | Dependencies |
|----------|---------|--------|--------------|
| **Linux** | WebKit2GTK | ✅ Ready | `apt install libgtk-3-dev libwebkit2gtk-4.1-dev` |
| **macOS** | WebKit | ✅ Ready | None (built-in) |
| **Windows** | Edge WebView2 | ✅ Ready | None (built-in on Win 10/11) |

## Installation

```bash
# macOS / Linux
curl -fsSL ziew.sh/install | sh

# Windows (PowerShell)
irm ziew.sh/install.ps1 | iex
```

### Manual Build

**Linux prerequisites:**
```bash
sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev
```

**Build:**
```bash
git clone https://github.com/ziews/ziew.git
cd ziew
zig build -Doptimize=ReleaseSmall
./zig-out/bin/hello
```

## Quick Start

```bash
ziew init myapp
cd myapp
ziew dev
```

## Ship Everywhere (Coming Soon)

One command to build for all platforms:

```bash
$ ziew ship

Building for all platforms...

✓ myapp-windows-x64.exe    320 KB
✓ myapp-macos-x64          380 KB
✓ myapp-macos-arm64        360 KB
✓ myapp-linux-x64          340 KB

Total: 1.4 MB (all platforms combined)
```

> Note: `ziew ship` always uses optimized release builds for smallest binary sizes.

## Roadmap

**v0.1 — Foundation**
- [x] Cross-platform webview (GTK/WebKit, Cocoa/WebKit, Edge WebView2)
- [x] JS bridge injection
- [ ] Built-in JS APIs (`ziew.fs`, `ziew.shell`, `ziew.dialog`)
- [ ] `ziew init` / `ziew dev` / `ziew ship` CLI

**v0.2 — Scripting & AI**
- [x] LuaJIT scripting layer (`-Dlua=true`)
- [x] `ziew.ai.complete()` — text generation (llama.cpp)
- [x] `ziew.ai.stream()` — streaming tokens
- [x] JS bridge for `ziew.lua.call()` and `ziew.ai.*`
- [x] `ziew.ai.speak()` — text-to-speech (Piper)
- [x] Chatbot example with streaming TTS
- [ ] `ziew.ai.transcribe()` — speech-to-text (whisper.cpp)

**Future**
- [ ] Plugin system
- [ ] TypeScript definitions generation
- [ ] `ziew docs` — API documentation generation

## Links

- **Website:** [ziew.sh](https://ziew.sh)
- **Install:** [ziew.sh/install](https://ziew.sh/install)
- **GitHub:** [github.com/ziews/ziew](https://github.com/ziews/ziew)

## License

MIT
