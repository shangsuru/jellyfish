//
//  ShaderCommon.h
//  すべてのクラゲ用シェーダで共有する型と関数。
//
//  クラゲは完全に GPU 上でアニメーションする: メッシュは
//  パラメトリック座標（例: 傘の断面上の位置 u と角度 θ）のみを持ち、
//  頂点シェーダが以下の解剖構造と遊泳運動を評価する。
//  構造体のレイアウトは RenderTypes.swift と常に一致させること。
//

#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <metal_stdlib>
using namespace metal;

#define PI  3.14159265359f
#define TAU 6.28318530718f

// MARK: - ユニフォームのレイアウト（RenderTypes.swift と対応）

struct FrameUniforms {
    float4x4 viewProj;
    float4x4 view;
    float4x4 invViewProj;
    float4 cameraPos;       // xyz カメラ位置、w 時刻（秒）
    float4 viewport;        // x 幅、y 高さ、z ピクセル角（2·tan(fov/2)/高さ）、w 焦点距離
    float4 keyLightDir;     // xyz 光源への方向（正規化済み）、w 強度
    float4 keyLightColor;
    float4 fillLightDir;    // xyz 光源への方向（正規化済み）、w 強度
    float4 fillLightColor;
    float4 ambientTop;
    float4 ambientBottom;
    float4 anim;            // x 拍動周期、y 収縮量、z 揺れ、w 遅延（単位長さあたりの秒数）
    float4 current;         // xyz 水流、w 未使用
};

struct AnatomyUniforms {
    float4 bell;       // x 半径、y 高さ、z 断面の掃引角（rad）、w 縁弁の深さ
    float4 bell2;      // x 縁弁の数、y 頂部の厚さ、z 傘縁の厚さ、w 触手の付け根の u
    float4 gonad;      // x 配置円の半径（u）、y 馬蹄形の半径（u）、z 管の半径、w ひだ
    float4 oralArm;    // x 長さ、y 幅、z ねじれ、w ひだの振幅
    float4 tentacle;   // x 先端の細り、y 数珠状のふくらみの頻度、z その強さ、w 未使用
    float4 manubrium;  // x 長さ、y 半径、z 口腕の数、w 生殖腺の数
};

struct MaterialUniforms {
    float4 baseColor;    // rgb 組織の色味、a 基本不透明度
    float4 rimColor;     // rgb 輪郭の発光、a 輪郭の不透明度
    float4 detailColor;  // rgb 細部（水管・ふくらみ・ひだ）、a 強さ
    float4 accentColor;  // rgb 副次的な色味、a 強さ
    float4 params;       // x フレネル指数、y 散乱、z 鏡面反射、w 透過
};

struct PartVertex {
    float4 p0;
    float4 p1;
};

// MARK: - フルスクリーンパス

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

/// ビューポート全体を覆う大きな三角形1枚。uv の y は下向き。
inline FullscreenOut fullscreenTriangle(uint vid) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut out;
    out.position = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
    out.uv = float2(p.x, 1.0f - p.y);
    return out;
}

// MARK: - ノイズ

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

/// まばらで柔らかい円形の斑点（セルごとに1候補、位置をランダムにずらす）。
/// 刺胞の集まりやいぼに使う。`density` は斑点を持つセルの割合。
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

// MARK: - 遊泳リズム

/// 時刻 `t` における傘の収縮量（0 = 弛緩、1 = 完全収縮）。
/// 素早く滑らかな推進ストロークの後に、ゆっくりとした弾性的な回復が続く。
/// 位相をわずかに揺らし、リズムがメトロノームのように感じられないようにする。
inline float pulseAt(float t, float period) {
    float ph = t / period + 0.05f * sin(t * 0.21f) + 0.03f * sin(t * 0.077f + 1.3f);
    float f = fract(ph);
    const float c = 0.34f;
    if (f < c) {
        float x = f / c;
        return x * x * (3.0f - 2.0f * x);
    }
    float x = (f - c) / (1.0f - c);
    float v = exp(-4.0f * x) * (1.0f + 4.0f * x);   // 回復開始時の傾きはゼロ
    const float v1 = 0.0915782f;                     // x = 1 での値
    return (v - v1) / (1.0f - v1);
}

