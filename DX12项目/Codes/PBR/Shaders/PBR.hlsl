#include "Common.hlsl"

struct VertexIn
{
	float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
	float2 TexC    : TEXCOORD;
	float3 TangentU : TANGENT;
};

struct VertexOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
	float3 TangentW : TANGENT;
	float2 TexC    : TEXCOORD;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout = (VertexOut)0.0f;

	// ��ȡ����
	MaterialData matData = gMaterialData[gMaterialIndex];
	
    // �任������ռ�
    float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);
    vout.PosW = posW.xyz;

    vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);
	
	vout.TangentW = mul(vin.TangentU, (float3x3)gWorld);

    // �任����μ��ÿռ�
    vout.PosH = mul(posW, gViewProj);
	
	// ����ı任
	float4 texC = mul(float4(vin.TexC, 0.0f, 1.0f), gTexTransform);
	vout.TexC = mul(texC, matData.MatTransform).xy;
	
    return vout;
}


float4 PS(VertexOut pin) : SV_Target
{	
	//-------------------------
	// 0. ���ռ���ǰ��׼������
	//-------------------------
	MaterialData matData = gMaterialData[gMaterialIndex];
	float4 diffuseAlbedo = matData.DiffuseAlbedo;
	float3 fresnelR0 = matData.FresnelR0;
	float  roughness = matData.Roughness;
	uint diffuseMapIndex = matData.DiffuseMapIndex;
	uint normalMapIndex = matData.NormalMapIndex;
    float metallic = matData.metallic;
	
	// �Է��߲�ֵ���ܻ�ʹ��ʧȥ��λ����, ����ٴι�һ��.
    pin.NormalW = normalize(pin.NormalW);
	
	// ���߿ռ�任������ռ�
	float4 normalMapSample = gTextureMaps[normalMapIndex].Sample(gsamAnisotropicWrap, pin.TexC);
	float3 NormalW = NormalSampleToWorldSpace(normalMapSample.rgb, pin.NormalW, pin.TangentW);

	// ��ȡ��ͼ��ɫ
    diffuseAlbedo *= gTextureMaps[diffuseMapIndex].Sample(gsamAnisotropicWrap, pin.TexC);

    // �۲췽��
    float3 viewDir = normalize(gEyePosW - pin.PosW);
	// ��Դ����, ����ֻ����һ�������
    float3 lightDir = -gLights[0].Direction;
	// ��ǿ��, Ҫ�ǵ��Դ�Ļ���Ҫ����������˥��
    float3 lightRadiance = gLights[0].Strength;
	// �������
    float3 halfVec = normalize(viewDir + lightDir);
	// ������ͼ��Aͨ���洢�Ź����, �ɴ�������ϸ�Ŀ��ƴֲڶ�
    roughness *= normalMapSample.a;
	
	
	//----------------------------------------------------------------
	// 1. ����ֱ�ӹ��ղ��ֵļ���
	//	PBR��ʽ : (������ + ���淴��) * Light * LdotN
	//	������ = kd * c / PI, ���� kd = (1 - ks)(1 - ������)
	//	���淴�� = DGF / (4 * VdotN * LdotN)
	//----------------------------------------------------------------
	
	// 1.1 ֱ�ӹ⾵�淴�����	
    float NdotL = max(dot(NormalW, lightDir), 0.0f);
    float NdotV = max(dot(NormalW, viewDir), 0.0f);
    float NdotH = max(dot(NormalW, halfVec), 0.0f);
    float VdotH = max(dot(viewDir, halfVec), 0.0f);
    fresnelR0 = lerp(fresnelR0, diffuseAlbedo.rgb, metallic); // �ɽ����ȶԷ�����ϵ����ֵ
    float3 F = F_Schlick(fresnelR0, VdotH); 
    float D = D_GGX(NdotH, roughness);
    float G = G_Smith(NdotL, NdotV, roughness);
	
    float3 specular = (D * G * F) / (4.0f * NdotV * NdotL + 0.01);	
	
	// 1.2 ֱ�ӹ������䲿�ּ���(������������ģ��)	
    float3 kd = (1 - F) * (1 - metallic);
    float3 diffuse = kd * diffuseAlbedo.rgb / PI;	
	// ��ѡ�ĵ�ʿ��������ģ��
#if Disney
    float FD90 = 0.5f + 2 * HdotV * HdotV * roughness;
    float FdV = 1 + (FD90 - 1) * pow(1 - NdotV, 5);
    float FdL = 1 + (FD90 - 1) * pow(1 - NdotL, 5);
    kd = FdV * FdL * (1 - metallic);
    diffuse = diffuseAlbedo.rgb * ((1 / PI) * kd);
#endif
	
	//1.3 ֱ�ӹⲿ�ֵ����ս��
    float3 litColor = (diffuse + specular) * lightRadiance * NdotL;

	
	//---------------------------------
	// 2. ��ӹⲿ�ֵļ��㣨IBLʵ�֣�
	//---------------------------------
	
	// 2.1 ��ӹ�������
    float3 iblIrradiance = IBLDiffuseIrradiance(NormalW); // �ڷ��߰�����Ȳ�����ƽ��, �Դ���Ϊ�������Irradiance
    float3 iblF = F_Schlick(fresnelR0, NdotV);  // ������û������������, ������NdotV������(��ᵼ�½�ǿ�ı�Ե��)
    float3 iblKd = (1 - iblF) * (1 - metallic);
    float3 iblDiffuse = iblKd * iblIrradiance * diffuseAlbedo.rgb;
	
	// 2.2 ��ӹ⾵�淴��
    float3 r = reflect(-viewDir, NormalW);
    float maxLod = 8.0f; // ��������ͼ���mipmap�ȼ�
    float3 iblSpecularIrradiance = gCubeMap.SampleLevel(gsamLinearClamp, r, roughness * maxLod).rgb; 
	// ��Ԥ�����BRDF����ֱ�Ӳ���
    float2 lut = gBRDFLUT.Sample(gsamLinearClamp, float2(NdotV, roughness)).rg;
    float3 iblSpecular = iblSpecularIrradiance * (iblF * lut.x + lut.y);
	
	
	// 2.3 ��ӹⲿ�����ս��
    litColor += iblDiffuse + iblSpecular;
	
		
	//----------------------------------------------------------
	//	3. �������
	//	��Ҫ����������, һ��ɫ��ӳ��, ����٤�����
	//  �������õĻ�����ͼ����HDR��ʽ, ��ɫ��ӳ��Ļ������ܰ�
	//----------------------------------------------------------
	
	// ɫ��ӳ��, HDRӳ�䵽LDR
    // litColor = litColor / (litColor + 1.0f);
	
	// ٤�����
    litColor = pow(litColor, 1.0 / 2.2);

    return float4(litColor, diffuseAlbedo.a);
}


