//***************************************************************************************
// Default.hlsl by Frank Luna (C) 2015 All Rights Reserved.
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

// Include common HLSL code.
#include "Common.hlsl"

struct VertexIO
{
	float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
	float2 TexC    : TEXCOORD;
	float3 TangentU : TANGENT;
};

struct DSOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
	float3 TangentW : TANGENT;
};

// 顶点着色器只传递下数据, mvp变换等交给域着色器来做
VertexIO VS(VertexIO vin)
{
    return vin;
}


// 三角形的细分等级
struct PatchTess
{
    float EdgeTess[3] : SV_TessFactor;
    float InsideTess : SV_InsideTessFactor;
};

PatchTess ConstantHS(InputPatch<VertexIO, 3> patch, uint patchID : SV_PrimitiveID)
{
    PatchTess pt;
	
    // 这里可以根据物体和摄像机距离动态的变换细分等级
    
    pt.EdgeTess[0] = 4;
    pt.EdgeTess[1] = 4;
    pt.EdgeTess[2] = 4;
	
    pt.InsideTess = 4;
	
    return pt;
}



[domain("tri")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("ConstantHS")]
[maxtessfactor(16.0f)]
VertexIO HS(InputPatch<VertexIO, 3> controlPoint, uint i : SV_OutputControlPointID, uint patchId : SV_PrimitiveID)
{
	// 控制点外壳着色器只传递数据, 不做修改
    return controlPoint[i];
}


// 每当镶嵌器创建新顶点时, 都会调用域着色器.
// 可以把域着色器当作这些新顶点的"顶点着色器".
[domain("tri")]
DSOut DS(PatchTess patchTess, float3 bary : SV_DomainLocation, const OutputPatch<VertexIO, 3> tri)
{
    VertexIO ver;
	
    MaterialData matData = gMaterialData[gMaterialIndex];
    uint normalMapIndex1 = matData.NormalMapIndex;
    uint normalMapIndex2 = matData.DiffuseMapIndex;
	
	// 根据重心坐标计算新顶点位置等属性
    ver.PosL = bary.x * tri[0].PosL + bary.y * tri[1].PosL + bary.z * tri[2].PosL;
    ver.NormalL = bary.x * tri[0].NormalL + bary.y * tri[1].NormalL + bary.z * tri[2].NormalL;
    ver.TangentU = bary.x * tri[0].TangentU + bary.y * tri[1].TangentU + bary.z * tri[2].TangentU;
    ver.TexC = bary.x * tri[0].TexC + bary.y * tri[1].TexC + bary.z * tri[2].TexC;
	
    ver.NormalL = normalize(ver.NormalL);
    
    // 变换纹理坐标
    float4 tex = mul(float4(ver.TexC, 0.0f, 1.0f), gTexTransform);
    float2 Tex1 = tex.xy;
    float2 Tex2 = tex.xy;
    Tex1.x += matData.MatTransform[3][0];
    Tex2.y += matData.MatTransform[3][1];

    
    // 获取法线贴图的值, 这里对贴图采样只能使用 SampleLevel 函数
    float4 Sample1 = gTextureMaps[normalMapIndex1].SampleLevel(gsamLinearWrap, Tex1, 0.0f);
    float4 Sample2 = gTextureMaps[normalMapIndex2].SampleLevel(gsamLinearWrap, Tex2, 0.0f);
    
    
    // 根据位移贴图, 在模型空间对其顶点偏移
    float d = Sample1.a;
    d += 0.5 * Sample2.a;
    ver.PosL += d * ver.NormalL;
    
    
    // 进行mvp等计算
    DSOut dout;
    
    // 变换到世界空间
    float4 posW = mul(float4(ver.PosL, 1.0f), gWorld);
    dout.PosW = posW.xyz;

    dout.TangentW = mul(ver.TangentU, (float3x3) gWorld);
    dout.NormalW = mul(ver.NormalL, (float3x3) gWorld);
    
    // 利用上面采样得到的值直接计算世界空间法线, 避免在像素着色器中重复采样
    float3 bumpedNormalW1 = NormalSampleToWorldSpace(Sample1.rgb, dout.NormalW, dout.TangentW);
    float3 bumpedNormalW2 = NormalSampleToWorldSpace(Sample2.rgb, dout.NormalW, dout.TangentW);

    float3 bumpedNormalW = normalize(bumpedNormalW1 + 0.5 * bumpedNormalW2);
    dout.NormalW = bumpedNormalW;

    // VP矩阵,变换到剪裁空间
    dout.PosH = mul(posW, gViewProj);
	
    return dout;
}



float4 PS(DSOut pin) : SV_Target
{
	MaterialData matData = gMaterialData[gMaterialIndex];
	float4 diffuseAlbedo = matData.DiffuseAlbedo;
	float3 fresnelR0 = matData.FresnelR0;
	float  roughness = matData.Roughness;
	uint normalMapIndex2 = matData.DiffuseMapIndex;
	uint normalMapIndex1 = matData.NormalMapIndex;
	
	// 对法线插值可能会使其失去单位长度, 因此再次归一化.
    pin.NormalW = normalize(pin.NormalW);
	

    // 着色点到眼睛的向量
    float3 toEyeW = normalize(gEyePosW - pin.PosW);
	

    // 环境光
    float4 ambient = gAmbientLight * diffuseAlbedo;

    const float shininess = (1.0f - roughness);
    Material mat = { diffuseAlbedo, fresnelR0, shininess };
    float3 shadowFactor = 1.0f;
    float4 directLight = ComputeLighting(gLights, mat, pin.PosW,
        pin.NormalW, toEyeW, shadowFactor);
    
    //return directLight;

    float4 litColor = ambient + directLight;

	// 利用法线贴图的法线来计算镜面反射.
    float3 r = reflect(-toEyeW, pin.NormalW);
	float4 reflectionColor = gCubeMap.Sample(gsamLinearWrap, r);
    float3 fresnelFactor = SchlickFresnel(fresnelR0, pin.NormalW, r);
    litColor.rgb += fresnelFactor * shininess * reflectionColor.rgb;
	
    litColor.a = diffuseAlbedo.a;

    return litColor;
}


