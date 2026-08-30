/// Dry Ink / Rough Marker (Realistic Physics & Domain Warping).
///
/// Bristles live in the local Frenet frame of the stroke: U along the closest
/// path tangent, V along the normal. Paper tooth stays page-anchored.
///
/// Spine: uSpineCount + uS0..uS15 (32 x,y) + uPr0..uPr7 (32 pressures).
/// Optional uCastShadow after pressures. Samplers: 0 = paper, 1 = bristles.

#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec3 uColor;
uniform float uFreq;
uniform float uOpacityMax;
uniform float uSeed;
uniform float uContrast;
uniform float uFineMix;
uniform float uThreshold;
uniform float uOffsetX;
uniform float uOffsetY;
uniform float uQuality;
uniform float uDirX;
uniform float uDirY;
uniform float uSpineCount;
uniform vec4 uS0;
uniform vec4 uS1;
uniform vec4 uS2;
uniform vec4 uS3;
uniform vec4 uS4;
uniform vec4 uS5;
uniform vec4 uS6;
uniform vec4 uS7;
uniform vec4 uS8;
uniform vec4 uS9;
uniform vec4 uS10;
uniform vec4 uS11;
uniform vec4 uS12;
uniform vec4 uS13;
uniform vec4 uS14;
uniform vec4 uS15;
uniform float uPressureToCoverage;
uniform float uPressureSens;
uniform vec4 uPr0;
uniform vec4 uPr1;
uniform vec4 uPr2;
uniform vec4 uPr3;
uniform vec4 uPr4;
uniform vec4 uPr5;
uniform vec4 uPr6;
uniform vec4 uPr7;
uniform float uCastShadow;
uniform sampler2D uPaper;
uniform sampler2D uBristles;

out vec4 fragColor;

const float kAtlasSize = 256.0;
const int kMaxSpine = 32;

