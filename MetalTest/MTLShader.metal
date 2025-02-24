//
//  MTLShader.metal
//  MetalTest
//
//  Created by 杨学思 on 2025/2/23.
//

#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

// 顶点着色器输入结构体
struct VertexIn {
    float3 position [[attribute(0)]];
};

// 顶点着色器输出结构体
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// 实例数据结构体
struct Instance {
    int modelIndex;
    float3 scale;
    float4x4 rotation;
    float3 translation;
};

// 统一变量结构体
struct Uniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
};

// 顶点着色器
vertex VertexOut vertex_main(const VertexIn vertices [[stage_in]],
                             const device Instance* instances [[buffer(1)]],
                             const device Uniforms& uniforms [[buffer(2)]],
                             uint instanceId [[instance_id]]) {
    Instance instance = instances[instanceId];
    
    // 构建模型矩阵
    float4x4 scaleMatrix = float4x4(float4(instance.scale.x, 0, 0, 0),
                                    float4(0, instance.scale.y, 0, 0),
                                    float4(0, 0, instance.scale.z, 0),
                                    float4(0, 0, 0, 1));
    
    // 简单的平移矩阵
    float4x4 translationMatrix = float4x4(float4(1, 0, 0, 0),
                                          float4(0, 1, 0, 0),
                                          float4(0, 0, 1, 0),
                                          float4(instance.translation, 1));
    
    float4x4 modelMatrix = translationMatrix * scaleMatrix * instance.rotation;
    
    // MVP 变换
    float4x4 mvpMatrix = uniforms.projectionMatrix * uniforms.viewMatrix * modelMatrix;
    
    VertexOut out;
    float4 v = mvpMatrix * float4(vertices.position, 1.0);

    float4 normalized = v / v.w;
    
    float theta = atan2(normalized.z, normalized.x);
    float uv_v = (normalized.y - (-1.0)) / (1.0 - (-1.0)); // 归一化到 0-1

    out.uv = float2((theta / (2.0 * M_PI_F)) + 0.5, uv_v);
    out.position = normalized;
    
    return out;
}

// 片段着色器
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return float4(in.uv, 0.0, 1.0);
}
