
#ifndef NUM_DIR_LIGHTS
    #define NUM_DIR_LIGHTS 1
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
	float4   DiffuseAlbedo;
	float3   FresnelR0;
	float    Roughness;
	float4x4 MatTransform;
	uint     DiffuseMapIndex;
	uint     NormalMapIndex;
	uint     MatPad1;
	uint     MatPad2;
};

TextureCube gCubeMap : register(t0);
Texture2D gShadowMap : register(t1);

// An array of textures, which is only supported in shader model 5.1+.  Unlike Texture2DArray, the textures
// in this array can be different sizes and formats, making it more flexible than texture arrays.
Texture2D gTextureMaps[10] : register(t2);

// Put in space1, so the texture array does not overlap with these resources.  
// The texture array will occupy registers t0, t1, ..., t3 in space0. 
StructuredBuffer<MaterialData> gMaterialData : register(t0, space1);


SamplerState gsamPointWrap        : register(s0);
SamplerState gsamPointClamp       : register(s1);
SamplerState gsamLinearWrap       : register(s2);
SamplerState gsamLinearClamp      : register(s3);
SamplerState gsamAnisotropicWrap  : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);
SamplerComparisonState gsamShadow : register(s6);

// Constant data that varies per frame.
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
    float4x4 gShadowTransform;
    float3 gEyePosW;
    float cbPerObjectPad1;
    float2 gRenderTargetSize;
    float2 gInvRenderTargetSize;
    float gNearZ;
    float gFarZ;
    float gTotalTime;
    float gDeltaTime;
    float4 gAmbientLight;

    // ��Դ���
    Light gLights[MaxLights];
};

//---------------------------------------------------------------------------------------
// �����ߴ����߿ռ�任������ռ�
//---------------------------------------------------------------------------------------
float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float3 tangentW)
{
	// �����ߴ�[0,1]�任��[-1,1]
	float3 normalT = 2.0f*normalMapSample - 1.0f;

	// ���ﹹ�����߿ռ�����������ռ��λ��
    // ��������ϵ�任
	float3 N = unitNormalW;
	float3 T = normalize(tangentW - dot(tangentW, N)*N);
	float3 B = cross(N, T);

	float3x3 TBN = float3x3(T, B, N);

	// �任������ռ�
	float3 bumpedNormalW = mul(normalT, TBN);

	return bumpedNormalW;
}


// ����0��1�������
float rand_01(in float2 uv)
{
    float2 noise = (frac(sin(dot(uv, float2(12.9898, 78.233) * 2.0)) * 43758.5453));
    return abs(noise.x + noise.y) * 0.5;
}


#define SAMPLES_NUM 16


// ���ɷֲ�
static const float2 poissonDisk[16] =
{
    float2(-0.94201624, -0.39906216),
 float2(0.94558609, -0.76890725),
 float2(-0.094184101, -0.92938870),
 float2(0.34495938, 0.29387760),
 float2(-0.91588581, 0.45771432),
 float2(-0.81544232, -0.87912464),
 float2(-0.38277543, 0.27676845),
 float2(0.97484398, 0.75648379),
 float2(0.44323325, -0.97511554),
 float2(0.53742981, -0.47373420),
 float2(-0.26496911, -0.41893023),
 float2(0.79197514, 0.19090188),
 float2(-0.24188840, 0.99706507),
 float2(-0.81409955, 0.91437590),
 float2(0.19984126, 0.78641367),
 float2(0.14383161, -0.14100790)
};


float findBlocker(float2 uv, float2 offset, float d)
{
    float depth = 0.0f;
    float count = 0.0f;
    
    // ������Χ��С�̶�����
    float searchWidth = 7;
    
    // �����ڵ����ƽ�����
    //for (int i = 0; i < SAMPLES_NUM; i++)
    //{
        
    //    float sample = gShadowMap.Sample(gsamPointClamp, uv + poissonDisk[i] * searchWidth * offset).x;
    //    if (sample < d)
    //    {
    //        depth += sample;
    //        count++;
    //    }
    //}
    
    for (int j = -7; j < 7;j++)
    {
        for (int k = -7; k < 7;k++)
        {
            float2 sampleUV = uv + float2(offset.x * k, offset.y * j);
            float sample = gShadowMap.Sample(gsamPointClamp, sampleUV).x;
            if (sample < d)
            {
                depth += sample;
                count++;
            }
        }

    }
    
        if (count == 0.0f)
            return 0.0f;

    return depth / count;
}

float PCSS(float4 shadowPosH)
{
    // �������͸��ͶӰ�Ļ�������Ҫ������γ���
    //shadowPosH.xyz /= shadowPosH.w;
    
    float2 uv = shadowPosH.xy;

    // ��ɫ���ڹ�Դ���NDC�ռ��zֵ
    float depth = shadowPosH.z;
    
    uint width, height, numMips;
    gShadowMap.GetDimensions(0, width, height, numMips);

    // ��ͼ�ߴ�
    float dx = 1.0f / (float) width;
    float dy = 1.0f / (float) height;
    
    // ��ȡ��Χ�ڵ����ƽ�����
    float blockerDepth = findBlocker(uv, float2(dx, dy), depth);
    
    // �����ⲻ���ڵ���֤��û����Ӱ, ֱ�ӷ���
    if(blockerDepth == 0)
        return 1.0f;
    
    // �����Ӱ��С, �����ｫ��Դ��С��Ϊ1
    // ͬʱ��������ֵ����NDC�ռ��
    // ��Ϊ����ͶӰ�������Ա任, ���Կ���ֱ����
    // ����͸��ͶӰ��, ���ֵ��������, �����Ҫ�任����Դ����Ĺ۲�ռ������ռ�������
    float wPenumbra = (depth - blockerDepth) / blockerDepth;
    
    // ����pcss�뾶
    // ���뾶���Ƶ�[2,10]��Χ
    uint range = clamp(2, 10, 15 * wPenumbra);
    
    
    // ��Ӱ����
    float percentLit = 0.0f;
    
    //  ���ܶ��Ĳ����뾶, ��ֻʹ����ͬ�Ĳ��ɷֲ�������16����, ��������Ӱ�ֲ�
    //  �ر��ǰ뾶�ϴ�ʱ, �����Ϊ����
    //  ���ԶԶԲ��ɷֲ�����һ���������ת������, �������ᵼ����Ӱ�����
    //  �����...ֱ���������뾶��������Ӱ�ֲ�
    [unroll]
    for (uint i = 0; i < SAMPLES_NUM; i++)
    {
        float2 offset = float2(dx, dy) * poissonDisk[i] * range;
        percentLit += gShadowMap.SampleCmpLevelZero(gsamShadow, shadowPosH.xy + offset, depth).x;
    }
    percentLit /= SAMPLES_NUM;
    

    return percentLit;
}

