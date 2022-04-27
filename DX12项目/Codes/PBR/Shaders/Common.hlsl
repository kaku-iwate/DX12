#ifndef NUM_DIR_LIGHTS
    #define NUM_DIR_LIGHTS 3
#endif

#ifndef NUM_POINT_LIGHTS
    #define NUM_POINT_LIGHTS 0
#endif

#ifndef NUM_SPOT_LIGHTS
    #define NUM_SPOT_LIGHTS 0
#endif

#include "LightingUtil.hlsl"

struct MaterialData
{
    float4 DiffuseAlbedo;
    float3 FresnelR0;
    float Roughness;
    float4x4 MatTransform;
    uint DiffuseMapIndex;
    uint NormalMapIndex;
    float metallic;
    uint MatPad2;
};

TextureCube gCubeMap : register(t0);

Texture2D gBRDFLUT : register(t1);

Texture2D gTextureMaps[10] : register(t2);
 
StructuredBuffer<MaterialData> gMaterialData : register(t0, space1);

SamplerState gsamPointWrap : register(s0);
SamplerState gsamPointClamp : register(s1);
SamplerState gsamLinearWrap : register(s2);
SamplerState gsamLinearClamp : register(s3);
SamplerState gsamAnisotropicWrap : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);

cbuffer cbPerObject : register(b0)
{
    float4x4 gWorld;
    float4x4 gTexTransform;
    uint gMaterialIndex;
    uint gObjPad0;
    uint gObjPad1;
    uint gObjPad2;
};

cbuffer cbPass : register(b1)
{
    float4x4 gView;
    float4x4 gInvView;
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float3 gEyePosW;
    float cbPerObjectPad1;
    float2 gRenderTargetSize;
    float2 gInvRenderTargetSize;
    float gNearZ;
    float gFarZ;
    float gTotalTime;
    float gDeltaTime;
    float4 gAmbientLight;

    Light gLights[MaxLights];
};

static float PI = 3.1415926;

//---------------------------------------------------------------------------------------
// 切线空间变换到世界空间
//---------------------------------------------------------------------------------------
float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float3 tangentW)
{
	// 将坐标分量由区间 [0,1] 转换到 [-1,1].
    float3 normalT = 2.0f * normalMapSample - 1.0f;

	// 构建正交规范基
    float3 N = unitNormalW;
    float3 T = normalize(tangentW - dot(tangentW, N) * N);
    float3 B = cross(N, T);

    float3x3 TBN = float3x3(T, B, N);

	// 将法线从切线空间变换到世界空间
    float3 bumpedNormalW = mul(normalT, TBN);

    return bumpedNormalW;
}

//--------------------------------------------------------
//  F菲涅尔项
//  F = R0 + (1 - R0) * a * a * a * a * a;
//  其中 a = (1 - VdotH), 或者(1 - LdotH), 因为 LdotH = VdotH
//  若使用NdotV代替VdotH, 则会导致较强边缘光
//--------------------------------------------------------
float3 F_Schlick(float3 R0, float VdotH)
{
    float a = 1 - VdotH;
    return R0 + (1 - R0) * (a * a * a * a * a);
}


//----------------------------------------------------------------------
// D项法线分布函数, 使用GGX模型
// D = a2 / (PI * d * d), 其中 d = ((n dot h) * (n dot h) * (a2 - 1) + 1)
// 相较于phong等模型, GGX拥有更长的尾部, 表现在画面上就是高光外围有一大圈光晕
//----------------------------------------------------------------------
float D_GGX(float NdotH, float roughness)
{
    roughness = lerp(0.1, 1.0, roughness); // 当粗糙度为0时, 分子的a2 = 0, 最后法线分布项返回0会导致高光消失
    float a = roughness * roughness;
    float a2 = a * a;
	
    float d = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
    float denom = PI * d * d;
    return a2 / denom;
}


//-----------------------------------------------------------------------
// G项几何遮蔽部分
// 几何遮蔽分为两部分, 其一: 入射光的几何阴影, 其二: 出射光的几何遮蔽
// 这两个部分使用GGX与Schlick-Beckmann结合的Schlick-GGX模型来计算
// 最后统合两部分的模型则被称为Smith
//------------------------
// 即 几何遮蔽 = Smith
// 而 Smith = Schlick-GGX(LightDir) * Schlick-GGX(ViewDir)
// 其中 Schlick-GGX(L) = NdotL /  (NdotL * (1 - k) + k)
// 这里的 k 是粗糙度的重映射, a = (roughness + 1) / 2 , k = (a * a) / 2
//-----------------------------------------------------------------------
float Schlick_GGX(float NdotL, float k)
{
    float denom = NdotL * (1 - k) + k;
    return NdotL / denom;
}

