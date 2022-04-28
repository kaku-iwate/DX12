
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

    // 光源相关
    Light gLights[MaxLights];
};

//---------------------------------------------------------------------------------------
// 将法线从切线空间变换到世界空间
//---------------------------------------------------------------------------------------
float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float3 tangentW)
{
	// 将法线从[0,1]变换到[-1,1]
	float3 normalT = 2.0f*normalMapSample - 1.0f;

	// 这里构建切线空间三轴在世界空间的位置
    // 用于坐标系变换
	float3 N = unitNormalW;
	float3 T = normalize(tangentW - dot(tangentW, N)*N);
	float3 B = cross(N, T);

	float3x3 TBN = float3x3(T, B, N);

	// 变换到世界空间
	float3 bumpedNormalW = mul(normalT, TBN);

	return bumpedNormalW;
}


// 生成0到1的随机数
float rand_01(in float2 uv)
{
    float2 noise = (frac(sin(dot(uv, float2(12.9898, 78.233) * 2.0)) * 43758.5453));
    return abs(noise.x + noise.y) * 0.5;
}


#define SAMPLES_NUM 16


// 泊松分布
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
    
    // 搜索范围大小固定下来
    float searchWidth = 7;
    
    // 计算遮挡物的平均深度
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
    // 如果是用透视投影的话这里需要做下齐次除法
    //shadowPosH.xyz /= shadowPosH.w;
    
    float2 uv = shadowPosH.xy;

    // 着色点在光源相机NDC空间的z值
    float depth = shadowPosH.z;
    
    uint width, height, numMips;
    gShadowMap.GetDimensions(0, width, height, numMips);

    // 贴图尺寸
    float dx = 1.0f / (float) width;
    float dy = 1.0f / (float) height;
    
    // 获取周围遮挡点的平均深度
    float blockerDepth = findBlocker(uv, float2(dx, dy), depth);
    
    // 如果检测不到遮挡物证明没有阴影, 直接返回
    if(blockerDepth == 0)
        return 1.0f;
    
    // 计算半影大小, 在这里将光源大小简化为1
    // 同时这里的深度值都是NDC空间的
    // 因为正交投影都是线性变换, 所以可以直接用
    // 但在透视投影中, 深度值并非线性, 因此需要变换到光源相机的观察空间或世界空间来计算
    float wPenumbra = (depth - blockerDepth) / blockerDepth;
    
    // 计算pcss半径
    // 将半径限制到[2,10]范围
    uint range = clamp(2, 10, 15 * wPenumbra);
    
    
    // 阴影因子
    float percentLit = 0.0f;
    
    //  不管多大的采样半径, 都只使用相同的泊松分布来采样16个点, 这会造成阴影分层
    //  特别是半径较大时, 问题更为明显
    //  可以对对泊松分布进行一个随机的旋转来改善, 但这样会导致阴影有噪点
    //  简单起见...直接限制最大半径来减轻阴影分层
    [unroll]
    for (uint i = 0; i < SAMPLES_NUM; i++)
    {
        float2 offset = float2(dx, dy) * poissonDisk[i] * range;
        percentLit += gShadowMap.SampleCmpLevelZero(gsamShadow, shadowPosH.xy + offset, depth).x;
    }
    percentLit /= SAMPLES_NUM;
    

    return percentLit;
}

