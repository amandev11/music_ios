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

// Outrun horizon: a pulsing sun, mountains drawn by the spectrum, and a grid rushing toward you.
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uResolution;
  float t = uTime * uSpeed;
  float hy = 0.46;
  vec3 col;
  if (uv.y < hy) {
    // Sky.
    float k = uv.y / hy;
    col = mix(uSecondaryColor * 0.08, uPrimaryColor * 0.55, pow(k, 1.6));
    vec2 sp = vec2((uv.x - 0.5) * uResolution.x / uResolution.y, uv.y - hy + 0.2);
    float sun = 1.0 - smoothstep(0.19, 0.2 + 0.03 * uBass * uIntensity, length(sp));
    float cut = step(0.5, fract((uv.y - hy) * 38.0 + t * 0.3)) * smoothstep(0.0, 0.2, hy - uv.y);
    col = mix(col, mix(uAccentColor, uPrimaryColor, k) * (1.0 + 0.5 * uBeat), sun * (1.0 - cut * 0.9));
    // Mountains from the spectrum.
    float m = hy - spec(abs(uv.x - 0.5) * 2.0) * 0.18 * uIntensity - 0.02 - 0.015 * sin(uv.x * 40.0);
    col = mix(col, vec3(0.01, 0.01, 0.025) + uSecondaryColor * 0.05, step(m, uv.y));
    col += uAccentColor * (1.0 - smoothstep(0.0, 0.006, abs(uv.y - m))) * 0.8;
  } else {
    // Ground grid in perspective.
    float yy = uv.y - hy;
    float z = 0.12 / yy;
    float x = (uv.x - 0.5) * z * 2.4;
    float gz = fract(z * 1.2 - t * (0.6 + uBass * uIntensity));
    float line = (1.0 - smoothstep(0.0, 0.06, abs(gz - 0.5) - 0.44)) + (1.0 - smoothstep(0.0, 0.05, abs(fract(x) - 0.5) - 0.45));
    float fade = smoothstep(0.0, 0.25, yy);
    vec3 glow = ramp(0.3 + 0.5 * spec(abs(uv.x - 0.5) * 2.0));
    col = mix(vec3(0.01, 0.01, 0.03), uSecondaryColor * 0.12, fade);
    col += glow * line * fade * (0.8 + 1.4 * uBass * uIntensity);
    col += uAccentColor * exp(-yy * 16.0) * 0.35;
  }
  col += uAccentColor * pow(hash21(frag + fract(uTime)), 30.0) * uTreble;
  fragColor = finish(col, uv);
}
