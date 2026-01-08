// {{PROJECT_NAME}} - Built with Ziew + Phaser
// https://phaser.io/

// ============================================
// SCENES
// ============================================

class TitleScene extends Phaser.Scene {
  constructor() {
    super({ key: 'TitleScene' })
  }

  create() {
    const centerX = this.cameras.main.width / 2
    const centerY = this.cameras.main.height / 2

    this.add.text(centerX, centerY - 50, '{{PROJECT_NAME}}', {
      fontSize: '48px',
      color: '#ffffff'
    }).setOrigin(0.5)

    this.add.text(centerX, centerY + 50, 'Press SPACE to start', {
      fontSize: '20px',
      color: '#999999'
    }).setOrigin(0.5)

    this.input.keyboard.once('keydown-SPACE', () => {
      this.scene.start('GameScene')
    })
  }
}

class GameScene extends Phaser.Scene {
  constructor() {
    super({ key: 'GameScene' })
    this.score = 0
  }

  create() {
    // Physics world bounds
    this.physics.world.setBounds(0, 0, 800, 600)

    // Ground
    this.ground = this.add.rectangle(400, 576, 800, 48, 0x288028)
    this.physics.add.existing(this.ground, true)

    // Player
    this.player = this.add.rectangle(100, 500, 32, 32, 0x50b4ff)
    this.physics.add.existing(this.player)
    this.player.body.setCollideWorldBounds(true)
    this.player.body.setBounce(0)

    // Collide player with ground
    this.physics.add.collider(this.player, this.ground)

    // Coins group
    this.coins = this.physics.add.group()
    for (let i = 0; i < 5; i++) {
      this.spawnCoin()
    }

    // Collect coins
    this.physics.add.overlap(this.player, this.coins, this.collectCoin, null, this)

    // Score text
    this.scoreText = this.add.text(12, 12, 'Score: 0', {
      fontSize: '24px',
      color: '#ffffff'
    })

    // Controls
    this.cursors = this.input.keyboard.createCursorKeys()
    this.wasd = this.input.keyboard.addKeys({
      up: Phaser.Input.Keyboard.KeyCodes.W,
      down: Phaser.Input.Keyboard.KeyCodes.S,
      left: Phaser.Input.Keyboard.KeyCodes.A,
      right: Phaser.Input.Keyboard.KeyCodes.D
    })
  }

  update() {
    const speed = 240
    const jumpForce = 400

    // Horizontal movement
    let vx = 0
    if (this.cursors.left.isDown || this.wasd.left.isDown) vx = -speed
    if (this.cursors.right.isDown || this.wasd.right.isDown) vx = speed
    this.player.body.setVelocityX(vx)

    // Jump
    const onGround = this.player.body.blocked.down
    const jumpPressed = Phaser.Input.Keyboard.JustDown(this.cursors.space) ||
                        Phaser.Input.Keyboard.JustDown(this.cursors.up) ||
                        Phaser.Input.Keyboard.JustDown(this.wasd.up)
    if (onGround && jumpPressed) {
      this.player.body.setVelocityY(-jumpForce)
    }

    // Fall off screen
    if (this.player.y > 650) {
      this.scene.start('GameOverScene', { score: this.score })
    }
  }

  spawnCoin() {
    const x = Phaser.Math.Between(50, 750)
    const y = Phaser.Math.Between(100, 450)
    const coin = this.add.circle(x, y, 12, 0xffd700)
    this.physics.add.existing(coin, true)
    this.coins.add(coin)
  }

  collectCoin(player, coin) {
    coin.destroy()
    this.score += 10
    this.scoreText.setText('Score: ' + this.score)
    this.spawnCoin()

    if (this.score >= 100) {
      this.scene.start('WinScene', { score: this.score })
    }
  }
}

class WinScene extends Phaser.Scene {
  constructor() {
    super({ key: 'WinScene' })
  }

  init(data) {
    this.finalScore = data.score || 0
  }

  create() {
    const centerX = this.cameras.main.width / 2
    const centerY = this.cameras.main.height / 2

    this.add.text(centerX, centerY - 40, 'You Win!', {
      fontSize: '64px',
      color: '#ffd700'
    }).setOrigin(0.5)

    this.add.text(centerX, centerY + 30, 'Score: ' + this.finalScore, {
      fontSize: '32px',
      color: '#ffffff'
    }).setOrigin(0.5)

    this.add.text(centerX, centerY + 90, 'Press SPACE to play again', {
      fontSize: '18px',
      color: '#999999'
    }).setOrigin(0.5)

    this.input.keyboard.once('keydown-SPACE', () => {
      this.scene.start('GameScene')
    })
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
    const centerX = this.cameras.main.width / 2
    const centerY = this.cameras.main.height / 2

    this.add.text(centerX, centerY - 40, 'Game Over', {
      fontSize: '64px',
      color: '#ff5050'
    }).setOrigin(0.5)

    this.add.text(centerX, centerY + 30, 'Score: ' + this.finalScore, {
      fontSize: '32px',
      color: '#ffffff'
    }).setOrigin(0.5)

    this.add.text(centerX, centerY + 90, 'Press SPACE to retry', {
      fontSize: '18px',
      color: '#999999'
    }).setOrigin(0.5)

    this.input.keyboard.once('keydown-SPACE', () => {
      this.scene.start('GameScene')
    })
  }
}

// ============================================
// GAME CONFIG
// ============================================

const config = {
  type: Phaser.AUTO,
  width: 800,
  height: 600,
  backgroundColor: '#141420',
  physics: {
    default: 'arcade',
    arcade: {
      gravity: { y: 800 },
      debug: false
    }
  },
  scene: [TitleScene, GameScene, WinScene, GameOverScene]
}

const game = new Phaser.Game(config)