// a = (roughness + 1) / 2 , k = (a * a) / 2
// 这部分可直接化简为 k = (roughness + 1.0) * (roughness + 1.0) / 8
float G_Smith(float NdotL, float NdotV, float roughness)
{
    float a = roughness + 1.0f;
    float k = (a * a) / 8.0f;
    
    float ggx1 = Schlick_GGX(NdotL, k);
    float ggx2 = Schlick_GGX(NdotV, k);
    
    return ggx1 * ggx2;
}

// IBL部分粗糙度的重映射与直接光部分不同
// IBL：k = (roughness * roughness) / 2
float IBLG_Smith(float NdotL, float NdotV, float roughness)
{
    float k = (roughness * roughness) / 2.0f;
    
    float ggx1 = Schlick_GGX(NdotL, k);
    float ggx2 = Schlick_GGX(NdotV, k);
    
    return ggx1 * ggx2;
}

//----------------------------------
// 计算IBL漫反射部分
// 对法线半球进行采样求平均
//----------------------------------
float3 IBLDiffuseIrradiance(float3 normal)
{
    float3 up = { 0.0, 1.0, 0.0 };
    float3 right = cross(up, normal);
    up = cross(normal, right);

    float3 irradiance = (0.0f);
    float sampleDelta = 0.35;
    float nrSamples = 0.0;
    for (float phi = 0.0; phi < 2.0 * PI; phi += sampleDelta)
    {
        for (float theta = 0.0; theta < 0.5 * PI; theta += sampleDelta)
        {
        // 切线空间的坐标
            float3 tangentSample = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
        // 变换到世界空间
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;

            irradiance += gCubeMap.Sample(gsamLinearWrap, sampleVec).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    irradiance = PI * irradiance * (1.0 / float(nrSamples));
    
    return irradiance;
}


//------------------------------------------------------
//  计算镜面反射部分的BRDF项
//  公式：F0 * |BRDF(1 - k) * NdotL + |BRDF * k * NdotL
//  注 : |代表积分符号
//  其中 k = a * a * a * a * a,  a = (1 - NdotV)
//  上述公式简化为 F0 * A + B
//  A = |BRDF(1 - k) * NdotL,  B = |BRDF * k * NdotL
//  需要计算的就是A和B
//-------------------------------------------------------

//  1. 获取低差异序列
float RadicalInverse_VdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}
float2 Hammersley(uint i, uint N)
{
    return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness)
{
    float a = roughness * roughness;

    float phi = 2.0 * PI * Xi.x;
    float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a * a - 1.0) * Xi.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    // 球坐标到笛卡尔坐标
    float3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // 将采样向量从切线空间变换到世界空间
    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    float3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}


float2 IntegrateBRDF(float NdotV, float roughness)
{
    // 当NdotV很小(位于边缘,值接近0)或很大(位于球中心,值为1)时, 得到的结果会很暗
    // 为避免上述结果, 将其限制在[0.2, 0.99]
    //NdotV = lerp(0.3, 0.99, NdotV);
    
    float3 V;
    V.x = sqrt(1.0 - NdotV * NdotV);
    V.y = 0.0;
    V.z = NdotV;

    float A = 0.0;
    float B = 0.0;

    float3 N = float3(0.0, 0.0, 1.0);

    const uint SAMPLE_COUNT = 512;
    for (uint i = 0u; i < SAMPLE_COUNT; ++i)
    {
        // 获取低差异序列
        float2 Xi = Hammersley(i, SAMPLE_COUNT);
        // GGX重要性采样, 根据粗糙度, 法线分布等来生成采样向量
        float3 H = ImportanceSampleGGX(Xi, N, roughness);
        // 2 * LdotN * N - L， 计算反射向量的公式
        float3 L = normalize(2.0 * dot(V, H) * H - V);

        float NdotL = max(L.z, 0.0);
        float NdotH = max(H.z, 0.0);
        float VdotH = max(dot(V, H), 0.0);

        if (NdotL > 0.0)
        {
            float NdotL = max(dot(N, L), 0);
            float NdotV = max(dot(N, V), 0);
            float G = IBLG_Smith(NdotL, NdotV, roughness);
            float G_Vis = (G * VdotH) / (NdotH * NdotV);
            float Fc = pow(1.0 - VdotH, 5.0);

            A += (1.0 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }
    A /= float(SAMPLE_COUNT);
    B /= float(SAMPLE_COUNT);
    return float2(A, B);
}



