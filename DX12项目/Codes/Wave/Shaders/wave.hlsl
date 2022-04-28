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

// ������ɫ��ֻ����������, mvp�任�Ƚ�������ɫ������
VertexIO VS(VertexIO vin)
{
    return vin;
}


// �����ε�ϸ�ֵȼ�
struct PatchTess
{
    float EdgeTess[3] : SV_TessFactor;
    float InsideTess : SV_InsideTessFactor;
};

PatchTess ConstantHS(InputPatch<VertexIO, 3> patch, uint patchID : SV_PrimitiveID)
{
    PatchTess pt;
	
    // ������Ը����������������붯̬�ı任ϸ�ֵȼ�
    
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
	// ���Ƶ������ɫ��ֻ��������, �����޸�
    return controlPoint[i];
}


// ÿ����Ƕ�������¶���ʱ, �����������ɫ��.
// ���԰�����ɫ��������Щ�¶����"������ɫ��".
[domain("tri")]
DSOut DS(PatchTess patchTess, float3 bary : SV_DomainLocation, const OutputPatch<VertexIO, 3> tri)
{
    VertexIO ver;
	
    MaterialData matData = gMaterialData[gMaterialIndex];
    uint normalMapIndex1 = matData.NormalMapIndex;
    uint normalMapIndex2 = matData.DiffuseMapIndex;
	
	// ����������������¶���λ�õ�����
    ver.PosL = bary.x * tri[0].PosL + bary.y * tri[1].PosL + bary.z * tri[2].PosL;
    ver.NormalL = bary.x * tri[0].NormalL + bary.y * tri[1].NormalL + bary.z * tri[2].NormalL;
    ver.TangentU = bary.x * tri[0].TangentU + bary.y * tri[1].TangentU + bary.z * tri[2].TangentU;
    ver.TexC = bary.x * tri[0].TexC + bary.y * tri[1].TexC + bary.z * tri[2].TexC;
	
    ver.NormalL = normalize(ver.NormalL);
    
    // �任��������
    float4 tex = mul(float4(ver.TexC, 0.0f, 1.0f), gTexTransform);
    float2 Tex1 = tex.xy;
    float2 Tex2 = tex.xy;
    Tex1.x += matData.MatTransform[3][0];
    Tex2.y += matData.MatTransform[3][1];

    
    // ��ȡ������ͼ��ֵ, �������ͼ����ֻ��ʹ�� SampleLevel ����
    float4 Sample1 = gTextureMaps[normalMapIndex1].SampleLevel(gsamLinearWrap, Tex1, 0.0f);
    float4 Sample2 = gTextureMaps[normalMapIndex2].SampleLevel(gsamLinearWrap, Tex2, 0.0f);
    
    
    // ����λ����ͼ, ��ģ�Ϳռ���䶥��ƫ��
    float d = Sample1.a;
    d += 0.5 * Sample2.a;
    ver.PosL += d * ver.NormalL;
    
    
    // ����mvp�ȼ���
    DSOut dout;
    
    // �任������ռ�
    float4 posW = mul(float4(ver.PosL, 1.0f), gWorld);
    dout.PosW = posW.xyz;

    dout.TangentW = mul(ver.TangentU, (float3x3) gWorld);
    dout.NormalW = mul(ver.NormalL, (float3x3) gWorld);
    
    // ������������õ���ֱֵ�Ӽ�������ռ䷨��, ������������ɫ�����ظ�����
    float3 bumpedNormalW1 = NormalSampleToWorldSpace(Sample1.rgb, dout.NormalW, dout.TangentW);
    float3 bumpedNormalW2 = NormalSampleToWorldSpace(Sample2.rgb, dout.NormalW, dout.TangentW);

    float3 bumpedNormalW = normalize(bumpedNormalW1 + 0.5 * bumpedNormalW2);
    dout.NormalW = bumpedNormalW;

    // VP����,�任�����ÿռ�
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
	
	// �Է��߲�ֵ���ܻ�ʹ��ʧȥ��λ����, ����ٴι�һ��.
    pin.NormalW = normalize(pin.NormalW);
	

    // ��ɫ�㵽�۾�������
    float3 toEyeW = normalize(gEyePosW - pin.PosW);
	

    // ������
    float4 ambient = gAmbientLight * diffuseAlbedo;

    const float shininess = (1.0f - roughness);
    Material mat = { diffuseAlbedo, fresnelR0, shininess };
    float3 shadowFactor = 1.0f;
    float4 directLight = ComputeLighting(gLights, mat, pin.PosW,
        pin.NormalW, toEyeW, shadowFactor);
    
    //return directLight;

    float4 litColor = ambient + directLight;

	// ���÷�����ͼ�ķ��������㾵�淴��.
    float3 r = reflect(-toEyeW, pin.NormalW);
	float4 reflectionColor = gCubeMap.Sample(gsamLinearWrap, r);
    float3 fresnelFactor = SchlickFresnel(fresnelR0, pin.NormalW, r);
    litColor.rgb += fresnelFactor * shininess * reflectionColor.rgb;
	
    litColor.a = diffuseAlbedo.a;

    return litColor;
}


