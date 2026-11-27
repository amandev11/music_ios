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

// Layered northern-light ribbons; every ribbon follows a slice of the spectrum.
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uResolution;
  float t = uTime * uSpeed * 0.35;
  vec3 col = mix(vec3(0.004, 0.006, 0.02), uSecondaryColor * 0.12, uv.y);
  // Stars.
  col += vec3(pow(hash21(floor(frag / 3.0)), 40.0)) * (0.4 + uTreble);
  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    float e = spec(fi / 4.0) * uIntensity;
    float y0 = 0.62 - fi * 0.09;
    float wave = sin(uv.x * (3.0 + fi) + t * (1.0 + fi * 0.3) + fi * 1.7) * 0.07
               + sin(uv.x * 7.0 - t * 1.3 + fi) * 0.025 * (0.5 + uMid)
               + (vnoise(vec2(uv.x * 4.0 + fi * 9.0, t)) - 0.5) * 0.08;
    float d = uv.y - (y0 + wave);
    float height = 0.1 + 0.22 * e + 0.05 * uBass;
    float curtain = smoothstep(0.0, 0.01, d) * exp(-max(d, 0.0) / height * 2.2) * smoothstep(-0.06, 0.0, d + 0.02);
    float rays = 0.65 + 0.35 * sin(uv.x * 140.0 + fi * 3.0 + t * 4.0);
    col += ramp(0.25 + fi * 0.18) * curtain * rays * (0.35 + 0.9 * e);
  }
  col += uAccentColor * uBeat * 0.06;
  fragColor = finish(col, uv);
}
