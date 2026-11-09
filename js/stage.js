// The persistent 3D stage behind every screen: a three.js port of Stage/StageDirector.swift
// and Stage/MascotRig.swift. One scene lives for the whole session; screens only move the
// camera and the cast.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { CHARACTERS, COLORS } from './library.js';

const srgb = (r, g, b) => new THREE.Color().setRGB(r, g, b, THREE.SRGBColorSpace);
const GLOW = srgb(1, 0.80, 0.20);   // marquee gold
const ROSE = srgb(1, 0.16, 0.08);   // hot red-orange
const GOLD = srgb(1, 0.70, 0.12);
const CREAM = srgb(1, 0.965, 0.89);
const RED = srgb(1, 0.14, 0.20);
const TARGET_HEIGHT = 1.04;         // the iOS bodies stand ~1.04 m tall at scale 1
const MODEL_SCALE = 0.335;          // MascotRig.modelScale: ~3.1 m source bodies → ~1.04 m

const CLIP_NAMES = { idle: 'Idle', walk: 'Walk', jump: 'Jump', victory: 'Victory', defeat: 'Defeat', hit: 'RecieveHit' };
const ONE_SHOT = new Set(['defeat', 'hit']);

/** Damped spring used for every procedural channel on the mascot. */
class Spring {
  constructor(value, stiffness = 140, damping = 16) {
    this.value = value; this.target = value; this.velocity = 0;
    this.stiffness = stiffness; this.damping = damping;
  }
  step(dt) {
    this.velocity += (this.stiffness * (this.target - this.value) - this.damping * this.velocity) * dt;
    this.value += this.velocity * dt;
  }
  copy(o) { this.value = o.value; this.target = o.target; this.velocity = o.velocity; }
}

// MARK: Materials

function rgbToHsv(r, g, b) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0;
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h /= 6; if (h < 0) h += 1;
  }
  return [h, max === 0 ? 0 : d / max, max];
}

function hsvToRgb(h, s, v) {
  const i = Math.floor(h * 6), f = h * 6 - i;
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6];
}

/**
 * Rich game-show color grade, as in MascotRig.polishMaterials: black faces stay black,
 * pale pieces become warm cream, navy reads royal, and costumes gain density.
 */
function polish(src) {
  const m = new THREE.MeshPhysicalMaterial({
    color: src.color.clone(),
    roughness: src.roughness,
    metalness: 0,
    emissive: src.emissive?.clone() ?? new THREE.Color(0),
    emissiveIntensity: src.emissiveIntensity ?? 1,
    name: src.name,
  });
  const isEye = src.roughness <= 0.15;
  m.roughness = isEye ? 0.09 : Math.min(src.roughness, 0.38);
  m.clearcoat = isEye ? 0.82 : 0.18;
  m.clearcoatRoughness = isEye ? 0.06 : 0.20;
  const c = {}; src.color.getRGB(c, THREE.SRGBColorSpace);
  const [h, sat, b] = rgbToHsv(c.r, c.g, c.b);
  let out;
  if (isEye && b > 0.45) out = [1.0, 0.95, 0.84];
  else if (b < 0.32 && sat < 0.20) {
    out = [0.010, 0.009, 0.012];
    m.clearcoat = isEye ? 0.82 : 0.07;
  } else if (sat < 0.12 && b > 0.55) out = [1.0, 0.95, 0.86];
  else if (h > 0.55 && h < 0.82) out = hsvToRgb(0.60, Math.max(0.82, Math.min(1, sat * 1.25)), Math.max(0.27, Math.min(0.38, b * 1.02)));
  else out = hsvToRgb(h, Math.min(1, sat * 1.38 + 0.035), Math.min(0.94, b * 1.10 + 0.055));
  m.color.setRGB(out[0], out[1], out[2], THREE.SRGBColorSpace);
  return m;
}

// MARK: Rig

class Rig {
  constructor(template, characterID, seed) {
    this.character = characterID;
    this.seed = seed;
    this.root = new THREE.Group();
    this.mover = new THREE.Group();
    this.hopper = new THREE.Group();
    this.model = cloneSkinned(template.scene);
    this.model.scale.setScalar(template.scale);
    this.model.traverse((o) => {
      if (o.isMesh) { o.castShadow = true; o.frustumCulled = false; }
    });
    this.hopper.add(this.model);
    this.mover.add(this.hopper);
    this.root.add(this.mover);

    const hit = new THREE.Mesh(new THREE.BoxGeometry(0.62, 1.12, 0.52).translate(0, 0.56, 0),
      new THREE.MeshBasicMaterial({ visible: false }));
    hit.userData.rig = this;
    this.mover.add(hit);
    this.hit = hit;

    this.mixer = new THREE.AnimationMixer(this.model);
    this.actions = {};
    for (const [key, name] of Object.entries(CLIP_NAMES)) {
      const clip = template.clips.find((c) => c.name === name);
      if (!clip) continue;
      const a = this.mixer.clipAction(clip);
      if (ONE_SHOT.has(key)) { a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; }
      this.actions[key] = a;
    }
    this.mood = 'idle';
    this.placement = new THREE.Vector3();
    this.scale = 1;
    this.facing = 0;
    this.x = new Spring(0, 60, 13);
    this.z = new Spring(0, 60, 13);
    this.size = new Spring(0, 90, 12);
    this.yaw = new Spring(0, 50, 10);
    this.spin = 0; this.spinVelocity = 0;
    this.squash = new Spring(0, 260, 11);
    this.leanZ = new Spring(0, 70, 10);
    this.leanX = new Spring(0, 70, 10);
    this.hopY = 0; this.hopVelocity = 0;
    this.reactingUntil = 0;
    this.time = 0;
    this.playing = null;
    this.current = null;
    this.mover.scale.setScalar(0);
    this.root.visible = false;
    this.play('idle', 0);
    // Start each idle at a different point so the cast never moves in lockstep.
    this.mixer.update(seed % 3);
  }

