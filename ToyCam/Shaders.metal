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
    float greenScreen;
    float colorMode;
    float zoom;
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

    // --- 디지털 줌 (중앙 확대) ---
    float zoom = max(u.zoom, 1.0);
    uv = (uv - 0.5) / zoom + 0.5;

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

    // --- 필터 컬러 모드 ---
    // 1-5,7-9: 듀오톤 / 6: 반전 / 10: 서멀 / 11: 나이트비전 / 12,16: 고정 팔레트 / 13-15: 필름 틴트
    if (u.colorMode > 0.5) {
        int m = int(round(u.colorMode));
        float t = dot(col, float3(0.299, 0.587, 0.114));
        if (m == 6) {
            col = 1.0 - col;                              // NEGA: 반전
        } else if (m == 10) {
            // THERMAL: 검정→보라→주황→노랑→흰색
            float3 c1 = float3(0.00, 0.00, 0.15), c2 = float3(0.50, 0.00, 0.60);
            float3 c3 = float3(1.00, 0.35, 0.00), c4 = float3(1.00, 0.90, 0.20), c5 = float3(1.0);
            if (t < 0.25)      col = mix(c1, c2, t / 0.25);
            else if (t < 0.5)  col = mix(c2, c3, (t - 0.25) / 0.25);
            else if (t < 0.75) col = mix(c3, c4, (t - 0.5) / 0.25);
            else               col = mix(c4, c5, (t - 0.75) / 0.25);
        } else if (m == 11) {
            // NIGHT: 야시경 (밝은 그린, 감마 부스트)
            col = mix(float3(0.0, 0.02, 0.0), float3(0.25, 1.0, 0.25), pow(t, 0.7));
        } else if (m == 12) {
            // CGA: 4색 팔레트 (검정/시안/마젠타/흰색) 최근접 매핑
            float3 pal[4] = { float3(0.0), float3(0.33, 1.0, 1.0), float3(1.0, 0.33, 1.0), float3(1.0) };
            float best = 1e9; float3 bc = pal[0];
            for (int i = 0; i < 4; i++) {
                float d = distance_squared(col, pal[i]);
                if (d < best) { best = d; bc = pal[i]; }
            }
            col = bc;
        } else if (m == 16) {
            // NES: 패미컴풍 8색 팔레트 최근접 매핑
            float3 pal[8] = {
                float3(0.0), float3(1.0),
                float3(0.78, 0.16, 0.16), float3(0.94, 0.53, 0.12),
                float3(0.99, 0.91, 0.31), float3(0.22, 0.65, 0.26),
                float3(0.23, 0.36, 0.85), float3(0.96, 0.76, 0.62)
            };
            float best = 1e9; float3 bc = pal[0];
            for (int i = 0; i < 8; i++) {
                float d = distance_squared(col, pal[i]);
                if (d < best) { best = d; bc = pal[i]; }
            }
            col = bc;
        } else if (m == 13) {
            // GOLD: 코닥풍 웜 틴트 (그림자 살짝 들어올림)
            col = clamp(col * float3(1.15, 1.00, 0.78) + float3(0.05, 0.02, 0.00), 0.0, 1.0);
        } else if (m == 14) {
            // FUJI/CCD: 쿨 그린-시안 틴트
            col = clamp(col * float3(0.88, 1.05, 1.00) + float3(0.00, 0.02, 0.04), 0.0, 1.0);
        } else if (m == 15) {
            // XPRO: 크로스 프로세스 (채널 커브 왜곡 + 대비)
            col = float3(pow(col.r, 0.85), col.g, pow(col.b, 1.30)) + float3(0.03, 0.0, -0.02);
            col = (col - 0.5) * 1.1 + 0.5;
            col = clamp(col, 0.0, 1.0);
        } else {
            // 듀오톤 계열
            float3 dark = float3(0.0), light = float3(1.0);
            if (m == 1)      { dark = float3(0.055, 0.18, 0.055); light = float3(0.55, 0.74, 0.06); } // GB 그린
            else if (m == 2) { dark = float3(0.16, 0.09, 0.02);   light = float3(0.93, 0.82, 0.62); } // 세피아
            else if (m == 3) { dark = float3(0.08, 0.04, 0.00);   light = float3(1.00, 0.69, 0.10); } // 앰버 CRT
            else if (m == 4) { dark = float3(0.10, 0.00, 0.00);   light = float3(1.00, 0.15, 0.10); } // 버추얼보이 레드
            else if (m == 5) { dark = float3(0.02, 0.07, 0.16);   light = float3(0.62, 0.85, 1.00); } // 아이스 블루
            else if (m == 8) { dark = float3(0.04, 0.10, 0.28);   light = float3(0.80, 0.90, 0.97); } // 시아노타입
            else if (m == 9) { dark = float3(0.35, 0.05, 0.55);   light = float3(0.30, 0.95, 0.95); } // 베이퍼웨이브
            // m == 7: 순수 모노 (dark=검정, light=흰색 기본값)
            col = mix(dark, light, t);
        }
    }

    // --- LCD 모드 오버라이드 (LCD 버튼: 0=컬러, 1=GB그린, 2=흑백) ---
    int lcd = int(round(u.greenScreen));
    if (lcd == 1) {
        float t = dot(col, float3(0.299, 0.587, 0.114));
        float3 darkGreen  = float3(0.055, 0.18, 0.055);  // #0f2e0f 근처
        float3 lightGreen = float3(0.55, 0.74, 0.06);    // #8bbc0f 근처
        col = mix(darkGreen, lightGreen, t);
    } else if (lcd == 2) {
        col = float3(dot(col, float3(0.299, 0.587, 0.114)));
    }

    // --- 비네팅 ---
    float2 d = in.uv - 0.5;
    float vig = 1.0 - u.vignette * dot(d, d) * 2.2;
    col *= clamp(vig, 0.0, 1.0);

    return float4(col, 1.0);
}
