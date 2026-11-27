#version 460 core
#include <flutter/runtime_effect.glsl>

// setFloat order: 0,1 resolution | 2 time | 3 bass | 4 mid | 5 treble | 6-8 primary | 9-11 secondary
// | 12-14 accent | 15 intensity | 16 speed | 17 beat | 18-33 sixteen spectrum bands (low to high).
uniform vec2 uResolution;
uniform float uTime;
uniform float uBass;
uniform float uMid;
uniform float uTreble;
uniform vec3 uPrimaryColor;
uniform vec3 uSecondaryColor;
uniform vec3 uAccentColor;
uniform float uIntensity;
uniform float uSpeed;
uniform float uBeat;
uniform vec4 uBandsA;
uniform vec4 uBandsB;
uniform vec4 uBandsC;
uniform vec4 uBandsD;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float bandAt(int i) {
  int k = i / 4;
  int j = i - k * 4;
  vec4 v = k == 0 ? uBandsA : (k == 1 ? uBandsB : (k == 2 ? uBandsC : uBandsD));
  return j == 0 ? v.x : (j == 1 ? v.y : (j == 2 ? v.z : v.w));
}

// Smoothly interpolated spectrum at x in 0..1 (0 = lowest band).
float spec(float x) {
  float f = clamp(x, 0.0, 1.0) * 15.0;
  int i = int(floor(f));
  return mix(bandAt(i), bandAt(min(i + 1, 15)), smoothstep(0.0, 1.0, fract(f)));
}

vec3 aces(vec3 x) {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

vec3 ramp(float t) {
  t = clamp(t, 0.0, 1.0);
  return t < 0.5 ? mix(uSecondaryColor, uPrimaryColor, t * 2.0)
                 : mix(uPrimaryColor, uAccentColor, (t - 0.5) * 2.0);
}

vec4 finish(vec3 col, vec2 uv) {
  float vig = 1.0 - smoothstep(0.25, 1.4, length(uv - 0.5) * 1.5);
  col *= mix(0.4, 1.0, vig);
  // Touch every uniform so the compiler keeps them all in order (setFloat indexes depend on it).
  float keep = uTime * 1e-7 + uBass + uMid + uTreble + uIntensity + uSpeed + uBeat + dot(uBandsA + uBandsB + uBandsC + uBandsD, vec4(1.0));
  col += (uPrimaryColor + uSecondaryColor + uAccentColor) * keep * 1e-6;
  return vec4(aces(col * 1.1), 1.0);
}

// A wall of glowing voxels: one column per spectrum band, bevelled cubes, a bright cap on each peak.
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uResolution;
  float t = uTime * uSpeed;
  float cols = 28.0;
  float cell = uResolution.x / cols;
  float rows = floor(uResolution.y / cell);
  vec2 g = vec2(frag.x / cell, (uResolution.y - frag.y) / cell);
  vec2 id = floor(g);
  vec2 f = fract(g);
  float cx = (id.x + 0.5) / cols;
  // Mirrored: the bass sits in the middle, the highs at both edges.
  float sx = abs(cx - 0.5) * 2.0;
  float level = spec(sx) * uIntensity;
  level = clamp(level * (0.8 + 0.5 * uBass) + 0.06 + 0.04 * sin(t * 1.3 + id.x * 0.7), 0.0, 1.0);
  float h = level * rows;
  float lit = step(id.y, h - 1.0);
  float cap = step(abs(id.y - floor(h)), 0.5) * step(0.5, h);

  // Bevelled cube: bright top edge, dark bottom edge, soft inner glow.
  vec2 d = abs(f - 0.5);
  float box = 1.0 - smoothstep(0.34, 0.44, max(d.x, d.y));
  float bevel = 0.75 + 0.45 * smoothstep(0.0, 0.5, f.y) - 0.35 * (1.0 - smoothstep(0.0, 0.5, f.y));
  float rel = id.y / max(rows, 1.0);
  vec3 base = ramp(rel * 0.9 + level * 0.3);
  vec3 col = vec3(0.012, 0.014, 0.02);
  // Unlit grid cells.
  col += vec3(0.05) * box * (0.6 + 0.4 * hash21(id));
  col += base * 0.08 * box;
  col = mix(col, base * bevel * (0.85 + 0.6 * uBeat), lit * box);
  col += uAccentColor * cap * box * (0.9 + 0.8 * uBeat);
  // Light spill from the lit cubes onto the wall.
  col += base * 0.05 * lit;
  // Treble sparkle in dark cells.
  float tw = pow(hash21(id + floor(t * 6.0)), 14.0) * uTreble * 4.0;
  col += uAccentColor * tw * box * (1.0 - lit);
  fragColor = finish(col, uv);
}
