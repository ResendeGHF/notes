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
uniform float uCastShadow;
uniform sampler2D uPaper;
uniform sampler2D uBristles;

out vec4 fragColor;

// Função de hash para gerar as posições orgânicas dos pequenos grãos de grafite
vec2 hash22(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Cellular noise (Voronoi) produz bolinhas perfeitamente circulares
// eliminando os "quadrados" causados pelo floor() do shader anterior.
float cellular(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float minDist = 1.0;
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 pt = hash22(i + neighbor);
            vec2 diff = neighbor + pt - f;
            float dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    return minDist;
}

void main() {
    vec2 worldP = FlutterFragCoord().xy + vec2(uOffsetX, uOffsetY);

    float freq = max(uFreq, 0.02);
    float fineMix = clamp(uFineMix, 0.0, 1.0);
    float contrast = max(uContrast, 0.35);
    float threshold = clamp(uThreshold, 0.05, 0.92);
    float opacityMax = clamp(uOpacityMax, 0.2, 1.0);
    float quality = clamp(uQuality, 0.0, 1.0);

    vec2 p = (worldP + uSeed * 100.0) * freq;
    vec2 pBristles = p + vec2(uSeed * 17.0, uSeed * 3.1);

    // 1. TEXTURA DO PAPEL (Amostragem dupla para quebrar o padrão)
    float paper1 = texture(uPaper, fract(p * 0.4)).r;
    float paper2 = texture(uPaper, fract(p * 1.15 + vec2(0.2, 0.3))).r;
    float paperTooth = mix(paper1, paper2, 0.5);

    // 2. CERDAS DO LÁPIS (Traços direcionais)
    float bristle1 = texture(uBristles, fract(pBristles * 0.5)).r;
    float bristle2 = texture(uBristles, fract(pBristles * 1.3 + vec2(0.5, 0.1))).r;
    float bristles = mix(bristle1, bristle2, 0.5);

    // 3. MICRO GRÃOS DE GRAFITE (Esferas perfeitas)
    // Usamos cellular noise invertido para criar as pequenas bolinhas (pó de grafite).
    float microDots = 1.0 - cellular(p * 8.0);
    float microDotsFine = 1.0 - cellular(p * 16.0);
    float dots = mix(microDots, microDotsFine, 0.5);

    // 4. MISTURA E DENSIDADE DO PIGMENTO
    // O pigmento do lápis se deposita primariamente nos picos/relevo do papel
    float basePigment = mix(paperTooth, bristles, fineMix * 0.8);
    
    // Adicionamos as bolinhas de grafite como "sujeira/grão de poeira"
    float pigment = mix(basePigment, dots, 0.35 + fineMix * 0.15);

    // 5. THRESHOLD COM ALTO CONTRASTE (Simula a quebra/pressão contra o papel)
    float gateLow = threshold - (0.25 / contrast);
    float gateHigh = threshold + (0.25 / contrast);
    float mask = smoothstep(gateLow, gateHigh, pigment);

    // 6. REALISMO 3D: SOMBRA E BRILHO METÁLICO DO GRAFITE
    if (uCastShadow > 0.5) {
        float h0 = paperTooth;
        float h1 = texture(uPaper, fract(p * 0.4 - vec2(0.005, 0.005))).r;
        float lightAngle = h0 - h1;
        
        float shadow = smoothstep(0.0, 0.05, lightAngle);
        float shine = smoothstep(-0.04, -0.01, lightAngle);
        
        // Sombras escuras concentradas nos vales do papel
        mask = mask * mix(1.0, 0.4, shadow);
        // Reflexo metálico suave da grafite nas pontas que encaram a luz
        mask = mask + (shine * mask * 0.3);
    }

    // Suaviza levemente as bordas do traço para mesclar com o background e evitar serrilhados
    mask = pow(clamp(mask, 0.0, 1.0), 1.2);
    
    float opacity = mask * opacityMax;

    fragColor = vec4(uColor * opacity, opacity);
}