  play(clip, blend = 0.25) {
    if (clip === this.playing) return;
    const next = this.actions[clip];
    if (!next) return;
    this.playing = clip;
    const prev = this.current;
    this.current = next;
    if (prev === next) { next.reset().play(); return; }
    next.reset();
    next.setEffectiveTimeScale(1);
    next.setEffectiveWeight(1);
    next.play();
    if (prev && blend > 0) prev.crossFadeTo(next, blend, false);
    else if (prev) prev.stop();
  }

  settle() {
    this.x.value = this.placement.x; this.z.value = this.placement.z;
    this.x.velocity = 0; this.z.velocity = 0;
    this.yaw.value = this.facing; this.yaw.velocity = 0;
  }

  takeOver(other) {
    this.x.copy(other.x); this.z.copy(other.z); this.yaw.copy(other.yaw);
    this.size.value = other.size.value * 0.6;
    this.hop(0.9);
    this.spinVelocity += 10;
  }

  poke() {
    this.hop(1.1);
    this.spinVelocity += 12;
    this.squash.velocity += 4;
    this.reactingUntil = this.time + 0.6;
    this.playing = null;
    this.play('hit', 0.1);
  }

  beat() { this.squash.velocity += 3.5; }

  hop(strength = 1) {
    if (this.hopY > 0.001) return;
    this.squash.velocity += 3;
    this.hopVelocity = 2.0 * strength;
  }

  update(dt, t, level) {
    this.time = t;
    const ft = t + this.seed;
    const moving = Math.abs(this.x.velocity) + Math.abs(this.z.velocity) > 0.35;
    if (t >= this.reactingUntil) {
      switch (this.mood) {
        case 'happy': this.play('jump'); break;
        case 'celebrate': this.play('victory'); break;
        case 'sad': this.play('defeat'); break;
        default: this.play(moving ? 'walk' : 'idle');
      }
    }

    let breath = 0, lz = 0, lx = 0;
    switch (this.mood) {
      case 'listening': lz = 0.12 + Math.sin(ft * 3) * 0.04; lx = 0.06; breath = Math.abs(Math.sin(ft * 3)) * 0.03; break;
      case 'ready': breath = Math.abs(Math.sin(ft * 6)) * 0.03; break;
      case 'recording': breath = -level * 0.12; lx = -0.08 - level * 0.08; lz = Math.sin(ft * 9) * 0.05 * level; break;
      case 'thinking': lz = 0.08 + Math.sin(ft * 1.2) * 0.04; break;
      default: break;
    }

    const steps = Math.max(1, Math.ceil(dt / (1 / 120)));
    const h = dt / steps;
    this.x.target = this.placement.x; this.z.target = this.placement.z;
    this.size.target = this.scale; this.yaw.target = this.facing;
    this.squash.target = breath;
    this.leanZ.target = lz; this.leanX.target = lx;
    for (let i = 0; i < steps; i++) {
      this.x.step(h); this.z.step(h); this.size.step(h); this.yaw.step(h);
      this.squash.step(h); this.leanZ.step(h); this.leanX.step(h);
      if (this.hopY > 0 || this.hopVelocity > 0) {
        this.hopVelocity -= 9.8 * h;
        this.hopY += this.hopVelocity * h;
        if (this.hopY <= 0) {
          this.hopY = 0;
          this.squash.velocity += Math.min(4, Math.abs(this.hopVelocity) * 1.6);
          this.hopVelocity = 0;
        }
      }
      this.spin += this.spinVelocity * h;
      this.spinVelocity *= Math.max(0, 1 - 2.8 * h);
    }
    if (Math.abs(this.spinVelocity) < 1.5) {
      const rest = Math.round(this.spin / (2 * Math.PI)) * 2 * Math.PI;
      this.spin += (rest - this.spin) * Math.min(1, 6 * dt);
    }

    this.root.visible = this.scale > 0 || this.size.value > 0.01;
    if (!this.root.visible) return;
    this.mixer.update(dt);

    // RealityKit's yaw turns toward +x for positive angles; three.js matches with the same sign.
    const heading = moving ? Math.atan2(this.x.velocity, this.z.velocity) : this.yaw.value;
    this.mover.position.set(this.x.value, this.placement.y, this.z.value);
    this.mover.scale.setScalar(Math.max(0.0001, this.size.value));
    this.mover.rotation.set(0, heading + this.spin, 0);
    const s = this.squash.value;
    this.hopper.position.set(0, this.hopY, 0);
    this.hopper.scale.set(1 + s * 0.5, 1 - s, 1 + s * 0.5);
    this.hopper.rotation.set(this.leanX.value, 0, this.leanZ.value, 'ZXY');
  }

