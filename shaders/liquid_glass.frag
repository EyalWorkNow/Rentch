#version 460 core
#include <flutter/runtime_effect.glsl>

// אתי's liquid-glass orb — 175×175. Glass body #23404A @ 20%, NO stroke, only
// directional light. Beneath it, 4 coloured balls (Ø50–85px) are HEAVILY blurred
// (frosted-glass look), drift SLOWLY, and grow/shrink while they move. Max glass
// physics: refraction (dome lens), dispersion (prism RGB split), frost, depth.
// Hard-clipped to the disc (r>1 → transparent) with a big safety margin, so the
// balls stay very well contained and never reach the glass edge.

uniform vec2 uSize;   // 175, 175 (logical)
uniform float uTime;
uniform float uLevel;    // 0..1 speaking intensity
uniform float uSpeaking; // 0 idle → 1 speaking: shifts to a livelier palette

out vec4 fragColor;

const vec3 GLASS = vec3(0.137, 0.251, 0.290); // #23404A

// Idle palette — cool teal / indigo / rose / amber.
const vec3 C0 = vec3(0.09, 0.78, 0.82); // teal
const vec3 C1 = vec3(0.40, 0.46, 1.00); // indigo
const vec3 C2 = vec3(1.00, 0.42, 0.52); // rose
const vec3 C3 = vec3(1.00, 0.80, 0.34); // amber

// Speaking palette — warmer, more electric (violet / magenta / coral / gold), so
// אתי's orb visibly "lights up" and shifts hue the moment she starts talking.
const vec3 S0 = vec3(0.55, 0.30, 1.00); // violet
const vec3 S1 = vec3(0.98, 0.32, 0.80); // magenta
const vec3 S2 = vec3(1.00, 0.46, 0.36); // coral
const vec3 S3 = vec3(1.00, 0.72, 0.20); // gold

vec3 ballColor(int i) {
  vec3 idle = (i == 0) ? C0 : (i == 1) ? C1 : (i == 2) ? C2 : C3;
  vec3 talk = (i == 0) ? S0 : (i == 1) ? S1 : (i == 2) ? S2 : S3;
  return mix(idle, talk, clamp(uSpeaking, 0.0, 1.0));
}

const float RMIN = 0.286; // Ø50px / R(87.5px)
const float RMAX = 0.486; // Ø85px / R

// Heavily-blurred coloured field of the 4 balls at disc-point q. Slow motion,
// slow size breathing. `cov` gets the (soft) coverage for compositing.
vec3 ballsField(vec2 q, float t, float lvl, out float cov) {
  vec3 acc = vec3(0.0);
  float wsum = 0.0;
  cov = 0.0;
  // Splay: cluster spreads outward toward the rim, but stays well inside.
  float clusterR = 0.17 + 0.04 * lvl;
  vec2 drift = 0.045 * vec2(sin(t * 0.11), cos(t * 0.09)); // very slow whole-cluster drift
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    // slow angular sway around the cluster
    float ang = 1.5708 * fi + 0.55 * sin(t * 0.10 + fi * 1.3);
    vec2 wob = 0.045 * vec2(sin(t * 0.14 + fi * 2.0), cos(t * 0.12 + fi));
    vec2 c = drift + clusterR * vec2(cos(ang), sin(ang)) + wob;
    // slow, continuous grow/shrink across the full 50–85px range
    float breathe = 0.5 + 0.5 * sin(t * (0.16 + 0.05 * fi) + fi * 1.7);
    float rad = mix(RMIN, RMAX, breathe) * (0.92 + 0.08 * lvl);
    // high containment: keep the whole (blurred) ball well inside the disc
    float safe = 1.0 - rad - 0.10;
    float cl = length(c);
    if (cl > safe) c *= safe / cl;
    float d = length(q - c);
    // HEAVY blur: wide Gaussian falloff → soft frosted glow, no hard edge
    float sig = rad * 0.9;
    float g = exp(-(d * d) / (2.0 * sig * sig));
    vec3 col = mix(ballColor(i), ballColor(int(mod(fi + 1.0, 4.0))),
                   0.22 * (0.5 + 0.5 * sin(t * 0.13 + fi)));
    acc += col * g;
    wsum += g;
    cov = max(cov, g);
  }
  return wsum > 1e-4 ? acc / wsum : vec3(0.0);
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 center = uSize * 0.5;
  float R = min(uSize.x, uSize.y) * 0.5;
  vec2 p = (fc - center) / R;
  float r = length(p);
  if (r > 1.0) { fragColor = vec4(0.0); return; } // hard clip → nothing escapes

  float z = sqrt(max(0.0, 1.0 - r * r)); // dome height
  vec3 n = vec3(p, z);
  float bend = 1.0 - z;
  vec2 dir = (r > 1e-4) ? p / r : vec2(0.0);

  // Refraction (max): the dome strongly pulls the sampled field inward → a clear
  // glass-lens magnification of the core and compression at the edge.
  vec2 base = p - dir * bend * 0.45;

  // Dispersion (max): sample R/G/B along noticeably different refraction offsets
  // so light splits into prism colours, strongest near the thick rim.
  float disp = 0.085 * bend + 0.02;
  float covR, covG, covB;
  vec3 sR = ballsField(base - dir * disp, uTime, uLevel, covR);
  vec3 sG = ballsField(base, uTime, uLevel, covG);
  vec3 sB = ballsField(base + dir * disp, uTime, uLevel, covB);
  vec3 bc = vec3(sR.r, sG.g, sB.b);
  float cov = max(covG, max(covR, covB));

  // Frost (max): pronounced milky matte glass where the balls are faint.
  bc = mix(bc, bc * 0.78 + vec3(0.18), 0.30);

  // Composite (premultiplied): frosted balls OVER the 20% glass body.
  float glassA = 0.20;
  vec3 bp = bc * cov;
  float ba = cov;
  vec3 gp = GLASS * glassA;
  vec3 outp = bp + gp * (1.0 - ba);
  float outa = ba + glassA * (1.0 - ba);

  // Depth + directional light (no stroke): diffuse shading, inner-edge shadow,
  // and a crisp specular sheen from the light direction.
  vec3 L = normalize(vec3(-0.45, -0.72, 0.85));
  float diff = 0.5 + 0.5 * dot(n, L);
  outp *= mix(0.82, 1.18, diff);
  outp *= mix(1.12, 0.72, smoothstep(0.25, 1.0, r)); // depth: bright core → shadowed rim
  float spec = pow(max(dot(n, L), 0.0), 30.0);
  outp += spec * 0.55 * outa;

  float aa = 1.0 - smoothstep(0.988, 1.0, r);
  fragColor = vec4(outp * aa, outa * aa);
}
