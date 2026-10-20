#version 460 core
#include <flutter/runtime_effect.glsl>

// Graphite pencil grain. One pass shades a whole union path (fill), so no
// geometry overlap can ever double-darken; this shader only decides how much
// graphite one pixel of that fill receives.
//
// Coordinate contract: FlutterFragCoord() is the fragment position in the
// LOCAL space of the drawing command. Every path that paints pencil ink
// records page coordinates - direct canvas draws, recorded tile pictures
// replayed under any pan/zoom transform, page-raster bakes at any resolution -
// so this local space IS page space. The grain is anchored to the page and
// cannot shift, swim or change scale when the canvas pans, zooms, or bakes at
// a different resolution: live and committed ink evaluate the identical field.
//
// Noise comes from two 256x256 atlases (see PencilGrainAtlas) that pack six
// seamless fields into RGB channels: one fetch serves a whole octave stack.
// The default grain scale maps the atlas 1:1 (1 texel = 1 page pixel) and is
// never sampled *finer*: sub-page-pixel grain would shimmer whenever the
// canvas shifts by a fraction of a pixel or a cache resamples the picture.
// Tip size therefore shapes the deposit *structure* (uTipMix fades the coarse
// bands for thin tips) instead of the sampling frequency, so a 10 px stroke
// reads as fine speckle rather than a few oversized blotches.

uniform vec3 uColor;
uniform float uFreq; // noise tiles per page pixel (1 / tile size in page px)
uniform float uOpacityMax; // darkest deposit alpha
uniform float uSeed; // per-stroke decorrelation of the noise
uniform float uContrast; // higher = harder grain edges, less soft gradient
uniform float uFineMix; // higher = more salt-and-pepper grit
uniform float uThreshold; // higher = sparser graphite, more paper showing
uniform float uQuality; // 0 = zoomed out LOD (2 fetches), 1 = full grain
uniform float uCastShadow;
uniform float uTipMix; // 0 = fine tip, 1 = broad tip (deposit feature scale)
uniform sampler2D uPaper; // R coarse lumps / G medium tooth / B fine grit
uniform sampler2D uBristles; // R,G fibre streaks / B streak grit

out vec4 fragColor;

void main() {
    // Page-anchored field: local coords are page coords in every draw path.
    vec2 page = FlutterFragCoord().xy;
    vec2 uv = page * max(uFreq, 1e-5);
    // Page-anchored per-stroke offset (deterministic: same seed, same grain).
    vec2 jitter =
        vec2(fract(uSeed * 0.6180339887), fract(uSeed * 0.3819660113)) * 0.37;

    // 1:1 fetch: the crisp grain. Coarse lumps / medium tooth / fine grit.
    vec4 p1 = texture(uPaper, fract(uv + jitter));
    // 1:1 fetch: fibre streaks the tip drags pigment along + streak grit.
    vec4 b1 = texture(uBristles, fract(uv + jitter.yx));

    float tooth = p1.r * 0.16 + p1.g * 0.42 + p1.b * 0.42;
    float fibre = mix(b1.r, b1.g, 0.5);
    float grit = b1.b;
    float lumps;
    if (uQuality < 0.5) {
        // Zoomed-out LOD: pressure drift comes from the coarse band of the
        // same fetch instead of a second one; grain averages out anyway.
        lumps = p1.r;
    } else {
        // 4x magnified fetch: slow pressure drift along the stroke. Magnified
        // sampling never aliases (see header).
        vec4 p2 = texture(uPaper, fract(uv * 0.25 + jitter.yx + 0.317));
        lumps = mix(p2.r, p2.g, 0.40);
    }

    // Tip size scales the deposit structure. A broad tip (size ~100) keeps the
    // full lump/tooth/fibre drift: a wide contact patch deposits wide tonal
    // patches. A fine tip fades the coarse bands so a 10 px stroke shows fine
    // speckle instead of a few huge blotches; the fine bands are boosted
    // slightly so thin strokes still read as graphite, not as flat marker ink.
    float coarse = mix(0.30, 1.0, uTipMix);
    float medium = mix(0.62, 1.0, uTipMix);
    float slow = (p1.r - 0.5) * 0.30 * coarse +
        (p1.g - 0.5) * 0.32 * medium +
        (fibre - 0.5) * 0.30 * medium +
        (lumps - 0.5) * 0.22 * coarse;
    float fast = (p1.b - 0.5) * 0.95 * mix(1.10, 0.95, uTipMix) +
        (grit - 0.5) * uFineMix * 0.40;
    float deposit = mix(0.645, 0.62, uTipMix) + slow + fast;

    // Gaps: smoothstep threshold turns deposit into coverage. uContrast
    // narrows the transition (harder grain, more paper sparkle). Fine tips
    // keep a harder, slightly higher edge: thin strokes want crisp pinhole
    // gaps, not the washed-out 10 px stretches a soft edge opens once the
    // coarse bands are quiet.
    float edge = clamp(uThreshold + 0.045 * (1.0 - uTipMix), 0.02, 0.95);
    float soft = mix(0.20, 0.30, uTipMix) / max(uContrast, 0.25);
    float grain = smoothstep(edge, edge + soft, deposit);
    // A whisper of graphite haze in the gaps: pure white holes read as
    // halftone screens instead of paper.
    grain = mix(0.05, grain, 0.95);

    // Per-pixel pigment density jitter at the finest scale: this is what reads
    // as a grainy stroke at 1:1. Fades out with the LOD factor so minified
    // views do not shimmer.
    float lod = smoothstep(0.45, 0.95, uQuality);
    float sparkle = p1.b;
    float density = mix(1.0, 0.70 + 0.62 * sparkle, lod);

    float alpha = grain * clamp(uOpacityMax, 0.0, 1.0) * density;

    if (uCastShadow > 0.5) {
        // Cheap contact shading: reuse the grain relief as a normal so the
        // grain itself catches the light. Off for normal drawing.
        float relief = smoothstep(0.04, 0.42, tooth - lumps);
        alpha *= mix(1.04, 0.74, relief);
    }

    fragColor = vec4(uColor * alpha, alpha);
}