  dispose() {
    this.mixer.stopAllAction();
    this.root.removeFromParent();
  }
}

// MARK: Meshes

function roundedDisc(radius, height, bevel, segments = 72) {
  const h = height / 2, inner = radius - bevel;
  const pts = [new THREE.Vector2(0, -h), new THREE.Vector2(inner * 0.5, -h)];
  for (let k = 0; k <= 6; k++) {
    const a = (k / 6) * (Math.PI / 2);
    pts.push(new THREE.Vector2(inner + bevel * Math.sin(a), -h + bevel - bevel * Math.cos(a)));
  }
  for (let k = 0; k <= 6; k++) {
    const a = (k / 6) * (Math.PI / 2);
    pts.push(new THREE.Vector2(inner + bevel * Math.cos(a), h - bevel + bevel * Math.sin(a)));
  }
  pts.push(new THREE.Vector2(inner * 0.5, h), new THREE.Vector2(0.0001, h));
  return new THREE.LatheGeometry(pts, segments);
}

function flatTorus(radius, tube, segments = 128, sides = 12) {
  return new THREE.TorusGeometry(radius, tube, sides, segments).rotateX(Math.PI / 2);
}

function crownGeometry(width, height) {
  const w = width / 2, h = height / 2;
  const s = new THREE.Shape();
  const pts = [[-w, -h], [-w, -h * 0.12], [-w * 0.58, h * 0.72], [-w * 0.18, h * 0.05], [0, h],
    [w * 0.18, h * 0.05], [w * 0.58, h * 0.72], [w, -h * 0.12], [w, -h]];
  s.moveTo(pts[0][0], pts[0][1]);
  for (const [x, y] of pts.slice(1)) s.lineTo(x, y);
  s.closePath();
  return new THREE.ShapeGeometry(s);
}

const unlit = (color, opacity = 1) => new THREE.MeshBasicMaterial({
  color, toneMapped: false, transparent: opacity < 1, opacity, depthWrite: opacity >= 1,
});

function gradientEnvironment(renderer, top, horizon, bottom) {
  const c = document.createElement('canvas');
  c.width = 256; c.height = 128;
  const g = c.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 128);
  const css = (v) => `rgb(${v.map((x) => Math.round(x * 255)).join(',')})`;
  grad.addColorStop(0, css(top)); grad.addColorStop(0.52, css(horizon)); grad.addColorStop(1, css(bottom));
  g.fillStyle = grad; g.fillRect(0, 0, 256, 128);
  const tex = new THREE.CanvasTexture(c);
  tex.mapping = THREE.EquirectangularReflectionMapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const env = pmrem.fromEquirectangular(tex).texture;
  tex.dispose(); pmrem.dispose();
  return env;
}

function softDot() {
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const r = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.35, 'rgba(255,255,255,0.7)'); r.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = r; g.fillRect(0, 0, 64, 64);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// MARK: Stage

export class Stage {
  constructor(canvas, handlers = {}) {
    this.canvas = canvas;
    this.handlers = handlers;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.NeutralToneMapping;
    this.renderer.toneMappingExposure = 1.0;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.scene.environment = gradientEnvironment(this.renderer, [0.50, 0.46, 0.50], [0.78, 0.70, 0.60], [0.11, 0.04, 0.055]);
    this.scene.environmentIntensity = 0.95;
    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 60);
    this.cameraPosition = new THREE.Vector3(0, 1.1, 4);
    this.cameraTarget = new THREE.Vector3(0, 0.3, 0);
    this.cameraGoal = [new THREE.Vector3(0, 1.4, 6), new THREE.Vector3(0, 0.28, 0)];
    this.reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.time = 0;
    this.sidePanel = 0;
    this.lastLevelPeak = 0;
    this.level = () => 0;

    this.rigs = new Map();       // player id → Rig
    this.showcase = new Map();   // character id → Rig
    this.templates = new Map();  // character id → { scene, clips, scale }
    this.loading = new Map();
    this.state = { screen: 'home', members: [], ranking: [], beat: 0, pokes: 0, homeCharacter: 'pirateGal' };

