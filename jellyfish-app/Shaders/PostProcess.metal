//
//  PostProcess.metal
//  HDR ブルーム（明るい半透明の輪郭まわりの柔らかな光）、フィルム調の
//  トーンマッピング、控えめなビネット、そして暗い水のグラデーションで
//  バンディングを防ぐディザリング。
//

#include "ShaderCommon.h"

constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);

vertex FullscreenOut fullscreenVertex(uint vid [[vertex_id]]) {
    return fullscreenTriangle(vid);
}

/// HDR シーンを縮小し、明るい部分だけを残す。
fragment float4 bloomPrefilter(FullscreenOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]]) {
    float2 texel = 1.0f / float2(src.get_width(), src.get_height());
    // すべてのサンプルを無害化する: さもないと不正なピクセル1つが四角形に広がる。
    float3 c = sanitizeHDR(src.sample(linearClamp, in.uv + texel * float2(-1.0f, -1.0f)).rgb)
             + sanitizeHDR(src.sample(linearClamp, in.uv + texel * float2( 1.0f, -1.0f)).rgb)
             + sanitizeHDR(src.sample(linearClamp, in.uv + texel * float2(-1.0f,  1.0f)).rgb)
             + sanitizeHDR(src.sample(linearClamp, in.uv + texel * float2( 1.0f,  1.0f)).rgb);
    c *= 0.25f;
    float l = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
    return float4(c * smoothstep(0.08f, 0.6f, l), 1.0f);
}

/// 分離可能な9タップのガウスぼかし。`stepUV` で方向と半径を指定する。
fragment float4 bloomBlur(FullscreenOut in [[stage_in]],
                          texture2d<float> src [[texture(0)]],
                          constant float2& stepUV [[buffer(0)]]) {
    const float w[5] = { 0.2270270270f, 0.1945945946f, 0.1216216216f, 0.0540540541f, 0.0162162162f };
    float3 c = src.sample(linearClamp, in.uv).rgb * w[0];
    for (int i = 1; i < 5; i++) {
        float2 o = stepUV * float(i);
        c += src.sample(linearClamp, in.uv + o).rgb * w[i];
        c += src.sample(linearClamp, in.uv - o).rgb * w[i];
    }
    return float4(c, 1.0f);
}

/// `params`: x ブルームの強さ、y 露出、z 時刻、w ビネットの強さ。
fragment float4 compositeFragment(FullscreenOut in [[stage_in]],
                                  texture2d<float> scene [[texture(0)]],
                                  texture2d<float> bloom [[texture(1)]],
                                  constant float4& params [[buffer(0)]]) {
    float3 hdr = sanitizeHDR(scene.sample(linearClamp, in.uv).rgb) + sanitizeHDR(bloom.sample(linearClamp, in.uv).rgb) * params.x;
    hdr *= params.y;

    // フィルム調の ACES 近似（Narkowicz）。
    float3 mapped = saturate((hdr * (2.51f * hdr + 0.03f)) / (hdr * (2.43f * hdr + 0.59f) + 0.14f));

    float2 q = (in.uv - 0.5f) * float2(1.0f, 0.9f);
    mapped *= 1.0f - params.w * smoothstep(0.3f, 1.0f, length(q) * 1.4f);

    // リニア -> sRGB 変換の後、8ビット量子化の前に三角分布ディザをかける。
    float3 srgb = select(1.055f * pow(mapped, 1.0f / 2.4f) - 0.055f, mapped * 12.92f, mapped <= 0.0031308f);
    float2 px = in.position.xy;
    float n = hash12(px + fract(params.z) * 97.0f) + hash12(px * 1.37f + 7.1f) - 1.0f;
    srgb += n / 255.0f;
    return float4(srgb, 1.0f);
}
