// {{PROJECT_NAME}} - Built with Ziew + Kaplay
// https://kaplayjs.com/

kaplay({
  width: 800,
  height: 600,
  background: [20, 20, 30],
  scale: 1,
  crisp: true,
})

// Game constants
const SPEED = 240
const JUMP_FORCE = 520
const GRAVITY = 1400

// ============================================
// SCENES
// ============================================

// Title screen
scene("title", () => {
  add([
    text("{{PROJECT_NAME}}", { size: 48 }),
    pos(width() / 2, height() / 2 - 50),
    anchor("center"),
    color(255, 255, 255),
  ])

  add([
    text("Press SPACE to start", { size: 20 }),
    pos(width() / 2, height() / 2 + 50),
    anchor("center"),
    color(150, 150, 150),
  ])

  onKeyPress("space", () => go("game"))
})

// Main game
scene("game", () => {
  setGravity(GRAVITY)

  // Ground
  add([
    rect(width(), 48),
    pos(0, height() - 48),
    color(40, 120, 40),
    area(),
    body({ isStatic: true }),
    "ground"
  ])

  // Player
  const player = add([
    rect(32, 32),
    pos(100, height() - 100),
    color(80, 180, 255),
    area(),
    body(),
    anchor("center"),
    "player"
  ])

  // Score
  let score = 0
  const scoreLabel = add([
    text("Score: 0", { size: 24 }),
    pos(12, 12),
    fixed(),
  ])

  // Controls - snappy arcade style
  onUpdate(() => {
    let moveX = 0
    if (isKeyDown("left") || isKeyDown("a")) moveX -= 1
    if (isKeyDown("right") || isKeyDown("d")) moveX += 1
    player.vel.x = moveX * SPEED
  })

  const jump = () => {
    if (player.isGrounded()) {
      player.jump(JUMP_FORCE)
    }
  }
  onKeyPress("space", jump)
  onKeyPress("up", jump)
  onKeyPress("w", jump)

  // Spawn collectibles
  function spawnCoin() {
    add([
      circle(12),
      pos(rand(50, width() - 50), rand(50, height() - 150)),
      color(255, 215, 0),
      area(),
      anchor("center"),
      "coin"
    ])
  }

  for (let i = 0; i < 5; i++) spawnCoin()

  // Collect coins
  player.onCollide("coin", (coin) => {
    destroy(coin)
    score += 10
    scoreLabel.text = "Score: " + score
    spawnCoin()

    if (score >= 100) {
      go("win", score)
    }
  })

  // Fall off screen
  player.onUpdate(() => {
    if (player.pos.y > height() + 50) {
      go("gameover", score)
    }
  })
})

// Win screen
scene("win", (finalScore) => {
  add([
    text("You Win!", { size: 64 }),
    pos(width() / 2, height() / 2 - 40),
    anchor("center"),
    color(255, 215, 0),
  ])

  add([
    text("Score: " + finalScore, { size: 32 }),
    pos(width() / 2, height() / 2 + 30),
    anchor("center"),
  ])

  add([
    text("Press SPACE to play again", { size: 18 }),
    pos(width() / 2, height() / 2 + 90),
    anchor("center"),
    color(150, 150, 150),
  ])

  onKeyPress("space", () => go("game"))
})

// Game over screen
scene("gameover", (finalScore) => {
  add([
    text("Game Over", { size: 64 }),
    pos(width() / 2, height() / 2 - 40),
    anchor("center"),
    color(255, 80, 80),
  ])

  add([
    text("Score: " + finalScore, { size: 32 }),
    pos(width() / 2, height() / 2 + 30),
    anchor("center"),
  ])

  add([
    text("Press SPACE to retry", { size: 18 }),
    pos(width() / 2, height() / 2 + 90),
    anchor("center"),
    color(150, 150, 150),
  ])

  onKeyPress("space", () => go("game"))
})

// Start at title screen
go("title")
