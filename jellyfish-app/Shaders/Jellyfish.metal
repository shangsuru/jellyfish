//
//  Jellyfish.metal
//  クラゲの各解剖学的部位の頂点シェーダとフラグメントシェーダ。
//
//  バッファの割り当て
//    頂点:         0 = PartVertex[], 1 = FrameUniforms, 2 = AnatomyUniforms
//    フラグメント: 0 = FrameUniforms, 1 = MaterialUniforms, 2 = AnatomyUniforms
//
//  すべての部位は乗算済みアルファの色を出力する: rgb = 視点に向かって散乱した光、
//  a = 組織が背景をどれだけ吸収するか（小さく抑える）。
//

#include "ShaderCommon.h"

struct TissueOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;
    float2 aux;
};

// MARK: - 傘

struct BellOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;          // x = 断面の u、y = theta
    float layer [[flat]];  // 0 = 外傘（外側）、1 = 下傘（内側）
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

    // 扇形セクタ座標: 縁弁1枚につき1単位。整数値は感覚器（傘縁の切れ込み）上、
    // 半整数は縁弁の中心に位置する。
    float lobes = a.bell2.x;
    float sx = theta * lobes / TAU;
    float d = sx - floor(sx + 0.5f);          // 感覚器の軸からの距離
    float e = fract(sx) - 0.5f;               // 縁弁の中心からの距離
    float sectorWidth = TAU / lobes * a.bell.x * max(sin(u * a.bell.z), 0.02f);
    float arcLen = a.bell.z * a.bell.x;       // u 1単位あたりの断面の長さ

    // 頂部付近の温かく密な間充ゲルが、冷たくガラスのような傘縁へと移り変わる。
    float apex = pow(1.0f - u, 2.0f);
    float3 tint = mix(m.baseColor.rgb, m.accentColor.rgb, apex * m.accentColor.a);

    float detail = 0.0f;
    float density = 0.0f;
    if (inner) {
        // 下傘面の胃水管系。
        float lineW = 0.0045f + 0.0035f * u;
        float zone = smoothstep(0.22f, 0.32f, u) * (1.0f - smoothstep(0.93f, 0.945f, u));
        // 各感覚器へまっすぐ伸びる放射水管。
        float radial = 1.0f - smoothstep(lineW * 0.35f, lineW, abs(d) * sectorWidth);
        // 傘縁に向かって分岐する間輻水管。
        float spread = 0.2f * smoothstep(0.45f, 0.93f, u);
        float branch = 1.0f - smoothstep(lineW * 0.35f, lineW, abs(abs(e) - spread) * sectorWidth);
        // 傘縁付近の細かな網目状の吻合。
        float net = valueNoise3(float3(cos(theta) * u, sin(theta) * u, 0.0f) * 26.0f);
        float mesh = (1.0f - smoothstep(0.0f, 0.06f, abs(net - 0.5f))) * smoothstep(0.7f, 0.92f, u) * 0.35f;
        // 傘縁のすぐ内側を一周する環状水管。
        float ring = 1.0f - smoothstep(0.003f, 0.008f, abs(u - 0.938f) * arcLen);
        detail = max(max(radial, branch) * zone, max(ring, mesh * zone));

        // 下傘面の中央にある4葉の胃腔。
        float gastric = (1.0f - smoothstep(0.1f, 0.28f, u)) * (0.65f + 0.35f * cos(4.0f * theta));
        density = gastric * 0.6f;
    } else {
        // 外傘: 刺胞のいぼの集まりと、かすかな縁弁の稜線。
        float2 q = float2(cos(theta), sin(theta)) * u * 40.0f;
        float wart = spots2(q, 0.35f, 0.3f) * smoothstep(0.15f, 0.45f, u);
        float ridge = smoothstep(0.8f, 1.0f, u) * (1.0f - pow(abs(e) * 2.0f, 2.0f));
        detail = wart * 0.45f + ridge * 0.2f;
    }

    // 感覚器: 傘縁の各切れ込みにある小さく密な感覚器官。
    float rh = 1.0f - smoothstep(0.006f, 0.016f,
                                 length(float2(abs(d) * sectorWidth, (u - 0.975f) * arcLen)));
    // 薄い傘縁は最も多く光を受ける。
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

// MARK: - 生殖腺

/// 弧パラメータ `s` における生殖腺 `gi`（馬蹄形で、下傘面のすぐ下に
/// 垂れ下がる）上の点と、その位置での傘の法線。
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

    // 馬蹄形の両端で閉じる、折りたたまれたリボン状の組織。
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

    // 生殖組織のひだと、発達中の配偶子の斑点。
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

// MARK: - 口柄

