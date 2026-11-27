#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniform order is the setFloat() order used by VisualizerScreen:
//  0,1 resolution | 2 time | 3 bass | 4 mid | 5 treble | 6-8 primary | 9-11 secondary | 12-14 accent
uniform vec2 uResolution;
uniform float uTime;
uniform float uBass;
uniform float uMid;
uniform float uTreble;
uniform vec3 uPrimaryColor;
uniform vec3 uSecondaryColor;
uniform vec3 uAccentColor;

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
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Five octaves of fractional Brownian motion; each octave is rotated to hide the value-noise grid.
float fbm(vec2 p) {
  const mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * vnoise(p);
    p = rot * p * 2.03 + 11.7;
    a *= 0.5;
  }
  return v;
}

// Narkowicz ACES filmic curve.
vec3 aces(vec3 x) {
  const float a = 2.51;
  const float b = 0.03;
  const float c = 2.43;
  const float d = 0.59;
  const float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uResolution;
  float scale = min(uResolution.x, uResolution.y);
  vec2 p = (frag - 0.5 * uResolution) / scale * 2.0;

  float t = uTime * 0.07;
  float d = length(p);

  // Bass pushes the field outward from the centre; a gentle zoom pulse reads as a kick drum.
  vec2 q0 = p * (1.0 - 0.05 * uBass);

  // Domain warping: fbm of fbm, with the mids speeding up the flow (colour advection).
  float flow = t * (1.0 + 1.8 * uMid);
  vec2 q = vec2(fbm(q0 * 1.5 + vec2(0.0, flow)), fbm(q0 * 1.5 + vec2(5.2, 1.3) - flow));
  vec2 r = vec2(
    fbm(q0 * 1.9 + 3.2 * q + vec2(1.7, 9.2) + flow * 1.3),
    fbm(q0 * 1.9 + 3.2 * q + vec2(8.3, 2.8) - flow * 1.1)
  );
  float f = fbm(q0 * 1.3 + 2.4 * r + uMid * 0.7);

  // Colour: primary into secondary through the field, accent where the warp folds.
  vec3 col = mix(uPrimaryColor, uSecondaryColor, smoothstep(0.15, 0.85, f));
  float fold = smoothstep(0.35, 1.05, length(q)) * 0.6 + uMid * 0.2 * r.x;
  col = mix(col, uAccentColor, clamp(fold, 0.0, 1.0));
  col *= 0.35 + 1.15 * f;

  // Radial beat shockwaves: rings travel outward and are strongest on loud bass.
  float ring = sin(d * 11.0 - uTime * 2.6 - uBass * 5.0);
  float shock = ring * exp(-d * 1.9) * uBass * 0.5;
  col += uAccentColor * max(shock, 0.0) * 0.9;
  col += uPrimaryColor * uBass * 0.16 * exp(-d * 1.6);

  // Treble: fine shimmer and filmic grain.
  float sparkle = pow(vnoise(p * 55.0 + vec2(uTime * 2.3, -uTime * 1.7)), 9.0) * uTreble * 2.2;
  col += uAccentColor * sparkle;
  float grain = hash21(frag + fract(uTime) * 91.7) - 0.5;
  col += grain * (0.025 + 0.05 * uTreble);

  // Keep the field dark enough for white lyrics: global gain, then a vignette.
  col *= 0.6;
  float vig = 1.0 - smoothstep(0.2, 1.35, length(uv - 0.5) * 1.6);
  col *= mix(0.3, 1.0, vig);

  col = aces(col * 1.15);
  fragColor = vec4(col, 1.0);
}
