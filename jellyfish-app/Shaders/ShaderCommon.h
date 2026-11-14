//
//  ShaderCommon.h
//  Shared types and functions for every jellyfish shader.
//
//  The jellyfish is animated entirely on the GPU: meshes only carry
//  parametric coordinates (e.g. bell profile position u and angle θ),
//  and the vertex shaders evaluate the anatomy + swimming motion below.
//  Struct layouts must stay in sync with RenderTypes.swift.
//

#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <metal_stdlib>
using namespace metal;

#define PI  3.14159265359f
#define TAU 6.28318530718f

// MARK: - Uniform layouts (mirrors RenderTypes.swift)

struct FrameUniforms {
    float4x4 viewProj;
    float4x4 view;
    float4x4 invViewProj;
    float4 cameraPos;       // xyz camera position, w time (s)
    float4 viewport;        // x width, y height, z pixel angle (2·tan(fov/2)/height), w focus distance
    float4 keyLightDir;     // xyz toward light (normalized), w intensity
    float4 keyLightColor;
    float4 fillLightDir;    // xyz toward light (normalized), w intensity
    float4 fillLightColor;
    float4 ambientTop;
    float4 ambientBottom;
    float4 anim;            // x pulse period, y contraction, z sway, w lag (s per unit length)
    float4 current;         // xyz water current, w unused
};

struct AnatomyUniforms {
    float4 bell;       // x radius, y height, z profile sweep (rad), w lappet depth
    float4 bell2;      // x lappet count, y apex thickness, z margin thickness, w tentacle root u
    float4 gonad;      // x ring radius (u), y horseshoe radius (u), z tube radius, w frill
    float4 oralArm;    // x length, y width, z twist, w frill amplitude
    float4 tentacle;   // x tip taper, y bead frequency, z bead strength, w unused
    float4 manubrium;  // x length, y radius, z oral arm count, w gonad count
};

struct MaterialUniforms {
    float4 baseColor;    // rgb tissue tint, a base opacity
    float4 rimColor;     // rgb rim glow, a rim opacity
    float4 detailColor;  // rgb detail (canals, beads, frills), a strength
    float4 accentColor;  // rgb secondary tint, a strength
    float4 params;       // x fresnel power, y scatter, z specular, w transmission
};

struct PartVertex {
    float4 p0;
    float4 p1;
};

// MARK: - Fullscreen passes

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

/// One oversized triangle covering the viewport; uv has y pointing down.
inline FullscreenOut fullscreenTriangle(uint vid) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut out;
    out.position = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
    out.uv = float2(p.x, 1.0f - p.y);
    return out;
}

// MARK: - Noise

inline float hash13(float3 p) {
    p = fract(p * 0.1031f);
    p += dot(p, p.zyx + 31.32f);
    return fract((p.x + p.y) * p.z);
}

inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

inline float valueNoise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

inline float valueNoise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0f - 2.0f * f);
    float n000 = hash13(i);
    float n100 = hash13(i + float3(1, 0, 0));
    float n010 = hash13(i + float3(0, 1, 0));
    float n110 = hash13(i + float3(1, 1, 0));
    float n001 = hash13(i + float3(0, 0, 1));
    float n101 = hash13(i + float3(1, 0, 1));
    float n011 = hash13(i + float3(0, 1, 1));
    float n111 = hash13(i + float3(1, 1, 1));
    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

/// Sparse, soft round spots (one candidate per cell, jittered) — used for
/// nematocyst clusters and warts. `density` is the fraction of cells with a spot.
inline float spots2(float2 p, float density, float radius) {
    float2 cell = floor(p);
    float result = 0.0f;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 c = cell + float2(x, y);
            float h = hash12(c);
            if (h > density) continue;
            float2 centre = c + 0.2f + 0.6f * float2(hash12(c + 17.3f), hash12(c + 41.7f));
            float r = radius * (0.6f + 0.8f * hash12(c + 7.9f));
            result = max(result, 1.0f - smoothstep(r * 0.4f, r, distance(p, centre)));
        }
    }
    return result;
}

inline float fbm2(float2 p) {
    float v = 0.0f;
    float a = 0.5f;
    for (int i = 0; i < 4; i++) {
        v += a * valueNoise2(p);
        p = p * 2.03f + 17.1f;
        a *= 0.5f;
    }
    return v;
}

inline float fbm3(float3 p) {
    float v = 0.0f;
    float a = 0.5f;
    for (int i = 0; i < 3; i++) {
        v += a * valueNoise3(p);
        p = p * 2.07f + 11.3f;
        a *= 0.5f;
    }
    return v;
}

// MARK: - Swimming rhythm

/// Bell contraction (0 = relaxed, 1 = fully contracted) at time `t`.
/// A quick, smooth power stroke is followed by a slow elastic recovery.
/// The phase drifts slightly so the rhythm never feels metronomic.
inline float pulseAt(float t, float period) {
    float ph = t / period + 0.05f * sin(t * 0.21f) + 0.03f * sin(t * 0.077f + 1.3f);
    float f = fract(ph);
    const float c = 0.34f;
    if (f < c) {
        float x = f / c;
        return x * x * (3.0f - 2.0f * x);
    }
    float x = (f - c) / (1.0f - c);
    float v = exp(-4.0f * x) * (1.0f + 4.0f * x);   // zero slope at the start of recovery
    const float v1 = 0.0915782f;                     // value at x = 1
    return (v - v1) / (1.0f - v1);
}