float hash21(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// SkSL forbids sampler2D function parameters. Sample each atlas directly.
float samplePaper(vec2 p) {
    return texture(uPaper, fract(p / kAtlasSize)).r;
}

float sampleBristles(vec2 p) {
    return texture(uBristles, fract(p / kAtlasSize)).r;
}

vec2 spineAt(int i) {
    int b = i / 2;
    vec4 v = uS0;
    if (b == 1) v = uS1;
    else if (b == 2) v = uS2;
    else if (b == 3) v = uS3;
    else if (b == 4) v = uS4;
    else if (b == 5) v = uS5;
    else if (b == 6) v = uS6;
    else if (b == 7) v = uS7;
    else if (b == 8) v = uS8;
    else if (b == 9) v = uS9;
    else if (b == 10) v = uS10;
    else if (b == 11) v = uS11;
    else if (b == 12) v = uS12;
    else if (b == 13) v = uS13;
    else if (b == 14) v = uS14;
    else if (b == 15) v = uS15;
    if ((i - b * 2) == 0) {
        return v.xy;
    }
    return v.zw;
}

float pressureAt(int i) {
    int b = i / 4;
    vec4 v = uPr0;
    if (b == 1) v = uPr1;
    else if (b == 2) v = uPr2;
    else if (b == 3) v = uPr3;
    else if (b == 4) v = uPr4;
    else if (b == 5) v = uPr5;
    else if (b == 6) v = uPr6;
    else if (b == 7) v = uPr7;
    int r = i - b * 4;
    if (r == 0) return v.x;
    if (r == 1) return v.y;
    if (r == 2) return v.z;
    return v.w;
}

void main() {
    vec2 worldP = FlutterFragCoord().xy + vec2(uOffsetX, uOffsetY);

    float freq = max(uFreq, 0.02);
    float fineMix = clamp(uFineMix, 0.0, 1.0);
    float contrast = max(uContrast, 0.35);
    float threshold = clamp(uThreshold, 0.05, 0.92);
    float opacityMax = clamp(uOpacityMax, 0.2, 1.0);
    float quality = clamp(uQuality, 0.0, 1.0);

    vec2 dir = vec2(uDirX, uDirY);
    if (length(dir) < 0.001) {
        dir = vec2(1.0, 0.0);
    } else {
        dir = normalize(dir);
    }

    float along = dot(worldP, dir);
    float across = dot(worldP, vec2(-dir.y, dir.x));

    int n = int(uSpineCount + 0.5);
    if (n > kMaxSpine) n = kMaxSpine;
    if (n >= 2) {
        float bestD = 1.0e20;
        float arc = 0.0;
        vec2 bestDir = dir;
        float bestAlong = along;
        float bestAcross = across;
        float bestPr = 0.5;
        for (int i = 0; i < kMaxSpine - 1; i++) {
            if (i < n - 1) {
                vec2 a = spineAt(i);
                vec2 b = spineAt(i + 1);
                vec2 ab = b - a;
                float abLen2 = dot(ab, ab);
                float abLen = sqrt(max(abLen2, 0.0));
                float t = 0.0;
                if (abLen2 > 1.0e-8) {
                    t = clamp(dot(worldP - a, ab) / abLen2, 0.0, 1.0);
                }
                vec2 q = a + t * ab;
                vec2 rel = worldP - q;
                float d = dot(rel, rel);
                if (d < bestD) {
                    bestD = d;
                    if (abLen > 1.0e-4) {
                        bestDir = ab / abLen;
                    }
                    bestAlong = arc + t * abLen;
                    bestAcross = rel.x * (-bestDir.y) + rel.y * bestDir.x;
                    bestPr = mix(pressureAt(i), pressureAt(i + 1), t);
                }
                arc += abLen;
            }
        }
        along = bestAlong;
        across = bestAcross;
        dir = bestDir;
        if (uPressureToCoverage > 0.5) {
            float shift = (clamp(bestPr, 0.0, 1.0) - 0.5) * clamp(uPressureSens, 0.0, 2.0);
            threshold = clamp(uThreshold - shift * 0.55, 0.05, 0.92);
            opacityMax = clamp(1.0 - threshold * 0.35, 0.2, 1.0);
        }
    }

    vec2 p = (worldP + uSeed * 100.0) * freq;
    vec2 pBristles = vec2(along, across) * freq;
    pBristles.x += uSeed * 17.0;

    // REALISM 1: Domain Warping. Breaks perfectly straight digital bristles.
    vec2 warp = vec2(
        samplePaper(pBristles * 0.08) - 0.5,
        samplePaper(pBristles * 0.08 + vec2(13.1, 7.3)) - 0.5
    );
    vec2 pWarpedBristles = pBristles + warp * 2.8;

    float thickBristles = sampleBristles(pWarpedBristles * vec2(0.02, 2.5));
    float paper = samplePaper(p * vec2(0.8, 0.8));

    // REALISM 2: Height-based Ink Transfer. 
    // Pigment catches on peaks and skips valleys, rather than flat alpha blending.
    float inkTransfer = (thickBristles * 1.35) - ((1.0 - paper) * 0.5);
    float grain = clamp(inkTransfer, 0.0, 1.0);

    if (quality > 0.5) {
        float fineBristles = sampleBristles(pWarpedBristles * vec2(0.005, 6.0));
        grain = mix(grain, fineBristles, 0.35);

        // Pigment clumping (grit) specifically catches the paper's peaks
        float grit = hash21(floor(p * vec2(1.8, 4.5)));
        float speckles = smoothstep(0.65 - (paper * 0.25), 1.0, grit);
        grain = mix(grain, max(grain, speckles), 0.15 + fineMix * 0.55);

        // REALISM 3: Liquid Pooling. Surging/starving of ink along the stroke path.
        float pool = samplePaper(pWarpedBristles * vec2(0.04, 0.1));
        float tone = 0.7 + 0.3 * smoothstep(0.2, 0.8, pool);
        grain *= tone;
    } else {
        float grit = hash21(floor(p * vec2(1.2, 3.2)));
        float speckles = smoothstep(0.65, 1.0, grit);
        grain = mix(grain, max(grain, speckles), 0.15 + fineMix * 0.45);
    }

    float gateLow = threshold - 0.18;
    float gateHigh = threshold + 0.18;
    float mask = smoothstep(gateLow, gateHigh, grain);

    // REALISM 4: Capillary Action. Dries slightly darker/harsher at the outer boundary.
    float edge = smoothstep(0.0, 0.3, mask) * (1.0 - smoothstep(0.7, 1.0, mask));
    mask = clamp(mask + edge * 0.15, 0.0, 1.0);

    mask = pow(max(mask, 0.0), contrast);
    mask *= smoothstep(0.01, 0.08, mask);

    float opacity = mask * opacityMax;

    // REALISM 5: Textured Impasto Shadows.
    if (uCastShadow > 0.5) {
        vec2 nrm = vec2(-dir.y, dir.x);
        float leeward = dot(nrm, vec2(0.55, 0.82));
        float side = across * sign(leeward + 1.0e-4);

        // Break up the digital line by perturbing the shadow with the paper normal
        side += (paper - 0.5) * 5.0;

        float form = smoothstep(-2.8, 3.8, side);
        opacity *= 1.0 - form * 0.28;

        // Subtle specular wet-ink highlight facing the light source
        float highlight = smoothstep(-4.5, -1.0, side) * smoothstep(1.5, -1.0, side);
        opacity = clamp(opacity + highlight * 0.12 * mask, 0.0, 1.0);
    }

    fragColor = vec4(uColor * opacity, opacity);
}