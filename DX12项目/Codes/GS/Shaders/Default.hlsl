//***************************************************************************************
// Default.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Default shader, currently supports lighting.
//***************************************************************************************

// Defaults for number of lights.
#ifndef NUM_DIR_LIGHTS
    #define NUM_DIR_LIGHTS 3
#endif

#ifndef NUM_POINT_LIGHTS
    #define NUM_POINT_LIGHTS 0
#endif

#ifndef NUM_SPOT_LIGHTS
    #define NUM_SPOT_LIGHTS 0
#endif

// Include structures and functions for lighting.
#include "LightingUtil.hlsl"

Texture2D    gDiffuseMap : register(t0);


SamplerState gsamPointWrap        : register(s0);
SamplerState gsamPointClamp       : register(s1);
SamplerState gsamLinearWrap       : register(s2);
SamplerState gsamLinearClamp      : register(s3);
SamplerState gsamAnisotropicWrap  : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);

// Constant data that varies per frame.
cbuffer cbPerObject : register(b0)
{
    float4x4 gWorld;
	float4x4 gTexTransform;
};

// Constant data that varies per material.
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

	float4 gFogColor;
	float gFogStart;
	float gFogRange;
    float gTessNum;
    float pad0;

    // Indices [0, NUM_DIR_LIGHTS) are directional lights;
    // indices [NUM_DIR_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHTS) are point lights;
    // indices [NUM_DIR_LIGHTS+NUM_POINT_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHT+NUM_SPOT_LIGHTS)
    // are spot lights for a maximum of MaxLights per object.
    Light gLights[MaxLights];
};

cbuffer cbMaterial : register(b2)
{
	float4   gDiffuseAlbedo;
    float3   gFresnelR0;
    float    gRoughness;
	float4x4 gMatTransform;
};

struct VertexIO
{
	float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
	float2 TexC    : TEXCOORD;
};

struct GeoOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
	float2 TexC    : TEXCOORD;
};

VertexIO VS(VertexIO vin)
{
	VertexIO vout = (VertexIO)0.0f;
    
    vout.PosL = vin.PosL;
    
    vout.NormalL = vin.NormalL;
	
	// Output vertex attributes for interpolation across triangle.
	float4 texC = mul(float4(vin.TexC, 0.0f, 1.0f), gTexTransform);
	vout.TexC = mul(texC, gMatTransform).xy;

    return vout;
}

void subdivide(VertexIO iVertex[3], out VertexIO oVertex[6])
{
    VertexIO m[3];
    
    // 计算新顶点位置
    m[0].PosL = 0.5 * (iVertex[0].PosL + iVertex[1].PosL);
    m[1].PosL = 0.5 * (iVertex[1].PosL + iVertex[2].PosL);
    m[2].PosL = 0.5 * (iVertex[2].PosL + iVertex[0].PosL);
    
    // 投影至单位球面
    m[0].PosL = normalize(m[0].PosL);
    m[1].PosL = normalize(m[1].PosL);
    m[2].PosL = normalize(m[2].PosL);
    
    ////计算法线
    m[0].NormalL = m[0].PosL;
    m[1].NormalL = m[1].PosL;
    m[2].NormalL = m[2].PosL;
    
    //纹理坐标
    m[0].TexC = 0.5 * (iVertex[0].TexC + iVertex[1].TexC);
    m[1].TexC = 0.5 * (iVertex[1].TexC + iVertex[2].TexC);
    m[2].TexC = 0.5 * (iVertex[2].TexC + iVertex[0].TexC);
    
    oVertex[0] = iVertex[0];
    oVertex[1] = m[0];
    oVertex[2] = m[2];
    oVertex[3] = m[1];
    oVertex[4] = iVertex[2];
    oVertex[5] = iVertex[1];
}

