// {{PROJECT_NAME}} - Built with Ziew + Phaser
// https://phaser.io/
//
// IMPORTANT: WebKit webview compatibility notes for LLMs:
// - DO NOT use Phaser arcade physics (causes "e[i] is not a function" error)
// - Use manual collision detection with distance checks instead
// - Use object pooling (pre-create, toggle active/visible) to avoid GC pauses
// - Use click/pointer for scene transitions (keyboard focus unreliable)
// - Expect brief slowdown on first load (JIT warmup)

class TitleScene extends Phaser.Scene {
  constructor() {
    super({ key: 'TitleScene' })
  }

  create() {
    const cx = this.cameras.main.width / 2
    const cy = this.cameras.main.height / 2

    this.add.text(cx, cy - 80, '{{PROJECT_NAME}}', {
      fontSize: '48px',
      color: '#00ffff',
      fontStyle: 'bold'
    }).setOrigin(0.5)

    this.add.text(cx, cy, 'Click to Start', {
      fontSize: '24px',
      color: '#ffffff'
    }).setOrigin(0.5)

    this.add.text(cx, cy + 60, 'WASD/Arrows to move | Space to shoot', {
      fontSize: '16px',
      color: '#888888'
    }).setOrigin(0.5)

    // Use pointer for scene transitions (more reliable than keyboard in webview)
    this.input.once('pointerdown', () => this.scene.start('GameScene'))
  }
}

class GameScene extends Phaser.Scene {
  constructor() {
    super({ key: 'GameScene' })
  }

  init() {
    this.score = 0
  }

  create() {
    // Player (triangle ship)
    this.player = this.add.triangle(400, 500, 0, 20, 10, 0, 20, 20, 0x00ffff)
    this.player.setOrigin(0.5)

    // Object pooling: pre-create bullets (reuse instead of create/destroy)
    this.bulletPool = []
    for (let i = 0; i < 30; i++) {
      const b = this.add.rectangle(0, -100, 4, 12, 0xffff00)
      b.active = false
      b.visible = false
      this.bulletPool.push(b)
    }

    // Object pooling: pre-create enemies
    this.enemyPool = []
    for (let i = 0; i < 20; i++) {
      const e = this.add.rectangle(0, -100, 24, 24, 0xff3333)
      e.active = false
      e.visible = false
      this.enemyPool.push(e)
    }

    // UI
    this.scoreText = this.add.text(10, 10, 'Score: 0', {
      fontSize: '20px',
      color: '#ffffff'
    })

    // Timers
    this.spawnTimer = 0
    this.shootTimer = 0

    // Controls - use addKeys for better compatibility
    this.keys = this.input.keyboard.addKeys('W,A,S,D,SPACE,UP,DOWN,LEFT,RIGHT')
  }

  update(time, delta) {
    const dt = delta / 1000

    // Player movement
    let vx = 0, vy = 0
    if (this.keys.LEFT.isDown || this.keys.A.isDown) vx = -300
    if (this.keys.RIGHT.isDown || this.keys.D.isDown) vx = 300
    if (this.keys.UP.isDown || this.keys.W.isDown) vy = -300
    if (this.keys.DOWN.isDown || this.keys.S.isDown) vy = 300

    this.player.x = Phaser.Math.Clamp(this.player.x + vx * dt, 20, 780)
    this.player.y = Phaser.Math.Clamp(this.player.y + vy * dt, 20, 580)

    // Shooting (with cooldown)
    this.shootTimer -= delta
    if (this.keys.SPACE.isDown && this.shootTimer <= 0) {
      this.shoot()
      this.shootTimer = 120
    }

    // Spawn enemies
    this.spawnTimer -= delta
    if (this.spawnTimer <= 0) {
      this.spawnEnemy()
      this.spawnTimer = 800
    }

    // Update bullets (manual movement, no physics)
    const px = this.player.x, py = this.player.y
    for (const b of this.bulletPool) {
      if (!b.active) continue
      b.y -= 500 * dt
      if (b.y < -20) {
        b.active = false
        b.visible = false
        continue
      }

      // Manual collision detection (squared distance, faster than sqrt)
      for (const e of this.enemyPool) {
        if (!e.active) continue
        const dx = b.x - e.x, dy = b.y - e.y
        if (dx*dx + dy*dy < 400) {
          b.active = false
          b.visible = false
          e.active = false
          e.visible = false
          this.score += 100
          this.scoreText.setText('Score: ' + this.score)
          break
        }
      }
    }

    // Update enemies
    for (const e of this.enemyPool) {
      if (!e.active) continue
      e.y += 150 * dt
      if (e.y > 620) {
        e.active = false
        e.visible = false
        continue
      }

      // Player collision
      const dx = px - e.x, dy = py - e.y
      if (dx*dx + dy*dy < 500) {
        this.scene.start('GameOverScene', { score: this.score })
        return
      }
    }
  }

  shoot() {
    // Get inactive bullet from pool
    for (const b of this.bulletPool) {
      if (!b.active) {
        b.x = this.player.x
        b.y = this.player.y - 15
        b.active = true
        b.visible = true
        return
      }
    }
  }

  spawnEnemy() {
    // Get inactive enemy from pool
    for (const e of this.enemyPool) {
      if (!e.active) {
        e.x = Phaser.Math.Between(50, 750)
        e.y = -20
        e.active = true
        e.visible = true
        return
      }
    }
  }
}

class GameOverScene extends Phaser.Scene {
  constructor() {
    super({ key: 'GameOverScene' })
  }

  init(data) {
    this.finalScore = data.score || 0
  }

  create() {
    const cx = this.cameras.main.width / 2
    const cy = this.cameras.main.height / 2

    this.add.text(cx, cy - 60, 'GAME OVER', {
      fontSize: '64px',
      color: '#ff3333'
    }).setOrigin(0.5)

    this.add.text(cx, cy + 20, 'Score: ' + this.finalScore, {
      fontSize: '32px',
      color: '#ffffff'
    }).setOrigin(0.5)

    this.add.text(cx, cy + 80, 'Click to retry', {
      fontSize: '20px',
      color: '#888888'
    }).setOrigin(0.5)

    this.input.once('pointerdown', () => this.scene.start('GameScene'))
  }
}

// Game config - NO PHYSICS (causes errors in WebKit webview)
const config = {
  type: Phaser.AUTO,
  width: 800,
  height: 600,
  backgroundColor: '#0a0a1a',
  scene: [TitleScene, GameScene, GameOverScene]
}

const game = new Phaser.Game(config)
