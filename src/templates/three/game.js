// {{PROJECT_NAME}} - Built with Ziew + Three.js
// https://threejs.org/

import * as THREE from 'three'
import { PointerLockControls } from 'three/addons/controls/PointerLockControls.js'

// ============================================
// SETUP
// ============================================

const scene = new THREE.Scene()
scene.background = new THREE.Color(0x87ceeb) // Sky blue
scene.fog = new THREE.Fog(0x87ceeb, 10, 100)

const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000)
camera.position.set(0, 2, 5)

const renderer = new THREE.WebGLRenderer({ antialias: true })
renderer.setSize(window.innerWidth, window.innerHeight)
renderer.setPixelRatio(window.devicePixelRatio)
renderer.shadowMap.enabled = true
renderer.shadowMap.type = THREE.PCFSoftShadowMap
document.body.appendChild(renderer.domElement)

// ============================================
// LIGHTING
// ============================================

const ambientLight = new THREE.AmbientLight(0xffffff, 0.4)
scene.add(ambientLight)

const directionalLight = new THREE.DirectionalLight(0xffffff, 1)
directionalLight.position.set(10, 20, 10)
directionalLight.castShadow = true
directionalLight.shadow.mapSize.width = 2048
directionalLight.shadow.mapSize.height = 2048
directionalLight.shadow.camera.near = 0.5
directionalLight.shadow.camera.far = 50
directionalLight.shadow.camera.left = -20
directionalLight.shadow.camera.right = 20
directionalLight.shadow.camera.top = 20
directionalLight.shadow.camera.bottom = -20
scene.add(directionalLight)

// ============================================
// WORLD
// ============================================

// Ground
const groundGeometry = new THREE.PlaneGeometry(100, 100)
const groundMaterial = new THREE.MeshStandardMaterial({
  color: 0x3a7d3a,
  roughness: 0.8
})
const ground = new THREE.Mesh(groundGeometry, groundMaterial)
ground.rotation.x = -Math.PI / 2
ground.receiveShadow = true
scene.add(ground)

// Grid helper
const grid = new THREE.GridHelper(100, 100, 0x2d5a2d, 0x2d5a2d)
grid.position.y = 0.01
scene.add(grid)

// Some cubes to look at
const cubeGeometry = new THREE.BoxGeometry(1, 1, 1)
const colors = [0xff6b6b, 0x4ecdc4, 0xffe66d, 0x95e1d3, 0xf38181]

for (let i = 0; i < 20; i++) {
  const material = new THREE.MeshStandardMaterial({
    color: colors[i % colors.length],
    roughness: 0.5,
    metalness: 0.1
  })
  const cube = new THREE.Mesh(cubeGeometry, material)
  cube.position.set(
    (Math.random() - 0.5) * 40,
    0.5 + Math.random() * 2,
    (Math.random() - 0.5) * 40
  )
  cube.castShadow = true
  cube.receiveShadow = true
  scene.add(cube)
}

// ============================================
// CONTROLS
// ============================================

const controls = new PointerLockControls(camera, document.body)

// Click to start
document.addEventListener('click', () => {
  controls.lock()
})

controls.addEventListener('lock', () => {
  document.getElementById('info').style.display = 'none'
})

controls.addEventListener('unlock', () => {
  document.getElementById('info').style.display = 'block'
})

// Movement
const velocity = new THREE.Vector3()
const direction = new THREE.Vector3()
const keys = { w: false, a: false, s: false, d: false, space: false }

document.addEventListener('keydown', (e) => {
  switch (e.code) {
    case 'KeyW': keys.w = true; break
    case 'KeyA': keys.a = true; break
    case 'KeyS': keys.s = true; break
    case 'KeyD': keys.d = true; break
    case 'Space': keys.space = true; break
  }
})

document.addEventListener('keyup', (e) => {
  switch (e.code) {
    case 'KeyW': keys.w = false; break
    case 'KeyA': keys.a = false; break
    case 'KeyS': keys.s = false; break
    case 'KeyD': keys.d = false; break
    case 'Space': keys.space = false; break
  }
})

// ============================================
// GAME LOOP
// ============================================

const clock = new THREE.Clock()
let canJump = true

function animate() {
  requestAnimationFrame(animate)

  const delta = clock.getDelta()
  const speed = 10

  if (controls.isLocked) {
    // Friction
    velocity.x -= velocity.x * 10 * delta
    velocity.z -= velocity.z * 10 * delta
    velocity.y -= 25 * delta // Gravity

    // Direction
    direction.z = Number(keys.w) - Number(keys.s)
    direction.x = Number(keys.d) - Number(keys.a)
    direction.normalize()

    if (keys.w || keys.s) velocity.z -= direction.z * speed * delta
    if (keys.a || keys.d) velocity.x -= direction.x * speed * delta

    // Jump
    if (keys.space && canJump) {
      velocity.y = 8
      canJump = false
    }

    controls.moveRight(-velocity.x * delta * speed)
    controls.moveForward(-velocity.z * delta * speed)
    camera.position.y += velocity.y * delta

    // Ground collision
    if (camera.position.y < 2) {
      velocity.y = 0
      camera.position.y = 2
      canJump = true
    }
  }

  renderer.render(scene, camera)
}

// ============================================
// RESIZE HANDLING
// ============================================

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight
  camera.updateProjectionMatrix()
  renderer.setSize(window.innerWidth, window.innerHeight)
})

// Start
animate()