    this.buildSet();
    this.bindInput();
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);

    this.resize();
    new ResizeObserver(() => this.resize()).observe(canvas);
    this.clock = new THREE.Clock();
    this.renderer.setAnimationLoop(() => this.frame());
  }

  buildSet() {
    const S = this.scene;

    const key = new THREE.DirectionalLight(srgb(1, 0.96, 0.88), 2.4);
    key.position.set(1.6, 4, 3);
    key.target.position.set(0, 0.4, 0);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    Object.assign(key.shadow.camera, { left: -3, right: 3, top: 3, bottom: -3, near: 0.5, far: 12 });
    key.shadow.bias = -0.0008;
    key.shadow.normalBias = 0.02;
    key.shadow.radius = 4;
    S.add(key, key.target);

    // Gold rim light separates the cast from the red background; a warm fill from the right.
    const rim = new THREE.PointLight(GLOW, 26, 9, 2);
    rim.position.set(-1.8, 2.2, -2.2);
    const fill = new THREE.PointLight(srgb(1, 0.58, 0.32), 12, 8, 2);
    fill.position.set(1.9, 2.0, -2.0);
    const front = new THREE.PointLight(srgb(1, 0.86, 0.72), 6, 12, 2);
    front.position.set(0, 2.2, 4.5);
    S.add(rim, fill, front);

    const stage = new THREE.Mesh(roundedDisc(1.95, 0.32, 0.09),
      new THREE.MeshPhysicalMaterial({ color: srgb(0.52, 0.10, 0.055), roughness: 0.30, clearcoat: 0.82, envMapIntensity: 0.5 }));
    stage.position.y = -0.16;
    stage.receiveShadow = true;
    S.add(stage);

    const top = new THREE.Mesh(roundedDisc(1.68, 0.045, 0.018),
      new THREE.MeshPhysicalMaterial({ color: srgb(0.96, 0.34, 0.065), roughness: 0.22, clearcoat: 1, envMapIntensity: 0.35 }));
    top.receiveShadow = true;
    S.add(top);

    // The bright inner pool of light, unlit like the iOS stage.
    const pool = new THREE.Mesh(roundedDisc(1.30, 0.018, 0.008), unlit(srgb(1, 0.58, 0.10)));
    pool.position.y = 0.035;
    S.add(pool);
    // Contact shadows on the pool: a shadow-only layer just above it.
    const shade = new THREE.Mesh(new THREE.CircleGeometry(1.3, 72).rotateX(-Math.PI / 2), new THREE.ShadowMaterial({ opacity: 0.32 }));
    shade.position.y = 0.046;
    shade.receiveShadow = true;
    S.add(shade);

    const innerRing = new THREE.Mesh(flatTorus(1.34, 0.036), unlit(CREAM));
    innerRing.position.y = 0.055;
    S.add(innerRing);

    this.ringMaterial = unlit(GLOW.clone());
    this.ring = new THREE.Mesh(flatTorus(1.73, 0.05), this.ringMaterial);
    S.add(this.ring);

    const bulbGeo = new THREE.SphereGeometry(0.025, 12, 8);
    const bulbMat = unlit(CREAM);
    for (let i = 0; i < 18; i++) {
      const a = (i / 18) * Math.PI * 2;
      const bulb = new THREE.Mesh(bulbGeo, bulbMat);
      bulb.position.set(1.58 * Math.cos(a), 0.075, 1.58 * Math.sin(a));
      S.add(bulb);
    }

    const outer = new THREE.Mesh(flatTorus(2.6, 0.01, 128, 8), unlit(ROSE));
    outer.position.y = -0.3;
    S.add(outer);

    // Soft beams of light over the stage.
    const beam = new THREE.Mesh(new THREE.ConeGeometry(1.35, 4.5, 48, 1, true), unlit(srgb(1, 0.30, 0.10), 0.075));
    beam.material.side = THREE.DoubleSide;
    beam.position.y = 2.25;
    S.add(beam);
    for (const x of [-1.75, 1.75]) {
      const side = new THREE.Mesh(new THREE.ConeGeometry(1.15, 5.2, 48, 1, true), unlit(srgb(1, 0.52, 0.08), 0.055));
      side.material.side = THREE.DoubleSide;
      side.position.set(x, 2.55, -0.7);
      S.add(side);
    }

    const crown = new THREE.Mesh(crownGeometry(4.2, 2.5), unlit(srgb(1, 0.08, 0.20), 0.24));
    crown.position.set(0, 1.5, -1.9);
    S.add(crown);

    // Shockwave rings, recycled.
    this.shockwaves = [];
    for (let i = 0; i < 4; i++) {
      const m = unlit(GLOW.clone(), 0.99);
      const wave = new THREE.Mesh(flatTorus(1, 0.012, 96, 6), m);
      wave.position.y = 0.03;
      wave.visible = false;
      S.add(wave);
      this.shockwaves.push({ mesh: wave, age: 10, strength: 1 });
    }

    // Podium blocks: 2nd, 1st, 3rd from left to right.
    this.podium = new THREE.Group();
    this.podiumRise = new Spring(0, 60, 11);
    const specs = [[-0.95, 0.38, srgb(0.75, 0.78, 0.9)], [0, 0.6, GLOW], [0.95, 0.24, srgb(1, 0.28, 0.45)]];
    for (const [x, h, c] of specs) {
      const block = new THREE.Mesh(new RoundedBoxGeometry(0.85, h, 0.85, 3, 0.06),
        new THREE.MeshPhysicalMaterial({ color: srgb(0.26, 0.04, 0.09), roughness: 0.3, clearcoat: 1 }));
      block.position.set(x, h / 2, 0);
      block.castShadow = true;
      block.receiveShadow = true;
      const cap = new THREE.Mesh(new RoundedBoxGeometry(0.87, 0.025, 0.87, 2, 0.012), unlit(c));
      cap.position.y = h / 2;
      block.add(cap);
      this.podium.add(block);
    }
    this.podium.scale.y = 0.001;
    this.podium.visible = false;
    S.add(this.podium);

    this.buildDust();
    this.buildConfetti();
  }

  buildDust() {
    const N = 150;
    const pos = new Float32Array(N * 3), col = new Float32Array(N * 3);
    this.dust = Array.from({ length: N }, (_, i) => {
      const p = { age: Math.random() * 5, life: 4 + Math.random() * 2, v: new THREE.Vector3(), c: new THREE.Color() };
      this.respawnMote(p, true);
      return p;
    });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
    const mat = new THREE.PointsMaterial({
      size: 0.045, map: softDot(), vertexColors: true, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, toneMapped: false, sizeAttenuation: true,
    });
    this.dustPoints = new THREE.Points(geo, mat);
    this.dustPoints.frustumCulled = false;
    this.scene.add(this.dustPoints);
  }

  respawnMote(p, anywhere = false) {
    p.p = new THREE.Vector3((Math.random() - 0.5) * 7, 1.4 + (Math.random() - 0.5) * 3, -0.5 + (Math.random() - 0.5) * 4);
    p.v.set((Math.random() - 0.5) * 0.08, (Math.random() - 0.3) * 0.06, (Math.random() - 0.5) * 0.05);
    p.c.copy(srgb(1, 0.52, 0.08)).lerp(srgb(1, 0.92, 0.42), Math.random()).multiplyScalar(0.7);
    p.age = anywhere ? Math.random() * p.life : 0;
  }

  buildConfetti() {
    const MAX = 1100;
    const geo = new THREE.PlaneGeometry(1, 0.62);
    const mat = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide, toneMapped: false });
    this.confettiMesh = new THREE.InstancedMesh(geo, mat, MAX);
    this.confettiMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.confettiMesh.frustumCulled = false;
    this.confettiMesh.count = 0;
    this.confettiMesh.setColorAt(0, new THREE.Color());
    this.scene.add(this.confettiMesh);
    this.confetti = [];
  }

  burstConfetti(small = false) {
    if (this.reduceMotion) return;
    const pairs = [[GOLD, GLOW], [RED, CREAM], [GOLD, RED]];
    const perEmitter = small ? 45 : 315;
    const duration = small ? 0.15 : 0.35;
    const width = small ? 1.5 : 3.2;
    this.confetti = [];
    for (const [a, b] of pairs) {
      for (let i = 0; i < perEmitter; i++) {
        const spread = (Math.random() - 0.5) * 2 * 1.2;
        const turn = Math.random() * Math.PI * 2;
        const speed = 0.6 + (Math.random() - 0.5) * 0.8;
        const dir = new THREE.Vector3(Math.sin(spread) * Math.cos(turn), Math.cos(spread), Math.sin(spread) * Math.sin(turn));
        this.confetti.push({
          delay: Math.random() * duration,
          age: 0,
          life: 3.2,
          p: new THREE.Vector3((Math.random() - 0.5) * width, 3.2 + (Math.random() - 0.5) * 0.1, 0.3 + (Math.random() - 0.5) * 1),
          v: dir.multiplyScalar(Math.max(0.05, speed)),
          axis: new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize(),
          angle: Math.random() * Math.PI * 2,
          spin: 4 + (Math.random() - 0.5) * 6,
          size: 0.035 + (Math.random() - 0.5) * 0.03,
          phase: Math.random() * 10,
          color: a.clone().lerp(b, Math.random()),
        });
      }
    }
    this.confetti.forEach((c, i) => this.confettiMesh.setColorAt(i, c.color));
    this.confettiMesh.instanceColor.needsUpdate = true;
    this.confettiMesh.count = this.confetti.length;
  }

  emitShockwave(strength) {
    if (this.reduceMotion) return;
    const w = this.shockwaves.reduce((a, b) => (a.age > b.age ? a : b));
    w.age = 0;
    w.strength = Math.max(0.3, Math.min(1, strength));
    w.mesh.material.color.copy(this.ringMaterial.color);
    w.mesh.visible = true;
  }

  // MARK: Cast loading

  /** Loads characters in order of need: whoever is on screen first, the rest in the background. */
  preload(order) {
    const queue = [...new Set(order)].filter((id) => !this.templates.has(id) && !this.loading.has(id));
    let active = 0;
    const next = () => {
      while (active < 3 && queue.length) {
        const id = queue.shift();
        if (this.templates.has(id) || this.loading.has(id)) continue;
        active++;
        this.loadCharacter(id).catch(() => {}).finally(() => { active--; next(); });
      }
    };
    next();
  }

  loadCharacter(id) {
    if (this.templates.has(id)) return Promise.resolve(this.templates.get(id));
    if (this.loading.has(id)) return this.loading.get(id);
    const ch = CHARACTERS.find((c) => c.id === id);
    // Retry a flaky connection a few times before giving up on a character.
    const attempt = (n) => this.loader.loadAsync(`models/${ch.asset}.glb`).catch((e) =>
      n < 3 ? new Promise((r) => setTimeout(r, 800 * (n + 1))).then(() => attempt(n + 1)) : Promise.reject(e));
    const p = attempt(0).then((gltf) => {
      const scene = gltf.scene;
      const cache = new Map();
      scene.traverse((o) => {
        if (!o.isMesh) return;
        const swap = (m) => { if (!cache.has(m)) cache.set(m, polish(m)); return cache.get(m); };
        o.material = Array.isArray(o.material) ? o.material.map(swap) : swap(o.material);
      });
      scene.updateMatrixWorld(true);
      scene.traverse((o) => { if (o.isSkinnedMesh) o.skeleton.update(); });
      const box = new THREE.Box3().setFromObject(scene);
      const height = box.max.y - box.min.y;
      // Same fixed scale as MascotRig.modelScale: bodies match, hats and hair add height.
      const scale = height > 0.2 && height < 50 ? MODEL_SCALE : TARGET_HEIGHT / 3.1;
      const template = { scene, clips: gltf.animations, scale, height };
      this.templates.set(id, template);
      this.loading.delete(id);
      this.sync(this.state, true);
      this.handlers.onCharacterLoaded?.(id);
      return template;
    }).catch((e) => {
      this.loading.delete(id);
      console.warn('Could not load character', id, e);
      throw e;
    });
    this.loading.set(id, p);
    return p;
  }

  // MARK: State sync

  sync(next, force = false) {
    const old = this.state;
    this.state = next;

    const ids = new Set(next.members.map((m) => m.id));
    for (const [id, rig] of this.rigs) {
      if (!ids.has(id)) { rig.dispose(); this.rigs.delete(id); }
    }
    next.members.forEach((member, i) => {
      const existing = this.rigs.get(member.id);
      if (existing?.character === member.character) return;
      const template = this.templates.get(member.character);
      if (!template) { this.preload([member.character]); return; }
      const rig = new Rig(template, member.character, i * 1.37 + 0.4);
      this.scene.add(rig.root);
      if (existing) { rig.takeOver(existing); existing.dispose(); }
      this.rigs.set(member.id, rig);
    });

    const fresh = [];
    CHARACTERS.forEach((ch, i) => {
      if (this.showcase.has(ch.id)) return;
      const template = this.templates.get(ch.id);
      if (!template) return;
      const rig = new Rig(template, ch.id, i * 0.91 + 2.3);
      this.scene.add(rig.root);
      this.showcase.set(ch.id, rig);
      fresh.push(rig);
    });

    const turnScreens = new Set(['handoff', 'turn', 'reveal']);
    const focusMember = next.members.find((m) => m.id === next.focusID);
    const ring = turnScreens.has(next.screen) && focusMember
      ? srgb(...COLORS[focusMember.color].rgb) : GLOW;
    this.ringMaterial.color.copy(ring);

    this.layout();
    for (const rig of fresh) rig.settle();

    if (force) return;
    if (next.beat !== old.beat) { this.focusRig?.beat(); this.emitShockwave(0.6); }
    if (next.pokes !== old.pokes) {
      const target = next.screen === 'home' ? this.showcase.get(next.homeCharacter) : this.focusRig;
      ((next.pokeID && this.rigs.get(next.pokeID)) || target)?.poke();
      this.emitShockwave(0.8);
    }
    if (next.screen !== old.screen) {
      if (next.screen === 'podium') this.burstConfetti();
      if (next.screen === 'handoff' || next.screen === 'reveal') { this.focusRig?.hop(1.1); this.emitShockwave(1); }
      if (next.screen === 'reveal' && next.mood === 'happy') this.burstConfetti(true);
    }
  }

  get focusRig() { return this.state.focusID ? this.rigs.get(this.state.focusID) : null; }

  layout() {
    const st = this.state;
    const members = st.members;
    const count = members.length;
    const focus = st.focusID;

    const lineup = (order, spacing, scale, z = 0) => {
      const width = spacing * Math.max(order.length - 1, 0);
      order.forEach((id, i) => {
        const rig = this.rigs.get(id);
        if (!rig) return;
        const x = -width / 2 + i * spacing;
        rig.placement.set(x, 0, z - Math.abs(x) * 0.28);
        rig.scale = scale;
        rig.facing = -x * 0.18;
      });
    };
    const audience = (front) => {
      members.map((m) => m.id).filter((id) => id !== front).forEach((id, i) => {
        const rig = this.rigs.get(id);
        if (!rig) return;
        const side = i % 2 === 0 ? 1 : -1;
        const row = Math.floor(i / 2);
        rig.placement.set(side * (1.0 + row * 0.45), 0, -0.45 - row * 0.45);
        rig.scale = 0.62 - row * 0.06;
        rig.facing = -side * 0.45;
      });
    };
    const spacingFor = () => (count > 5 ? [0.62, 0.66] : count > 3 ? [0.8, 0.82] : [0.95, 1]);

    if (st.screen !== 'home') for (const rig of this.showcase.values()) rig.scale = 0;
    this.podium.visible = st.screen === 'podium' || this.podiumRise.value > 0.01;
    this.podiumRise.target = st.screen === 'podium' ? 1 : 0;

    switch (st.screen) {
      case 'home': {
        for (const rig of this.rigs.values()) { rig.placement.set(0, 0, -1.6); rig.scale = 0; }
        const n = CHARACTERS.length;
        const selected = Math.max(0, CHARACTERS.findIndex((c) => c.id === st.homeCharacter));
        CHARACTERS.forEach((ch, i) => {
          const rig = this.showcase.get(ch.id);
          if (!rig) return;
          let rel = i - selected;
          if (rel > n / 2) rel -= n;
          if (rel < -n / 2) rel += n;
          const side = Math.sign(rel);
          if (rel === 0) { rig.placement.set(0, 0.26, 0.22); rig.scale = 1.30; rig.facing = 0; }
          else if (Math.abs(rel) === 1) { rig.placement.set(side * 0.92, 0.14, -0.62); rig.scale = 0.74; rig.facing = -side * 0.45; }
          else { rig.placement.set(side * 1.8, 0, -1.1); rig.scale = 0; rig.facing = 0; }
          rig.mood = 'idle';
        });
        this.setCamera([0, 1.4, 6.0], [0, 0.28, 0]);
        break;
      }
      case 'crew':
      case 'packs': {
        const [spacing, scale] = spacingFor();
        lineup(members.map((m) => m.id), spacing, scale);
        for (const [id, rig] of this.rigs) {
          rig.mood = st.screen === 'packs' ? 'happy' : 'idle';
          if (id === focus && st.screen === 'crew') { rig.placement.z += 0.35; rig.scale = scale * 1.15; }
        }
        const wide = count * spacing * 0.5;
        this.setCamera([0, 1.7, 6.6 + wide * 1.1], [0, -0.7 - wide * 0.1, 0]);
        break;
      }
      case 'handoff':
      case 'turn':
      case 'reveal': {
        audience(focus);
        const rig = focus ? this.rigs.get(focus) : null;
        if (rig) { rig.placement.set(0, 0, 0.25); rig.scale = 1.15; rig.facing = 0; rig.mood = st.mood; }
        for (const [id, r] of this.rigs) if (id !== focus) r.mood = st.audienceMood;
        if (st.screen === 'turn') this.setCamera([0, 1.2, 6.0], [0, 0.02, 0]);
        else this.setCamera([0, 1.4, 6.2], [0, -0.2, 0]);
        break;
      }
      case 'recap': {
        const [spacing, scale] = spacingFor();
        const order = [];
        st.ranking.forEach((id, i) => { if (i % 2 === 0) order.push(id); else order.unshift(id); });
        lineup(order, spacing, scale);
        for (const [id, rig] of this.rigs) {
          rig.mood = id === st.ranking[0] ? 'celebrate' : 'idle';
          if (id === st.ranking[0]) { rig.placement.z += 0.3; rig.scale = scale * 1.15; }
        }
        const wide = count * spacing * 0.5;
        this.setCamera([0, 1.7, 6.6 + wide * 1.1], [0, -0.7 - wide * 0.1, 0]);
        break;
      }
      case 'podium': {
        const spots = [[0, 0.6, 0], [-0.95, 0.38, 0], [0.95, 0.24, 0]];
        const rest = st.ranking.slice(3);
        st.ranking.forEach((id, i) => {
          const rig = this.rigs.get(id);
          if (!rig) return;
          if (i < 3) {
            rig.placement.set(...spots[i]);
            rig.scale = i === 0 ? 0.95 : 0.8;
            rig.facing = -spots[i][0] * 0.2;
            rig.mood = i === 0 ? 'celebrate' : 'happy';
          } else {
            const j = rest.indexOf(id);
            rig.placement.set((j - (rest.length - 1) / 2) * 0.62, 0, -1.4);
            rig.scale = 0.5; rig.facing = 0; rig.mood = 'happy';
          }
        });
        this.setCamera([0, 1.6, 8.5], [0, -0.1, 0]);
        break;
      }
      default: break;
    }
  }

  setCamera(position, target) {
    // With the controls in a side column nothing covers the bottom of the stage, so the
    // camera rises a little and the cast sits nearer the middle of the free space.
    const lift = this.sidePanel > 0 ? 0.38 : 0;
    this.cameraGoal[0].set(position[0], position[1] + lift, position[2]);
    this.cameraGoal[1].set(target[0], target[1] + lift, target[2]);
  }

  // MARK: Input

  bindInput() {
    const ray = new THREE.Raycaster();
    let down = null;
    this.canvas.addEventListener('pointerdown', (e) => { down = { x: e.clientX, y: e.clientY, t: performance.now() }; });
    this.canvas.addEventListener('pointerup', (e) => {
      if (!down) return;
      const dx = e.clientX - down.x, dy = e.clientY - down.y;
      down = null;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { this.handlers.onSwipe?.(dx < 0 ? 1 : -1); return; }
      if (Math.hypot(dx, dy) > 12) return;
      const r = this.canvas.getBoundingClientRect();
      const ndc = new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
      ray.setFromCamera(ndc, this.camera);
      const targets = [];
      for (const rig of [...this.rigs.values(), ...this.showcase.values()]) if (rig.root.visible && rig.scale > 0) targets.push(rig.hit);
      const hit = ray.intersectObjects(targets, false)[0];
      if (!hit) return;
      const rig = hit.object.userData.rig;
      for (const [id, r] of this.rigs) if (r === rig) { this.handlers.onTapMember?.(id); return; }
      for (const [id, r] of this.showcase) if (r === rig) { this.handlers.onTapShowcase?.(id); return; }
    });
    this.canvas.addEventListener('pointercancel', () => { down = null; });
  }

  // MARK: Layout

  setSidePanel(width) {
    if (this.sidePanel === width) return;
    this.sidePanel = width;
    this.resize();
    this.layout();
  }

  resize() {
    const w = Math.max(1, this.canvas.clientWidth), h = Math.max(1, this.canvas.clientHeight);
    this.renderer.setPixelRatio(Math.min(devicePixelRatio || 1, w * h > 2.2e6 ? 1.5 : 2));
    this.renderer.setSize(w, h, false);
    const side = this.sidePanel;
    this.camera.aspect = (w + side) / h;
    if (side > 0) this.camera.setViewOffset(w + side, h, side, 0, w, h);
    else this.camera.clearViewOffset();
    this.camera.updateProjectionMatrix();
  }

  // MARK: Frame loop

  /** Stops drawing while the game is scrolled out of view or the tab is hidden. */
  setPaused(paused) {
    if (this.paused === paused) return;
    this.paused = paused;
    this.renderer.setAnimationLoop(paused ? null : () => this.frame());
    if (!paused) this.clock.getDelta();
  }

  frame() {
    const dt = Math.min(this.clock.getDelta(), 1 / 20);
    this.time += dt;
    const t = this.time;
    const level = this.level();
    const focus = this.focusRig;

    for (const rig of this.rigs.values()) rig.update(dt, t, rig === focus ? level : 0);
    for (const rig of this.showcase.values()) rig.update(dt, t, 0);

    const k = Math.min(1, 2.6 * dt);
    this.cameraPosition.lerp(this.cameraGoal[0], k);
    this.cameraTarget.lerp(this.cameraGoal[1], k);
    const drift = this.reduceMotion ? [0, 0] : [Math.sin(t * 0.21) * 0.08, Math.sin(t * 0.17) * 0.04];
    this.camera.position.set(this.cameraPosition.x + drift[0], this.cameraPosition.y + drift[1], this.cameraPosition.z);
    this.camera.lookAt(this.cameraTarget);

    if (level > 0.45 && t - this.lastLevelPeak > 0.22) { this.lastLevelPeak = t; this.emitShockwave(level); }
    this.ring.scale.setScalar(1 + level * 0.06);

    for (const w of this.shockwaves) {
      w.age += dt;
      if (w.age < 1.1) {
        const r = 0.5 + w.age * 1.9;
        w.mesh.scale.setScalar(r);
        w.mesh.material.opacity = Math.max(0, 0.75 * w.strength * (1 - w.age / 1.1));
      } else if (w.mesh.visible) w.mesh.visible = false;
    }

    this.podiumRise.step(dt);
    this.podium.scale.y = Math.max(0.001, this.podiumRise.value);
    if (this.podiumRise.target === 0 && this.podiumRise.value < 0.01) this.podium.visible = false;

    this.stepDust(dt);
    this.stepConfetti(dt);
    this.renderer.render(this.scene, this.camera);
  }

  stepDust(dt) {
    const pos = this.dustPoints.geometry.attributes.position.array;
    const col = this.dustPoints.geometry.attributes.color.array;
    this.dust.forEach((p, i) => {
      p.age += dt;
      if (p.age > p.life) this.respawnMote(p);
      p.p.addScaledVector(p.v, dt);
      p.p.x += Math.sin(this.time * 0.7 + i) * 0.002;
      const f = Math.min(1, p.age / 1.2, (p.life - p.age) / 1.2);
      pos[i * 3] = p.p.x; pos[i * 3 + 1] = p.p.y; pos[i * 3 + 2] = p.p.z;
      col[i * 3] = p.c.r * f; col[i * 3 + 1] = p.c.g * f; col[i * 3 + 2] = p.c.b * f;
    });
    this.dustPoints.geometry.attributes.position.needsUpdate = true;
    this.dustPoints.geometry.attributes.color.needsUpdate = true;
  }

  stepConfetti(dt) {
    if (!this.confetti.length) return;
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3();
    let alive = 0;
    this.confetti.forEach((c, i) => {
      if (c.delay > 0) { c.delay -= dt; s.setScalar(0); m.compose(c.p, q.identity(), s); this.confettiMesh.setMatrixAt(i, m); alive++; return; }
      c.age += dt;
      if (c.age > c.life) { s.setScalar(0); m.compose(c.p, q.identity(), s); this.confettiMesh.setMatrixAt(i, m); return; }
      alive++;
      c.v.y -= 1.6 * dt;
      c.v.multiplyScalar(Math.max(0, 1 - 1.2 * dt));
      c.p.addScaledVector(c.v, dt);
      c.p.x += Math.sin(c.age * 3 + c.phase) * 0.4 * 0.01;
      c.p.z += Math.cos(c.age * 2.4 + c.phase) * 0.4 * 0.008;
      c.angle += c.spin * dt;
      q.setFromAxisAngle(c.axis, c.angle);
      const fade = Math.min(1, (c.life - c.age) / 0.5);
      s.setScalar(c.size * fade);
      m.compose(c.p, q, s);
      this.confettiMesh.setMatrixAt(i, m);
    });
    this.confettiMesh.instanceMatrix.needsUpdate = true;
    if (!alive) { this.confetti = []; this.confettiMesh.count = 0; }
  }
}