/// Gentle vertical displacement of the body: each stroke lifts it slightly.
inline float bodyBob(float t, constant FrameUniforms& f) {
    return 0.07f * pulseAt(t - 0.35f, f.anim.x) * f.anim.y + 0.03f * sin(t * 0.23f);
}

// MARK: - Bell (umbrella) anatomy

/// Exumbrella surface point in body space for profile coordinate `u`
/// (0 = apex, 1 = margin) and angle `theta`.
inline float3 bellSurface(float u, float theta, float t,
                          constant FrameUniforms& f, constant AnatomyUniforms& a) {
    float R = a.bell.x;
    float H = a.bell.y;

    // Scalloped margin: rounded lappets separated by narrow notches (rhopalia sites).
    float scallop = sqrt(abs(sin(theta * a.bell2.x * 0.5f)));
    float edge = 1.0f - a.bell.w * (1.0f - scallop);
    float phi = a.bell.z * u * mix(1.0f, edge, smoothstep(0.6f, 1.0f, u));

    // The contraction wave starts at the margin muscles and lags slightly toward the apex.
    float p = pulseAt(t - u * 0.22f, f.anim.x) * f.anim.y;

    float r = R * sin(phi);
    float y = H * cos(phi);
    float k = u * u;
    r *= 1.0f - 0.24f * p * k;
    y = y * (1.0f + 0.10f * p) - 0.10f * p * k;

    // Slow asymmetric undulation so the bell never looks perfectly rigid.
    float wobble = 0.018f * pow(u, 4.0f) * sin(3.0f * theta + t * 0.6f)
                 + 0.010f * pow(u, 3.0f) * sin(5.0f * theta - t * 0.45f + 1.7f);
    y += wobble;
    r *= 1.0f + 0.6f * wobble;

    return float3(r * cos(theta), y, r * sin(theta));
}

/// Mesoglea thickness: thick jelly at the apex, paper-thin at the margin.
inline float bellThickness(float u, constant AnatomyUniforms& a) {
    return mix(a.bell2.z, a.bell2.y, pow(1.0f - saturate(u), 1.4f));
}

/// Exumbrella position plus outward normal (finite differences of `bellSurface`).
inline void bellFrame(float u, float theta, float t,
                      constant FrameUniforms& f, constant AnatomyUniforms& a,
                      thread float3& P, thread float3& N) {
    const float e = 0.003f;
    P = bellSurface(u, theta, t, f, a);
    float3 du = bellSurface(min(u + e, 1.0f), theta, t, f, a) - bellSurface(max(u - e, 0.0f), theta, t, f, a);
    float3 dt = bellSurface(u, theta + e, t, f, a) - bellSurface(u, theta - e, t, f, a);
    float3 n = cross(dt, du);
    float len = length(n);
    N = len > 1e-9f ? n / len : float3(0, 1, 0);
}

/// Underside of the bell apex where the manubrium hangs.
inline float3 subumbrellaApex(float t, constant FrameUniforms& f, constant AnatomyUniforms& a) {
    return bellSurface(0.0f, 0.0f, t, f, a) - float3(0.0f, a.bell2.y, 0.0f);
}

// MARK: - Shading

struct TissueLight {
    float3 irradiance;
    float3 specular;
};

/// Light arriving at thin, translucent tissue: wrapped diffuse scattering,
/// transmission when the light is behind the tissue, a hemispherical
/// ambient term from the water column, and a wet specular glint.
inline TissueLight tissueLight(float3 N, float3 V,
                               constant FrameUniforms& f, constant MaterialUniforms& m) {
    float3 L = f.keyLightDir.xyz;
    float3 F = f.fillLightDir.xyz;
    float3 Nf = dot(N, V) < 0.0f ? -N : N;

    float key  = 0.3f + 0.7f * saturate(0.5f + 0.5f * dot(N, L));
    float fill = saturate(0.5f + 0.5f * dot(N, F));
    float trans = pow(saturate(dot(-V, L)), 3.0f) * m.params.w;
    float3 ambient = mix(f.ambientBottom.rgb, f.ambientTop.rgb, 0.5f + 0.5f * N.y);

    TissueLight result;
    result.irradiance = ambient
        + f.keyLightColor.rgb * f.keyLightDir.w * (key * m.params.y + trans)
        + f.fillLightColor.rgb * f.fillLightDir.w * fill * m.params.y;

    float3 H = normalize(L + V);
    float spec = pow(saturate(dot(Nf, H)), 96.0f) * m.params.z;
    result.specular = spec * f.keyLightColor.rgb * f.keyLightDir.w;
    return result;
}

/// Water absorbs red light first; distant tissue shifts toward blue and fades.
/// Fragments extremely close to the camera fade out instead of clipping hard.
inline float4 applyWater(float4 c, float3 worldPos, constant FrameUniforms& f) {
    float d = distance(worldPos, f.cameraPos.xyz);
    float3 att = exp(-d * float3(0.075f, 0.035f, 0.02f));
    float nearFade = smoothstep(0.08f, 0.6f, d);
    c.rgb *= att * nearFade;
    c.a *= nearFade;
    return c;
}

#endif