void outputSubdivsion(VertexIO v[6], inout TriangleStream<GeoOut> triStream)
{
    GeoOut gout[6];
    
    [unroll]
    for (int i = 0; i < 6; i++)
    {
        // 顶点变换到世界空间
        gout[i].PosW = mul(float4(v[i].PosL, 1.0f), gWorld).xyz;
        gout[i].NormalW = mul(v[i].NormalL, (float3x3)gWorld);
        
        // 顶点变换到齐次空间
        gout[i].PosH = mul(float4(gout[i].PosW, 1.0f), gViewProj);
        gout[i].TexC = v[i].TexC;
    }
    
    [unroll]
    for (int j = 0; j < 5; j++)
    {
        triStream.Append(gout[j]);
    }
    triStream.RestartStrip();
    
    triStream.Append(gout[1]);
    triStream.Append(gout[5]);
    triStream.Append(gout[3]);
}

[maxvertexcount(32)]
void GS(triangle VertexIO gin[3], inout TriangleStream<GeoOut> triStream)
{
    if(gTessNum == 0.0f)  // 不进行曲面细分
    {
        GeoOut gout;
        [unroll]
        for (int i = 0; i < 3; i++)
        {
        // 顶点变换到世界空间
            gout.PosW = mul(float4(gin[i].PosL, 1.0f), gWorld).xyz;
            gout.NormalW = gin[i].NormalL;
        
        // 顶点变换到齐次空间
            gout.PosH = mul(float4(gout.PosW, 1.0f), gViewProj);
            gout.TexC = gin[i].TexC;
            triStream.Append(gout);
        }
    }
    else
    {
        VertexIO v[6];
        subdivide(gin, v);
        if(gTessNum == 1.0f)  // 一次曲面细分
        {
            outputSubdivsion(v, triStream);
        }
        else if(gTessNum == 2.0f) // 两次曲面细分
        {
            VertexIO subV[6];

            VertexIO subTri1[3];  // 需要把经一次细分后拆出的四个三角形再次作为输入进行细分
            [unroll]
            for (int i = 0; i < 3; i+=2)
            {
                subTri1[0] = v[i];
                subTri1[1] = v[i+1];
                subTri1[2] = v[i+2];
                subdivide(subTri1, subV);
                outputSubdivsion(subV, triStream);
                triStream.RestartStrip();
            }
            
            VertexIO subTri2[3] = { v[1], v[5], v[3] };
            subdivide(subTri2, subV);
            outputSubdivsion(subV, triStream);
            
            triStream.RestartStrip();  // 在不同三角形间分割三角形条带是必须的
            
            VertexIO subTri3[3] = { v[1], v[3], v[2] };
            subdivide(subTri3, subV);
            outputSubdivsion(subV, triStream);
        }
    }

}

float4 PS(GeoOut pin) : SV_Target
{
    float4 diffuseAlbedo = gDiffuseMap.Sample(gsamAnisotropicWrap, pin.TexC) * gDiffuseAlbedo;
	
#ifdef ALPHA_TEST
	// Discard pixel if texture alpha < 0.1.  We do this test as soon 
	// as possible in the shader so that we can potentially exit the
	// shader early, thereby skipping the rest of the shader code.
	clip(diffuseAlbedo.a - 0.1f);
#endif

    // Interpolating normal can unnormalize it, so renormalize it.
    pin.NormalW = normalize(pin.NormalW);

    // Vector from point being lit to eye. 
	float3 toEyeW = gEyePosW - pin.PosW;
	float distToEye = length(toEyeW);
	toEyeW /= distToEye; // normalize

    // Light terms.
    float4 ambient = gAmbientLight*diffuseAlbedo;

    const float shininess = 1.0f - gRoughness;
    Material mat = { diffuseAlbedo, gFresnelR0, shininess };
    float3 shadowFactor = 1.0f;
    float4 directLight = ComputeLighting(gLights, mat, pin.PosW,
        pin.NormalW, toEyeW, shadowFactor);

    float4 litColor = ambient + directLight;

#ifdef FOG
	float fogAmount = saturate((distToEye - gFogStart) / gFogRange);
	litColor = lerp(litColor, gFogColor, fogAmount);
#endif

    // Common convention to take alpha from diffuse albedo.
    litColor.a = diffuseAlbedo.a;

    return litColor;
}