vertex TissueOut manubriumVertex(uint vid [[vertex_id]],
                                 const device PartVertex* verts [[buffer(0)]],
                                 constant FrameUniforms& f [[buffer(1)]],
                                 constant AnatomyUniforms& a [[buffer(2)]]) {
    PartVertex v = verts[vid];
    float s = v.p0.x, ang = v.p0.y;
    float t = f.cameraPos.w;

    float3 apex = subumbrellaApex(t, f, a);
    float pd = pulseAt(t - 0.1f, f.anim.x) * f.anim.y;
    // 口腕と向きを揃えた4葉の柄で、口腕の付け根に向かって広がる。
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
    // 規則的な縞ではなく、口の管の不規則なひだ。
    float folds = valueNoise3(float3(cos(in.uv.y), sin(in.uv.y), in.uv.x * 3.0f) * 4.0f);
    // 上の下傘面と下の口腕に滑らかになじませる。
    float blend = smoothstep(0.0f, 0.25f, in.uv.x) * (1.0f - smoothstep(0.75f, 1.0f, in.uv.x) * 0.5f);

    TissueLight lt = tissueLight(N, V, f, m);
    float opacity = (m.baseColor.a * (0.8f + 0.5f * folds) + m.rimColor.a * fres) * blend;
    float3 emission = m.baseColor.rgb * opacity + m.rimColor.rgb * fres * m.rimColor.a * 0.4f * blend;
    float3 color = emission * lt.irradiance + lt.specular * 0.15f * blend;
    return applyWater(float4(color, saturate(opacity * 0.5f)), in.worldPos, f);
}

// MARK: - 口腕

inline float oralArmLength(float seed, constant AnatomyUniforms& a) {
    return a.oralArm.x * (0.85f + 0.3f * seed);
}

inline float oralArmAngle(float ai, constant AnatomyUniforms& a) {
    return PI * 0.25f + ai * TAU / a.manubrium.z;
}

/// 口腕 `ai` の中心線。下の部分ほど体の動きへの反応が遅れるため、
/// 拍動が口腕を波のように伝わって下りていく。
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

    // 口腕ごとに独立した、ゆっくりとした揺れ。
    float ph = seed * TAU;
    float amp = f.anim.z * 0.07f * pow(s, 1.4f) * len;
    p.x += amp * (sin(t * 0.31f + ph + L * 0.8f) + 0.4f * sin(t * 0.57f + ph * 2.3f - L * 1.7f));
    p.z += amp * (cos(t * 0.27f + ph * 1.6f + L * 0.7f) + 0.4f * sin(t * 0.49f + ph * 0.7f - L * 1.5f));
    p += f.current.xyz * s * s * len * 0.15f;
    p.y += bodyBob(ts, f);
    return p;
}

/// カーテン状の口腕シート上の点: `s` は口腕に沿った位置、`w` は横方向（-1…1）。
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

    // 口腕は長さに沿って緩やかにらせんを描く。
    float twist = a.oralArm.z * s + seed * 1.3f + 0.15f * sin(t * 0.2f + seed * 5.0f);
    float ct = cos(twist), st = sin(twist);
    float3 Bt = B * ct + N * st;
    float3 Nt = -B * st + N * ct;

    float len = oralArmLength(seed, a);
    float L = s * len;
    float width = a.oralArm.y * (0.45f + 0.55f * smoothstep(0.0f, 0.12f, s)) * (1.0f - 0.78f * s);

    // C字型の断面: シートが中央の水管を包むように丸まる。
    float alpha = w * 1.9f;
    float3 off = width * (sin(alpha) * Bt + (1.0f - cos(alpha)) * Nt * 0.85f);
    float3 sheetN = normalize(cross(T, cos(alpha) * Bt + sin(alpha) * Nt * 0.85f));

    // 縁はゆっくり呼吸するようなひだに折りたたまれている。
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
    // ひだ状の縁に点在する刺胞の集まり。
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

// MARK: - 縁触手

/// 傘縁から垂れ下がる縁触手の中心線。
inline float3 tentacleCenter(float s, float rootTheta, float len, float seed, float t,
                             constant FrameUniforms& f, constant AnatomyUniforms& a) {
    float L = s * len;
    float ts = t - L * f.anim.w;
    float rootU = a.bell2.w;

    // 触手の下部は少し前に傘縁が *あった* 位置を追うため、
    // ストロークのたびに柔らかな波として触手を伝わり下りる。
    float3 root = bellSurface(rootU, rootTheta, t, f, a);
    float3 delayed = bellSurface(rootU, rootTheta, ts, f, a);
    float2 radial = float2(cos(rootTheta), sin(rootTheta));

    float3 p = root;
    p.xz = mix(root.xz, delayed.xz, smoothstep(0.0f, 0.4f, L));
    p.y -= L;
    p.xz += radial * 0.1f * (1.0f - exp(-L * 3.0f));

    // ゆっくりとした独立した揺れ。
    float ph = seed * TAU;
    float amp = f.anim.z * 0.1f * pow(s, 1.3f) * len;
    p.x += amp * (sin(t * 0.37f + ph + L * 1.1f) + 0.5f * sin(t * 0.61f + ph * 1.7f - L * 2.3f));
    p.z += amp * (cos(t * 0.29f + ph * 1.3f + L * 0.9f) + 0.5f * sin(t * 0.53f + ph * 2.1f - L * 1.9f));

    // 筋緊張による細かなよじれ。
    float kink = 0.014f * smoothstep(0.0f, 0.3f, s);
    p.xz += kink * float2(sin(L * 9.0f + seed * 20.0f + t * 0.8f), cos(L * 7.3f + seed * 13.0f - t * 0.7f));

    // 水流が先端を運ぶ。
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

    // カメラに正対するリボン。幅は約1ピクセルを下回らず、それより細い
    // 触手は代わりに薄くすることで、ちらつきを防ぐ。
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
    // リボンの横方向に円柱状の法線を再構成する。
    float3 N = normalize(in.sideDir * x + V * sqrt(max(1.0f - x * x, 0.0f)));

    // 透明な管: 輪郭ほど明るく、縁はアンチエイリアスで柔らかくする。
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
