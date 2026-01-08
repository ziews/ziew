# Ziew Plugins

Official plugins for the Ziew desktop app framework.

## Plugin Architecture

Plugins extend Ziew with native capabilities that webviews can't provide. Each plugin:
- Is optional (doesn't bloat the core)
- Provides both Zig API and JS bridge
- Works across Windows, macOS, and Linux

## Installation

```bash
ziew plugin add <name>     # Install a plugin
ziew plugin list           # List installed plugins
ziew plugin remove <name>  # Remove a plugin
```

---

## Tier 1: Essential

### sqlite
Local database storage using SQLite.

```javascript
// JS API
const db = await ziew.sqlite.open('app.db')
await db.exec('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)')
await db.run('INSERT INTO users (name) VALUES (?)', ['Alice'])
const users = await db.all('SELECT * FROM users')
db.close()
```

**Status:** 🔴 Not implemented

---

### tray
System tray icon with menu support.

```javascript
// JS API
await ziew.tray.create({
  icon: './icon.png',
  tooltip: 'My App',
  menu: [
    { label: 'Show', click: () => ziew.window.show() },
    { label: 'Quit', click: () => ziew.app.quit() }
  ]
})

ziew.tray.on('click', () => ziew.window.toggle())
```

**Status:** 🔴 Not implemented

---

### updater
Auto-update support for deployed applications.

```javascript
// JS API
const update = await ziew.updater.check('https://releases.myapp.com/latest.json')
if (update.available) {
  await ziew.updater.download(update)
  await ziew.updater.install() // Restarts app
}
```

**Status:** 🔴 Not implemented

---

### keychain
Secure credential storage using OS keychain.

```javascript
// JS API
await ziew.keychain.set('myapp', 'api_key', 'sk-secret123')
const key = await ziew.keychain.get('myapp', 'api_key')
await ziew.keychain.delete('myapp', 'api_key')
```

**Status:** 🔴 Not implemented

---

## Tier 2: Common

### notify
System notifications.

```javascript
// JS API
await ziew.notify.send({
  title: 'Download Complete',
  body: 'Your file is ready',
  icon: './icon.png'
})
```

**Status:** 🔴 Not implemented

---

### hotkeys
Global keyboard shortcuts (work even when app unfocused).

```javascript
// JS API
ziew.hotkeys.register('CommandOrControl+Shift+Space', () => {
  ziew.window.toggle()
})

ziew.hotkeys.unregister('CommandOrControl+Shift+Space')
```

**Status:** 🔴 Not implemented

---

### single-instance
Prevent multiple app instances, handle deep links.

```javascript
// JS API
const isPrimary = await ziew.singleInstance.acquire()
if (!isPrimary) {
  // Another instance is running, quit
  ziew.app.quit()
}

ziew.singleInstance.on('second-instance', (args) => {
  // Handle args from second instance launch
  ziew.window.focus()
})
```

**Status:** 🔴 Not implemented

---

### menu
Native application and context menus.

```javascript
// JS API
ziew.menu.setApp([
  {
    label: 'File',
    submenu: [
      { label: 'New', accelerator: 'CommandOrControl+N', click: handleNew },
      { type: 'separator' },
      { label: 'Quit', accelerator: 'CommandOrControl+Q', click: () => ziew.app.quit() }
    ]
  }
])

// Context menu
element.addEventListener('contextmenu', (e) => {
  e.preventDefault()
  ziew.menu.popup([
    { label: 'Copy', click: handleCopy },
    { label: 'Paste', click: handlePaste }
  ])
})
```

**Status:** 🔴 Not implemented

---

## Tier 3: Games

### gamepad
Game controller input.

```javascript
// JS API
ziew.gamepad.on('connected', (pad) => {
  console.log(`Controller connected: ${pad.name}`)
})

ziew.gamepad.on('button', (pad, button, pressed) => {
  if (button === 'a' && pressed) player.jump()
})

ziew.gamepad.on('axis', (pad, axis, value) => {
  if (axis === 'leftX') player.moveX(value)
})

// Polling alternative
const state = ziew.gamepad.getState(0)
if (state.buttons.a) player.jump()
```

**Status:** 🔴 Not implemented

---

### steam
Steamworks integration for Steam distribution.

```javascript
// JS API
await ziew.steam.init(480) // App ID

const user = ziew.steam.user()
console.log(`Playing as: ${user.name}`)

await ziew.steam.achievement.unlock('FIRST_WIN')
await ziew.steam.leaderboard.submit('high_scores', score)
```

**Status:** 🔴 Not implemented

---

## Tier 4: Specialized

### serial
Serial port communication for hardware projects.

```javascript
// JS API
const ports = await ziew.serial.list()
const port = await ziew.serial.open('/dev/ttyUSB0', { baudRate: 9600 })

port.on('data', (data) => {
  console.log('Received:', data)
})

await port.write('Hello Arduino\n')
port.close()
```

**Status:** 🔴 Not implemented

---

### bluetooth
Bluetooth device communication.

```javascript
// JS API
const devices = await ziew.bluetooth.scan({ timeout: 5000 })
const device = await ziew.bluetooth.connect(devices[0].id)

device.on('data', handleData)
await device.write(buffer)
device.disconnect()
```

**Status:** 🔴 Not implemented

---

### midi
MIDI device support for music applications.

```javascript
// JS API
const inputs = await ziew.midi.inputs()
const output = await ziew.midi.openOutput(0)

ziew.midi.on('noteon', (note, velocity, channel) => {
  synth.play(note, velocity)
})

output.noteOn(60, 127, 0) // Middle C
output.noteOff(60, 0)
```

**Status:** 🔴 Not implemented

---

### ultralight
Alternative renderer using Ultralight for consistent cross-platform rendering.

```javascript
// Configured in ziew.config.json, not runtime API
{
  "renderer": "ultralight"
}
```

**Note:** Ultralight has commercial licensing requirements.

**Status:** 🔴 Not implemented

---

## Implementation Priority

1. **sqlite** - Highest impact, enables data-driven apps
2. **tray** - Essential for utilities/background apps
3. **notify** - Quick win, high visibility
4. **single-instance** - Common need, relatively simple
5. **keychain** - Security essential
6. **hotkeys** - Power user feature
7. **menu** - Professional feel
8. **gamepad** - Game-focused
9. **updater** - Complex but critical for distribution
10. **serial** - Specialized
11. **steam** - Specialized
12. **bluetooth** - Specialized
13. **midi** - Specialized
14. **ultralight** - Complex + licensing

---

## Contributing

Plugins follow the standard structure:

```
plugins/<name>/
├── plugin.json       # Metadata
├── src/
│   ├── <name>.zig    # Zig implementation
│   └── bridge.zig    # JS bridge bindings
├── js/
│   └── <name>.js     # JS API wrapper
└── README.md         # Documentation
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for details.
