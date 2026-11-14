//
//  Jellyfish.metal
//  Vertex + fragment shaders for each anatomical part of the jellyfish.
//
//  Buffer conventions
//    vertex:   0 = PartVertex[], 1 = FrameUniforms, 2 = AnatomyUniforms
//    fragment: 0 = FrameUniforms, 1 = MaterialUniforms, 2 = AnatomyUniforms
//
//  All parts output premultiplied colour: rgb = light scattered toward the
//  viewer, a = how much of the background the tissue absorbs (kept small).
//

#include "ShaderCommon.h"

struct TissueOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;
    float2 aux;
};

// MARK: - Bell

struct BellOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;          // x = profile u, y = theta
    float layer [[flat]];  // 0 = exumbrella (outer), 1 = subumbrella (inner)
};

vertex BellOut bellVertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device PartVertex* verts [[buffer(0)]],
                          constant FrameUniforms& f [[buffer(1)]],
                          constant AnatomyUniforms& a [[buffer(2)]]) {
    float2 uv = verts[vid].p0.xy;
    float t = f.cameraPos.w;

    float3 P, N;
    bellFrame(uv.x, uv.y, t, f, a, P, N);
    if (iid == 1) {
        P -= N * bellThickness(uv.x, a);
    }
    P.y += bodyBob(t, f);

    BellOut out;
    out.position = f.viewProj * float4(P, 1.0f);
    out.worldPos = P;
    out.normal = N;
    out.uv = uv;
    out.layer = float(iid);
    return out;
}

fragment float4 bellFragment(BellOut in [[stage_in]],
                             constant FrameUniforms& f [[buffer(0)]],
                             constant MaterialUniforms& m [[buffer(1)]],
                             constant AnatomyUniforms& a [[buffer(2)]]) {
    float u = saturate(in.uv.x);
    float theta = in.uv.y;
    bool inner = in.layer > 0.5f;

    float3 N = normalize(in.normal);
    float3 V = normalize(f.cameraPos.xyz - in.worldPos);
    float fres = fresnelTerm(N, V, m.params.x);

    // Sector coordinates: one unit per lappet. Integer values sit on the
    // rhopalia (marginal notches); half-integers on the lappet centres.
    float lobes = a.bell2.x;
    float sx = theta * lobes / TAU;
    float d = sx - floor(sx + 0.5f);          // distance from rhopalial axis
    float e = fract(sx) - 0.5f;               // distance from lappet centre
    float sectorWidth = TAU / lobes * a.bell.x * max(sin(u * a.bell.z), 0.02f);
    float arcLen = a.bell.z * a.bell.x;       // profile length per unit u

    // Warm, dense mesoglea near the apex fading into a cool, glassy margin.
    float apex = pow(1.0f - u, 2.0f);
    float3 tint = mix(m.baseColor.rgb, m.accentColor.rgb, apex * m.accentColor.a);

    float detail = 0.0f;
    float density = 0.0f;
    if (inner) {
        // Gastrovascular canal system on the subumbrella.
        float lineW = 0.0045f + 0.0035f * u;
        float zone = smoothstep(0.22f, 0.32f, u) * (1.0f - smoothstep(0.93f, 0.945f, u));
        // Straight radial canals running to every rhopalium.
        float radial = 1.0f - smoothstep(lineW * 0.35f, lineW, abs(d) * sectorWidth);
        // Interradial canals that fork toward the margin.
        float spread = 0.2f * smoothstep(0.45f, 0.93f, u);
        float branch = 1.0f - smoothstep(lineW * 0.35f, lineW, abs(abs(e) - spread) * sectorWidth);
        // Fine anastomosing network near the margin.
        float net = valueNoise3(float3(cos(theta) * u, sin(theta) * u, 0.0f) * 26.0f);
        float mesh = (1.0f - smoothstep(0.0f, 0.06f, abs(net - 0.5f))) * smoothstep(0.7f, 0.92f, u) * 0.35f;
        // Ring canal circling just inside the margin.
        float ring = 1.0f - smoothstep(0.003f, 0.008f, abs(u - 0.938f) * arcLen);
        detail = max(max(radial, branch) * zone, max(ring, mesh * zone));

        // Four-lobed gastric cavity in the centre of the subumbrella.
        float gastric = (1.0f - smoothstep(0.1f, 0.28f, u)) * (0.65f + 0.35f * cos(4.0f * theta));
        density = gastric * 0.6f;
    } else {
        // Exumbrella: clusters of nematocyst warts and faint lappet ridges.
        float2 q = float2(cos(theta), sin(theta)) * u * 40.0f;
        float wart = spots2(q, 0.35f, 0.3f) * smoothstep(0.15f, 0.45f, u);
        float ridge = smoothstep(0.8f, 1.0f, u) * (1.0f - pow(abs(e) * 2.0f, 2.0f));
        detail = wart * 0.45f + ridge * 0.2f;
    }

    // Rhopalia: dense little sensory bodies sitting in each marginal notch.
    float rh = 1.0f - smoothstep(0.006f, 0.016f,
                                 length(float2(abs(d) * sectorWidth, (u - 0.975f) * arcLen)));
    // Thin margin edges catch the most light.
    float margin = smoothstep(0.9f, 1.0f, u);

    TissueLight lt = tissueLight(N, V, f, m);

    float opacity = m.baseColor.a * (1.0f + density) + m.rimColor.a * fres + margin * 0.05f;
    float3 emission = tint * opacity
                    + m.rimColor.rgb * fres * m.rimColor.a * 0.6f
                    + m.detailColor.rgb * detail * m.detailColor.a * (inner ? 0.18f : 0.08f)
                    + m.accentColor.rgb * density * 0.05f
                    + float3(1.0f, 0.85f, 0.55f) * rh * 0.35f;
    float3 color = emission * lt.irradiance * (inner ? 0.85f : 1.0f) + lt.specular * (0.25f + fres);
    float alpha = saturate(opacity * 0.45f + detail * 0.04f + rh * 0.3f);

    return applyWater(float4(color, alpha), in.worldPos, f);
}

