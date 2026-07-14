#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    ushort3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    uchar2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float2 uv;
};

struct Uniforms {
    float2 gridSize;
    float depthScale;
    float padding;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             constant float2 *offsets [[buffer(2)]],
                             uint vertexID [[vertex_id]])
{
    float2 corner = offsets[vertexID & 3];
    float2 cellPosition = float2(in.position.xy) + corner;
    float2 clipPosition = float2((cellPosition.x / uniforms.gridSize.x) * 2.0 - 1.0,
                                 1.0 - (cellPosition.y / uniforms.gridSize.y) * 2.0);
    float depth = clamp(float(in.position.z) * uniforms.depthScale, 0.0, 0.99);

    VertexOut out;
    out.position = float4(clipPosition, depth, 1.0);
    out.color = in.color;
    out.uv = (float2(in.texCoord) + corner) / 16.0;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> glyphs [[texture(0)]],
                              sampler glyphSampler [[sampler(0)]])
{
    float alpha = glyphs.sample(glyphSampler, in.uv).r;
    if (alpha == 0.0) {
        discard_fragment();
    }
    return float4(in.color.rgb, in.color.a * alpha);
}
