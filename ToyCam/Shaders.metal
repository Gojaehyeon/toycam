#include <metal_stdlib>
using namespace metal;

// Memory layout MUST match `Uniforms` in PixelParams.swift (all float, sequential).
struct Uniforms {
    float pixelSize;
    float colorLevels;
    float ditherStrength;
    float saturation;
    float contrast;
    float vignette;
    float grayscale;
    float resX;
    float resY;
    float texAspect;
    float viewAspect;
};

struct VOut {
    float4 pos [[position]];
    float2 uv;
};

// 8x8 Bayer ordered-dither matrix (0..63).
constant float bayer8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21
};

vertex VOut vtx(uint vid [[vertex_id]]) {
    // Fullscreen triangle.
    float2 p[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VOut o;
    o.pos = float4(p[vid], 0.0, 1.0);
    float2 uv = p[vid] * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;            // NDC(y-up) -> texture(y-down)
    o.uv = uv;
    return o;
}

static inline float3 adjustSaturation(float3 c, float s) {
    float l = dot(c, float3(0.299, 0.587, 0.114));
    return mix(float3(l), c, s);
}

fragment float4 frag(VOut in [[stage_in]],
                     texture2d<float> tex [[texture(0)]],
                     sampler smp [[sampler(0)]],
                     constant Uniforms& u [[buffer(0)]]) {
    // --- aspect-fill 매핑 (화면을 꽉 채우고 넘치는 쪽은 크롭) ---
    float2 uv = in.uv;
    float va = u.viewAspect;
    float ta = u.texAspect;
    float2 scale = float2(1.0);
    if (va > ta) {
        scale.y = ta / va;
    } else {
        scale.x = va / ta;
    }
    uv = (uv - 0.5) * scale + 0.5;

    // --- 픽셀화 ---
    float2 res = float2(max(u.resX, 1.0), max(u.resY, 1.0));
    float gridPx = max(u.pixelSize, 1.0);
    float2 cell = gridPx / res;                       // uv 단위 셀 크기
    int2 pcoord = int2(floor(uv / cell));
    float2 puv = (float2(pcoord) + 0.5) * cell;

    float3 col = tex.sample(smp, clamp(puv, 0.0, 1.0)).rgb;

    // --- 토이카메라 톤: 대비 + 채도 ---
    col = (col - 0.5) * u.contrast + 0.5;
    col = adjustSaturation(col, u.saturation);
    if (u.grayscale > 0.5) {
        col = float3(dot(col, float3(0.299, 0.587, 0.114)));
    }
    col = clamp(col, 0.0, 1.0);

    // --- 디더링 후 색상 양자화 (팔레트 느낌) ---
    int bi = (pcoord.y & 7) * 8 + (pcoord.x & 7);
    float threshold = (bayer8[bi] + 0.5) / 64.0 - 0.5; // -0.5..0.5
    float levels = max(u.colorLevels, 2.0);
    col += threshold * (u.ditherStrength / (levels - 1.0));
    col = floor(col * (levels - 1.0) + 0.5) / (levels - 1.0);
    col = clamp(col, 0.0, 1.0);

    // --- 비네팅 ---
    float2 d = in.uv - 0.5;
    float vig = 1.0 - u.vignette * dot(d, d) * 2.2;
    col *= clamp(vig, 0.0, 1.0);

    return float4(col, 1.0);
}