/// 体の穏やかな上下動: ストロークのたびにわずかに持ち上がる。
inline float bodyBob(float t, constant FrameUniforms& f) {
    return 0.07f * pulseAt(t - 0.35f, f.anim.x) * f.anim.y + 0.03f * sin(t * 0.23f);
}

// MARK: - 傘の解剖構造

/// 断面座標 `u`（0 = 頂部、1 = 傘縁）と角度 `theta` に対する、
/// 体座標系での外傘面上の点。
inline float3 bellSurface(float u, float theta, float t,
                          constant FrameUniforms& f, constant AnatomyUniforms& a) {
    float R = a.bell.x;
    float H = a.bell.y;

    // 波形の傘縁: 丸い縁弁が細い切れ込み（感覚器のある位置）で区切られる。
    float scallop = sqrt(abs(sin(theta * a.bell2.x * 0.5f)));
    float edge = 1.0f - a.bell.w * (1.0f - scallop);
    float phi = a.bell.z * u * mix(1.0f, edge, smoothstep(0.6f, 1.0f, u));

    // 収縮波は傘縁の筋肉から始まり、頂部に向かってわずかに遅れて伝わる。
    float p = pulseAt(t - u * 0.22f, f.anim.x) * f.anim.y;

    float r = R * sin(phi);
    float y = H * cos(phi);
    float k = u * u;
    r *= 1.0f - 0.24f * p * k;
    y = y * (1.0f + 0.10f * p) - 0.10f * p * k;

    // ゆっくりとした非対称のうねりで、傘が完全に硬く見えないようにする。
    float wobble = 0.018f * pow(u, 4.0f) * sin(3.0f * theta + t * 0.6f)
                 + 0.010f * pow(u, 3.0f) * sin(5.0f * theta - t * 0.45f + 1.7f);
    y += wobble;
    r *= 1.0f + 0.6f * wobble;

    return float3(r * cos(theta), y, r * sin(theta));
}

/// 間充ゲルの厚さ: 頂部では厚く、傘縁では紙のように薄い。
inline float bellThickness(float u, constant AnatomyUniforms& a) {
    return mix(a.bell2.z, a.bell2.y, pow(1.0f - saturate(u), 1.4f));
}

/// 外傘面の位置と外向き法線（`bellSurface` の有限差分）。
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

/// 口柄が垂れ下がる、傘の頂部の下面。
inline float3 subumbrellaApex(float t, constant FrameUniforms& f, constant AnatomyUniforms& a) {
    return bellSurface(0.0f, 0.0f, t, f, a) - float3(0.0f, a.bell2.y, 0.0f);
}

// MARK: - 数値的な安全対策
//
// シェーダは fast math でビルドされ、pow(x, y) = exp2(y·log2(x)) となるため、
// 底がわずかでも負だと NaN になる。NaN のピクセルが1つでもあると、
// ブルームのぼかしで点滅する四角形に広がるため、底は常にクランプする。

/// 底が負にならないことを保証した、視線依存の輪郭項。
inline float fresnelTerm(float3 N, float3 V, float power) {
    return pow(saturate(1.0f - abs(dot(N, V))), power);
}

/// NaN/Inf を黒に置き換え、極端なハイライトをクランプする。
/// fast math では `isnan` が最適化で除去されうるため、ビット判定を使う。
inline float3 sanitizeHDR(float3 c) {
    uint3 bits = as_type<uint3>(c);
    bool3 bad = (bits & 0x7f800000u) == 0x7f800000u;
    return clamp(select(c, float3(0.0f), bad), 0.0f, 32.0f);
}

// MARK: - シェーディング

struct TissueLight {
    float3 irradiance;
    float3 specular;
};

/// 薄く半透明な組織に届く光: 回り込む拡散散乱、
/// 光が組織の背後にあるときの透過、水柱からの
/// 半球状の環境光、そして濡れたような鏡面のきらめき。
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

/// 水は赤い光から先に吸収するため、遠くの組織は青みを帯びて薄れる。
/// カメラに極端に近いフラグメントは、急に切れる代わりにフェードアウトする。
inline float4 applyWater(float4 c, float3 worldPos, constant FrameUniforms& f) {
    float d = distance(worldPos, f.cameraPos.xyz);
    float3 att = exp(-d * float3(0.075f, 0.035f, 0.02f));
    float nearFade = smoothstep(0.08f, 0.6f, d);
    c.rgb *= att * nearFade;
    c.a *= nearFade;
    return c;
}

#endif
