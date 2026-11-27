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

// Flying through a ribbed tunnel; the bass throws you forward, mids twist the walls.
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uResolution;
  vec2 p = (frag - 0.5 * uResolution) / min(uResolution.x, uResolution.y) * 2.0;
  float t = uTime * uSpeed;
  float r = length(p) + 1e-4;
  float a = atan(p.y, p.x);
  float z = 0.35 / r;
  float travel = t * (0.8 + 1.4 * uBass * uIntensity);
  float twist = a + z * 0.35 * sin(t * 0.3) + uMid * 1.2 * sin(z + t);
  float rings = abs(sin((z - travel) * 5.0));
  float ribs = abs(sin(twist * 6.0 + z * 0.6));
  float sx = fract(a / 6.2831853 + 0.5);
  float level = spec(abs(sx - 0.5) * 2.0) * uIntensity;
  float wall = smoothstep(0.55, 1.0, rings) * 0.8 + smoothstep(0.82, 1.0, ribs) * 0.6;
  vec3 col = ramp(fract(z * 0.12 - t * 0.04) * 0.9);
  col *= (0.12 + wall * (0.8 + level * 2.0));
  col += uAccentColor * exp(-r * 4.5) * (0.5 + 1.4 * uBass * uIntensity);
  col *= smoothstep(0.0, 0.5, r);
  col += uAccentColor * pow(vnoise(p * 40.0 + t * 3.0), 10.0) * uTreble * 2.0;
  fragColor = finish(col, uv);
}
