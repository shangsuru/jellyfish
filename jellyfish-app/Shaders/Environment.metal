//
//  Environment.metal
//  The water column around the specimen: a direction-based underwater
//  backdrop (depth gradient, Snell's window, light shafts) and softly
//  drifting suspended particles that give the scene depth.
//

#include "ShaderCommon.h"

// MARK: - Water backdrop

/// Colour of the open water seen along world-space direction `d`.
/// Because it depends on direction rather than screen position, looking
/// up from beneath the jellyfish reveals the brighter surface above.
inline float3 waterColor(float3 d, float t, constant FrameUniforms& f) {
    float up = d.y;

    // Depth gradient: near-black abyss below, deep blue at eye level, lighter toward the surface.
    float3 deep = float3(0.0012f, 0.0035f, 0.010f);
    float3 mid  = float3(0.0040f, 0.0170f, 0.038f);
    float3 high = float3(0.0200f, 0.0750f, 0.120f);
    float3 col = mix(deep, mid, smoothstep(-0.7f, 0.2f, up));
    col = mix(col, high, pow(smoothstep(0.1f, 1.0f, up), 1.5f));

    // Large, slow variations in turbidity.
    float murk = fbm3(d * 2.2f + float3(0.0f, t * 0.01f, 0.0f));
    col *= 0.8f + 0.45f * murk;

    // Snell's window: the glow of the surface light from above.
    float sd = saturate(dot(d, f.keyLightDir.xyz));
    col += float3(0.04f, 0.12f, 0.17f) * pow(sd, 10.0f) * 0.8f;
    col += float3(0.25f, 0.40f, 0.45f) * pow(sd, 140.0f) * 0.35f;

    // Caustic shimmer within the window.
    if (up > 0.3f) {
        float2 sp = d.xz / max(up, 0.2f) * 2.5f;
        float c = fbm2(sp + float2(t * 0.05f, -t * 0.04f));
        col += float3(0.02f, 0.06f, 0.08f) * pow(c, 3.0f) * smoothstep(0.5f, 0.95f, up) * 2.0f;
    }

    // Light shafts radiating down from the surface.
    float2 az = normalize(d.xz + float2(1e-5f, 0.0f));
    float r1 = fbm2(az * 3.5f + float2(t * 0.015f, -t * 0.011f));
    float r2 = fbm2(az * 7.0f + float2(-t * 0.02f, t * 0.017f) + 5.3f);
    float rays = pow(smoothstep(0.35f, 0.78f, r1), 2.0f) * 0.7f + pow(smoothstep(0.4f, 0.8f, r2), 2.0f) * 0.3f;
    float band = smoothstep(-0.55f, 0.35f, up) * (1.0f - smoothstep(0.6f, 0.97f, up));
    col += float3(0.012f, 0.045f, 0.065f) * rays * band;

    return col;
}

vertex FullscreenOut backgroundVertex(uint vid [[vertex_id]]) {
    return fullscreenTriangle(vid);
}

fragment float4 backgroundFragment(FullscreenOut in [[stage_in]],
                                   constant FrameUniforms& f [[buffer(0)]]) {
    float2 ndc = float2(in.uv.x * 2.0f - 1.0f, 1.0f - in.uv.y * 2.0f);
    float4 world = f.invViewProj * float4(ndc, 1.0f, 1.0f);
    float3 dir = normalize(world.xyz / world.w - f.cameraPos.xyz);
    return float4(waterColor(dir, f.cameraPos.w, f), 1.0f);
}

// MARK: - Suspended particles ("marine snow")

struct ParticleOut {
    float4 position [[position]];
    float2 corner;
    float intensity;
};

/// `field`: xyz = centre of the particle volume, w = edge length.
vertex ParticleOut particleVertex(uint vid [[vertex_id]],
                                  const device PartVertex* verts [[buffer(0)]],
                                  constant FrameUniforms& f [[buffer(1)]],
                                  constant float4& field [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float3 base = v.p0.xyz;
    float size = v.p0.w;
    float2 corner = v.p1.xy;
    float seed = v.p1.z;
    float brightness = v.p1.w;
    float t = f.cameraPos.w;

    // Slow drift with a little meander; positions wrap inside a box
    // that follows the camera, so the water always feels populated.
    float3 drift = float3(0.012f, 0.028f, -0.009f) * (0.5f + seed);
    float3 p = base + drift * t + 0.05f * float3(sin(t * 0.3f + seed * 30.0f), 0.0f, cos(t * 0.25f + seed * 17.0f));
    float3 rel = fract((p - field.xyz) / field.w + 0.5f) - 0.5f;
    float3 world = field.xyz + rel * field.w;
    float edge = max(abs(rel.x), max(abs(rel.y), abs(rel.z))) * 2.0f;
    float fade = 1.0f - smoothstep(0.7f, 1.0f, edge);

    float dist = distance(world, f.cameraPos.xyz);
    fade *= smoothstep(0.4f, 1.4f, dist);

    // Out-of-focus particles grow into faint bokeh discs.
    float blur = abs(dist - f.viewport.w) * 0.010f;
    float pixel = dist * f.viewport.z;
    float sizeWorld = max(size + blur, pixel * 1.5f);
    float energy = (size * size) / (sizeWorld * sizeWorld);

    float3 right = float3(f.view[0].x, f.view[1].x, f.view[2].x);
    float3 up = float3(f.view[0].y, f.view[1].y, f.view[2].y);
    world += (right * corner.x + up * corner.y) * sizeWorld;

    ParticleOut out;
    out.position = f.viewProj * float4(world, 1.0f);
    out.corner = corner;
    out.intensity = brightness * fade * clamp(energy, 0.03f, 1.0f) * exp(-dist * 0.06f);
    return out;
}

fragment float4 particleFragment(ParticleOut in [[stage_in]]) {
    float r2 = dot(in.corner, in.corner);
    float disc = exp(-r2 * 4.0f) * (1.0f - smoothstep(0.8f, 1.0f, r2));
    float3 color = float3(0.5f, 0.68f, 0.8f) * in.intensity * disc;
    return float4(color, 0.0f);   // purely additive
}
