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
// ���߿ռ�任������ռ�
//---------------------------------------------------------------------------------------
float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float3 tangentW)
{
	// ��������������� [0,1] ת���� [-1,1].
    float3 normalT = 2.0f * normalMapSample - 1.0f;

	// ���������淶��
    float3 N = unitNormalW;
    float3 T = normalize(tangentW - dot(tangentW, N) * N);
    float3 B = cross(N, T);

    float3x3 TBN = float3x3(T, B, N);

	// �����ߴ����߿ռ�任������ռ�
    float3 bumpedNormalW = mul(normalT, TBN);

    return bumpedNormalW;
}

//--------------------------------------------------------
//  F��������
//  F = R0 + (1 - R0) * a * a * a * a * a;
//  ���� a = (1 - VdotH), ����(1 - LdotH), ��Ϊ LdotH = VdotH
//  ��ʹ��NdotV����VdotH, ��ᵼ�½�ǿ��Ե��
//--------------------------------------------------------
float3 F_Schlick(float3 R0, float VdotH)
{
    float a = 1 - VdotH;
    return R0 + (1 - R0) * (a * a * a * a * a);
}


//----------------------------------------------------------------------
// D��߷ֲ�����, ʹ��GGXģ��
// D = a2 / (PI * d * d), ���� d = ((n dot h) * (n dot h) * (a2 - 1) + 1)
// �����phong��ģ��, GGXӵ�и�����β��, �����ڻ����Ͼ��Ǹ߹���Χ��һ��Ȧ����
//----------------------------------------------------------------------
float D_GGX(float NdotH, float roughness)
{
    roughness = lerp(0.1, 1.0, roughness); // ���ֲڶ�Ϊ0ʱ, ���ӵ�a2 = 0, ����߷ֲ����0�ᵼ�¸߹���ʧ
    float a = roughness * roughness;
    float a2 = a * a;
	
    float d = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
    float denom = PI * d * d;
    return a2 / denom;
}


//-----------------------------------------------------------------------
// G����ڱβ���
// �����ڱη�Ϊ������, ��һ: �����ļ�����Ӱ, ���: �����ļ����ڱ�
// ����������ʹ��GGX��Schlick-Beckmann��ϵ�Schlick-GGXģ��������
// ���ͳ�������ֵ�ģ���򱻳�ΪSmith
//------------------------
// �� �����ڱ� = Smith
// �� Smith = Schlick-GGX(LightDir) * Schlick-GGX(ViewDir)
// ���� Schlick-GGX(L) = NdotL /  (NdotL * (1 - k) + k)
// ����� k �Ǵֲڶȵ���ӳ��, a = (roughness + 1) / 2 , k = (a * a) / 2
//-----------------------------------------------------------------------
float Schlick_GGX(float NdotL, float k)
{
    float denom = NdotL * (1 - k) + k;
    return NdotL / denom;
}

// a = (roughness + 1) / 2 , k = (a * a) / 2
// �ⲿ�ֿ�ֱ�ӻ���Ϊ k = (roughness + 1.0) * (roughness + 1.0) / 8
float G_Smith(float NdotL, float NdotV, float roughness)
{
    float a = roughness + 1.0f;
    float k = (a * a) / 8.0f;
    
    float ggx1 = Schlick_GGX(NdotL, k);
    float ggx2 = Schlick_GGX(NdotV, k);
    
    return ggx1 * ggx2;
}

// IBL���ֲִڶȵ���ӳ����ֱ�ӹⲿ�ֲ�ͬ
// IBL��k = (roughness * roughness) / 2
float IBLG_Smith(float NdotL, float NdotV, float roughness)
{
    float k = (roughness * roughness) / 2.0f;
    
    float ggx1 = Schlick_GGX(NdotL, k);
    float ggx2 = Schlick_GGX(NdotV, k);
    
    return ggx1 * ggx2;
}

//----------------------------------
// ����IBL�����䲿��
// �Է��߰�����в�����ƽ��
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
        // ���߿ռ������
            float3 tangentSample = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
        // �任������ռ�
            float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;

            irradiance += gCubeMap.Sample(gsamLinearWrap, sampleVec).rgb * cos(theta) * sin(theta);
            nrSamples++;
        }
    }
    irradiance = PI * irradiance * (1.0 / float(nrSamples));
    
    return irradiance;
}


//------------------------------------------------------
//  ���㾵�淴�䲿�ֵ�BRDF��
//  ��ʽ��F0 * |BRDF(1 - k) * NdotL + |BRDF * k * NdotL
//  ע : |������ַ���
//  ���� k = a * a * a * a * a,  a = (1 - NdotV)
//  ������ʽ��Ϊ F0 * A + B
//  A = |BRDF(1 - k) * NdotL,  B = |BRDF * k * NdotL
//  ��Ҫ����ľ���A��B
//-------------------------------------------------------

//  1. ��ȡ�Ͳ�������
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

    // �����굽�ѿ�������
    float3 H;
    H.x = cos(phi) * sinTheta;
    H.y = sin(phi) * sinTheta;
    H.z = cosTheta;

    // ���������������߿ռ�任������ռ�
    float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 tangent = normalize(cross(up, N));
    float3 bitangent = cross(N, tangent);

    float3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
    return normalize(sampleVec);
}


float2 IntegrateBRDF(float NdotV, float roughness)
{
    // ��NdotV��С(λ�ڱ�Ե,ֵ�ӽ�0)��ܴ�(λ��������,ֵΪ1)ʱ, �õ��Ľ����ܰ�
    // Ϊ�����������, ����������[0.2, 0.99]
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
        // ��ȡ�Ͳ�������
        float2 Xi = Hammersley(i, SAMPLE_COUNT);
        // GGX��Ҫ�Բ���, ���ݴֲڶ�, ���߷ֲ��������ɲ�������
        float3 H = ImportanceSampleGGX(Xi, N, roughness);
        // 2 * LdotN * N - L�� ���㷴�������Ĺ�ʽ
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