// MARK: - Gonads

/// Point along gonad `gi` (horseshoe-shaped, hanging just beneath the
/// subumbrella) at arc parameter `s`, plus the local bell normal.
inline void gonadPoint(float gi, float s, float t,
                       constant FrameUniforms& f, constant AnatomyUniforms& a,
                       thread float3& P, thread float3& N) {
    float axis = gi * TAU / a.manubrium.w;
    const float beta0 = PI * 0.82f;
    float beta = mix(-beta0, beta0, s);
    float2 centre = a.gonad.x * float2(cos(axis), sin(axis));
    float2 q = centre + a.gonad.y * float2(cos(axis + beta), sin(axis + beta));
    float u = length(q);
    float th = atan2(q.y, q.x);

    float3 Pb;
    bellFrame(u, th, t, f, a, Pb, N);
    P = Pb - N * (bellThickness(u, a) + a.gonad.z * 1.1f);
}

vertex TissueOut gonadVertex(uint vid [[vertex_id]],
                             const device PartVertex* verts [[buffer(0)]],
                             constant FrameUniforms& f [[buffer(1)]],
                             constant AnatomyUniforms& a [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float gi = v.p0.x, s = v.p0.y, ang = v.p0.z;
    float t = f.cameraPos.w;

    float3 P0, N0, P1, N1, P2, N2;
    gonadPoint(gi, s, t, f, a, P0, N0);
    gonadPoint(gi, min(s + 0.01f, 1.0f), t, f, a, P1, N1);
    gonadPoint(gi, max(s - 0.01f, 0.0f), t, f, a, P2, N2);
    float3 T = normalize(P1 - P2);
    float3 B = normalize(cross(T, N0));

    // Folded, ribbon-like tissue that closes at both ends of the horseshoe.
    float taper = max(sqrt(sin(PI * saturate(s))), 0.08f);
    float frill = 1.0f + a.gonad.w * (0.5f * sin(s * 95.0f + ang * 2.0f)
                                    + 0.5f * sin(s * 41.0f - ang * 3.0f + gi * 1.7f));
    float r = a.gonad.z * taper * frill;
    const float flatten = 0.55f;
    float3 offset = cos(ang) * N0 * flatten + sin(ang) * B;
    float3 world = P0 + offset * r;
    world.y += bodyBob(t, f);

    TissueOut out;
    out.position = f.viewProj * float4(world, 1.0f);
    out.worldPos = world;
    out.normal = normalize(cos(ang) * N0 / flatten + sin(ang) * B);
    out.uv = float2(s, ang);
    out.aux = float2(frill, gi);
    return out;
}

fragment float4 gonadFragment(TissueOut in [[stage_in]],
                              constant FrameUniforms& f [[buffer(0)]],
                              constant MaterialUniforms& m [[buffer(1)]]) {
    float3 N = normalize(in.normal);
    float3 V = normalize(f.cameraPos.xyz - in.worldPos);
    float fres = fresnelTerm(N, V, m.params.x);

    // Folds of germinal tissue and speckles of developing gametes.
    float folds = 0.5f + 0.5f * sin(in.uv.x * 95.0f + in.uv.y * 2.0f + in.aux.y);
    float speckle = smoothstep(0.62f, 0.85f, valueNoise3(in.worldPos * 70.0f));

    TissueLight lt = tissueLight(N, V, f, m);
    float opacity = m.baseColor.a * (0.7f + 0.6f * folds) + m.rimColor.a * fres;
    float3 tint = mix(m.baseColor.rgb, m.accentColor.rgb, folds * m.accentColor.a);
    float3 emission = tint * opacity
                    + m.rimColor.rgb * fres * m.rimColor.a * 0.5f
                    + m.detailColor.rgb * speckle * m.detailColor.a * 0.15f;
    float3 color = emission * lt.irradiance + lt.specular * 0.4f;
    float alpha = saturate(opacity * 0.6f);
    return applyWater(float4(color, alpha), in.worldPos, f);
}

// MARK: - Manubrium

vertex TissueOut manubriumVertex(uint vid [[vertex_id]],
                                 const device PartVertex* verts [[buffer(0)]],
                                 constant FrameUniforms& f [[buffer(1)]],
                                 constant AnatomyUniforms& a [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float s = v.p0.x, ang = v.p0.y;
    float t = f.cameraPos.w;

    float3 apex = subumbrellaApex(t, f, a);
    float pd = pulseAt(t - 0.1f, f.anim.x) * f.anim.y;
    // Four-lobed stalk aligned with the oral arms, flaring where they begin.
    float lobes = 0.72f + 0.28f * cos(4.0f * (ang - PI * 0.25f));
    float r = a.manubrium.y * lobes * (1.0f + 0.7f * s * s) * (1.0f - 0.12f * pd);
    float3 dir = float3(cos(ang), 0.0f, sin(ang));
    float3 world = apex - float3(0.0f, s * a.manubrium.x, 0.0f) + dir * r;
    world.y += bodyBob(t, f);

    TissueOut out;
    out.position = f.viewProj * float4(world, 1.0f);
    out.worldPos = world;
    out.normal = normalize(dir + float3(0.0f, 0.3f, 0.0f));
    out.uv = float2(s, ang);
    out.aux = float2(lobes, 0.0f);
    return out;
}

fragment float4 manubriumFragment(TissueOut in [[stage_in]],
                                  constant FrameUniforms& f [[buffer(0)]],
                                  constant MaterialUniforms& m [[buffer(1)]]) {
    float3 N = normalize(in.normal);
    float3 V = normalize(f.cameraPos.xyz - in.worldPos);
    float fres = fresnelTerm(N, V, m.params.x);
    // Irregular folds of the mouth tube rather than regular stripes.
    float folds = valueNoise3(float3(cos(in.uv.y), sin(in.uv.y), in.uv.x * 3.0f) * 4.0f);
    // Blend smoothly into the subumbrella above and the oral arms below.
    float blend = smoothstep(0.0f, 0.25f, in.uv.x) * (1.0f - smoothstep(0.75f, 1.0f, in.uv.x) * 0.5f);

    TissueLight lt = tissueLight(N, V, f, m);
    float opacity = (m.baseColor.a * (0.8f + 0.5f * folds) + m.rimColor.a * fres) * blend;
    float3 emission = m.baseColor.rgb * opacity + m.rimColor.rgb * fres * m.rimColor.a * 0.4f * blend;
    float3 color = emission * lt.irradiance + lt.specular * 0.15f * blend;
    return applyWater(float4(color, saturate(opacity * 0.5f)), in.worldPos, f);
}

// MARK: - Oral arms

inline float oralArmLength(float seed, constant AnatomyUniforms& a) {
    return a.oralArm.x * (0.85f + 0.3f * seed);
}

inline float oralArmAngle(float ai, constant AnatomyUniforms& a) {
    return PI * 0.25f + ai * TAU / a.manubrium.z;
}

/// Centre line of oral arm `ai`. Lower sections respond to the body's
/// motion later than upper ones, so pulses ripple down the arm.
inline float3 oralArmSpine(float s, float ai, float seed, float t,
                           constant FrameUniforms& f, constant AnatomyUniforms& a) {
    float len = oralArmLength(seed, a);
    float L = s * len;
    float ts = t - L * f.anim.w;
    float pd = pulseAt(ts, f.anim.x) * f.anim.y;
    float ang = oralArmAngle(ai, a);

    float3 base = subumbrellaApex(t, f, a) - float3(0.0f, a.manubrium.x, 0.0f);
    float spread = a.manubrium.y * 1.3f + 0.16f * (1.0f - exp(-L * 1.5f)) + 0.05f * L;
    spread *= 1.0f - 0.18f * pd;
    float3 p = base + float3(cos(ang) * spread, -L * (1.0f - 0.03f * pd), sin(ang) * spread);

    // Independent, slow sway per arm.
    float ph = seed * TAU;
    float amp = f.anim.z * 0.07f * pow(s, 1.4f) * len;
    p.x += amp * (sin(t * 0.31f + ph + L * 0.8f) + 0.4f * sin(t * 0.57f + ph * 2.3f - L * 1.7f));
    p.z += amp * (cos(t * 0.27f + ph * 1.6f + L * 0.7f) + 0.4f * sin(t * 0.49f + ph * 0.7f - L * 1.5f));
    p += f.current.xyz * s * s * len * 0.15f;
    p.y += bodyBob(ts, f);
    return p;
}

/// Point on the curtain-like oral arm sheet: `s` along the arm, `w` across (-1…1).
inline float3 oralArmPoint(float s, float w, float ai, float seed, float t,
                           constant FrameUniforms& f, constant AnatomyUniforms& a) {
    const float ds = 0.004f;
    float3 c = oralArmSpine(s, ai, seed, t, f, a);
    float3 T = normalize(oralArmSpine(min(s + ds, 1.0f), ai, seed, t, f, a)
                       - oralArmSpine(max(s - ds, 0.0f), ai, seed, t, f, a));

    float ang = oralArmAngle(ai, a);
    float3 outward = float3(cos(ang), 0.0f, sin(ang));
    float3 B = normalize(outward - T * dot(outward, T));
    float3 N = cross(T, B);

    // The arm spirals gently along its length.
    float twist = a.oralArm.z * s + seed * 1.3f + 0.15f * sin(t * 0.2f + seed * 5.0f);
    float ct = cos(twist), st = sin(twist);
    float3 Bt = B * ct + N * st;
    float3 Nt = -B * st + N * ct;

    float len = oralArmLength(seed, a);
    float L = s * len;
    float width = a.oralArm.y * (0.45f + 0.55f * smoothstep(0.0f, 0.12f, s)) * (1.0f - 0.78f * s);

    // C-shaped cross-section: the sheet curls around the central canal.
    float alpha = w * 1.9f;
    float3 off = width * (sin(alpha) * Bt + (1.0f - cos(alpha)) * Nt * 0.85f);
    float3 sheetN = normalize(cross(T, cos(alpha) * Bt + sin(alpha) * Nt * 0.85f));

    // Margins are folded into slowly breathing ruffles.
    float edge = pow(abs(w), 2.2f);
    float ruffle = 0.65f * sin(L * 34.0f + w * 3.0f + seed * 11.0f + t * 0.35f)
                 + 0.35f * sin(L * 13.0f - w * 2.0f + seed * 3.0f - t * 0.22f);
    off += sheetN * ruffle * edge * a.oralArm.w * (width / a.oralArm.y + 0.25f);
    return c + off;
}

vertex TissueOut oralArmVertex(uint vid [[vertex_id]],
                               const device PartVertex* verts [[buffer(0)]],
                               constant FrameUniforms& f [[buffer(1)]],
                               constant AnatomyUniforms& a [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float ai = v.p0.x, s = v.p0.y, w = v.p0.z;
    float seed = v.p1.x;
    float t = f.cameraPos.w;

    float3 P = oralArmPoint(s, w, ai, seed, t, f, a);
    float s2 = s < 0.99f ? s + 0.004f : s - 0.004f;
    float w2 = w < 0.95f ? w + 0.03f : w - 0.03f;
    float3 Ps = oralArmPoint(s2, w, ai, seed, t, f, a);
    float3 Pw = oralArmPoint(s, w2, ai, seed, t, f, a);
    float3 n = cross(Ps - P, Pw - P);
    float ln = length(n);

    TissueOut out;
    out.position = f.viewProj * float4(P, 1.0f);
    out.worldPos = P;
    out.normal = ln > 1e-10f ? n / ln : float3(0, 1, 0);
    out.uv = float2(s, w);
    out.aux = float2(seed, oralArmLength(seed, a));
    return out;
}

fragment float4 oralArmFragment(TissueOut in [[stage_in]],
                                constant FrameUniforms& f [[buffer(0)]],
                                constant MaterialUniforms& m [[buffer(1)]]) {
    float s = in.uv.x, w = in.uv.y;
    float3 N = normalize(in.normal);
    float3 V = normalize(f.cameraPos.xyz - in.worldPos);
    float fres = fresnelTerm(N, V, m.params.x);

    float edgeMask = smoothstep(0.55f, 1.0f, abs(w));
    float canal = 1.0f - smoothstep(0.0f, 0.22f, abs(w));
    // Nematocyst clusters dotting the frilled margins.
    float2 cell = float2(s * in.aux.y * 36.0f, w * 12.0f);
    float dots = spots2(cell + in.aux.x * 50.0f, 0.45f, 0.32f) * edgeMask;
    float tipFade = 1.0f - smoothstep(0.82f, 1.0f, s);

    TissueLight lt = tissueLight(N, V, f, m);
    float3 tint = mix(m.baseColor.rgb, m.detailColor.rgb, edgeMask * m.detailColor.a);
    tint = mix(tint, m.accentColor.rgb, canal * m.accentColor.a);
    float opacity = m.baseColor.a * (1.0f + canal * 1.2f + edgeMask * 0.8f) + m.rimColor.a * fres;
    float3 emission = tint * opacity
                    + m.rimColor.rgb * fres * m.rimColor.a * 0.5f
                    + m.detailColor.rgb * dots * 0.12f;
    float3 color = (emission * lt.irradiance + lt.specular * 0.35f) * tipFade;
    float alpha = saturate(opacity * 0.5f) * tipFade;
    return applyWater(float4(color, alpha), in.worldPos, f);
}

// MARK: - Marginal tentacles

/// Centre line of a marginal tentacle hanging from the bell margin.
inline float3 tentacleCenter(float s, float rootTheta, float len, float seed, float t,
                             constant FrameUniforms& f, constant AnatomyUniforms& a) {
    float L = s * len;
    float ts = t - L * f.anim.w;
    float rootU = a.bell2.w;

    // The lower tentacle follows where the margin *was* a moment ago,
    // so each stroke travels down the tentacle as a soft wave.
    float3 root = bellSurface(rootU, rootTheta, t, f, a);
    float3 delayed = bellSurface(rootU, rootTheta, ts, f, a);
    float2 radial = float2(cos(rootTheta), sin(rootTheta));

    float3 p = root;
    p.xz = mix(root.xz, delayed.xz, smoothstep(0.0f, 0.4f, L));
    p.y -= L;
    p.xz += radial * 0.1f * (1.0f - exp(-L * 3.0f));

    // Slow, independent sway.
    float ph = seed * TAU;
    float amp = f.anim.z * 0.1f * pow(s, 1.3f) * len;
    p.x += amp * (sin(t * 0.37f + ph + L * 1.1f) + 0.5f * sin(t * 0.61f + ph * 1.7f - L * 2.3f));
    p.z += amp * (cos(t * 0.29f + ph * 1.3f + L * 0.9f) + 0.5f * sin(t * 0.53f + ph * 2.1f - L * 1.9f));

    // Fine kinks from muscle tone.
    float kink = 0.014f * smoothstep(0.0f, 0.3f, s);
    p.xz += kink * float2(sin(L * 9.0f + seed * 20.0f + t * 0.8f), cos(L * 7.3f + seed * 13.0f - t * 0.7f));

    // The water current carries the tips.
    p += f.current.xyz * s * s * len * 0.25f;
    p.y += bodyBob(ts, f);
    return p;
}

struct TentacleOut {
    float4 position [[position]];
    float3 worldPos;
    float3 sideDir;
    float across;
    float s;
    float coverage;
    float bead;
};

vertex TentacleOut tentacleVertex(uint vid [[vertex_id]],
                                  const device PartVertex* verts [[buffer(0)]],
                                  constant FrameUniforms& f [[buffer(1)]],
                                  constant AnatomyUniforms& a [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float s = v.p0.y, side = v.p0.z;
    float rootTheta = v.p1.x, len = v.p1.y, radius = v.p1.z, seed = v.p1.w;
    float t = f.cameraPos.w;

    const float ds = 0.006f;
    float3 c = tentacleCenter(s, rootTheta, len, seed, t, f, a);
    float3 T = normalize(tentacleCenter(min(s + ds, 1.0f), rootTheta, len, seed, t, f, a)
                       - tentacleCenter(max(s - ds, 0.0f), rootTheta, len, seed, t, f, a));

    // Camera-facing ribbon. Its width never drops below ~1 pixel; thinner
    // tentacles fade instead, which keeps them from shimmering.
    float3 toCam = f.cameraPos.xyz - c;
    float dist = length(toCam);
    float3 sideDir = cross(T, toCam);
    float sl = length(sideDir);
    sideDir = sl > 1e-6f ? sideDir / sl : float3(1, 0, 0);

    float bead = pow(saturate(0.5f + 0.5f * sin(s * len * a.tentacle.y + seed * 40.0f)), 6.0f);
    float r = radius * mix(1.0f, a.tentacle.x, pow(s, 0.7f)) * (1.0f + a.tentacle.z * bead);
    float pixel = dist * f.viewport.z;
    float halfWidth = max(r, pixel * 0.7f);

    float3 world = c + sideDir * side * halfWidth;

    TentacleOut out;
    out.position = f.viewProj * float4(world, 1.0f);
    out.worldPos = world;
    out.sideDir = sideDir;
    out.across = side;
    out.s = s;
    out.coverage = r / halfWidth;
    out.bead = bead;
    return out;
}

fragment float4 tentacleFragment(TentacleOut in [[stage_in]],
                                 constant FrameUniforms& f [[buffer(0)]],
                                 constant MaterialUniforms& m [[buffer(1)]]) {
    float x = clamp(in.across, -1.0f, 1.0f);
    float3 V = normalize(f.cameraPos.xyz - in.worldPos);
    // Reconstruct a cylindrical normal across the ribbon.
    float3 N = normalize(in.sideDir * x + V * sqrt(max(1.0f - x * x, 0.0f)));

    // Transparent tube: brighter at the silhouette, soft anti-aliased edge.
    float edgeGlow = 0.45f + 0.55f * x * x;
    float aa = 1.0f - smoothstep(0.6f, 1.0f, abs(x));
    float tipFade = 1.0f - smoothstep(0.8f, 1.0f, in.s);

    TissueLight lt = tissueLight(N, V, f, m);
    float3 tint = mix(m.baseColor.rgb, m.detailColor.rgb, in.bead * m.detailColor.a);
    float opacity = (m.baseColor.a * edgeGlow + m.rimColor.a * x * x * 0.4f) * (1.0f + in.bead * 0.6f);
    float k = aa * tipFade * in.coverage;
    float3 color = (tint * opacity * lt.irradiance + lt.specular * 0.2f) * k;
    float alpha = saturate(opacity * 0.5f) * k;
    return applyWater(float4(color, alpha), in.worldPos, f);
}
