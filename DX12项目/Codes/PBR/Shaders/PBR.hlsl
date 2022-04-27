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

	// 获取材质
	MaterialData matData = gMaterialData[gMaterialIndex];
	
    // 变换到世界空间
    float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);
    vout.PosW = posW.xyz;

    vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);
	
	vout.TangentW = mul(vin.TangentU, (float3x3)gWorld);

    // 变换到齐次剪裁空间
    vout.PosH = mul(posW, gViewProj);
	
	// 纹理的变换
	float4 texC = mul(float4(vin.TexC, 0.0f, 1.0f), gTexTransform);
	vout.TexC = mul(texC, matData.MatTransform).xy;
	
    return vout;
}


float4 PS(VertexOut pin) : SV_Target
{	
	//-------------------------
	// 0. 光照计算前的准备工作
	//-------------------------
	MaterialData matData = gMaterialData[gMaterialIndex];
	float4 diffuseAlbedo = matData.DiffuseAlbedo;
	float3 fresnelR0 = matData.FresnelR0;
	float  roughness = matData.Roughness;
	uint diffuseMapIndex = matData.DiffuseMapIndex;
	uint normalMapIndex = matData.NormalMapIndex;
    float metallic = matData.metallic;
	
	// 对法线插值可能会使其失去单位长度, 因此再次归一化.
    pin.NormalW = normalize(pin.NormalW);
	
	// 切线空间变换到世界空间
	float4 normalMapSample = gTextureMaps[normalMapIndex].Sample(gsamAnisotropicWrap, pin.TexC);
	float3 NormalW = NormalSampleToWorldSpace(normalMapSample.rgb, pin.NormalW, pin.TangentW);

	// 获取贴图颜色
    diffuseAlbedo *= gTextureMaps[diffuseMapIndex].Sample(gsamAnisotropicWrap, pin.TexC);

    // 观察方向
    float3 viewDir = normalize(gEyePosW - pin.PosW);
	// 光源方向, 这里只计算一个方向光
    float3 lightDir = -gLights[0].Direction;
	// 光强度, 要是点光源的话还要再算个距离的衰减
    float3 lightRadiance = gLights[0].Strength;
	// 半程向量
    float3 halfVec = normalize(viewDir + lightDir);
	// 法线贴图的A通道存储着光泽度, 由此来更精细的控制粗糙度
    roughness *= normalMapSample.a;
	
	
	//----------------------------------------------------------------
	// 1. 进行直接光照部分的计算
	//	PBR公式 : (漫反射 + 镜面反射) * Light * LdotN
	//	漫反射 = kd * c / PI, 其中 kd = (1 - ks)(1 - 金属度)
	//	镜面反射 = DGF / (4 * VdotN * LdotN)
	//----------------------------------------------------------------
	
	// 1.1 直接光镜面反射计算	
    float NdotL = max(dot(NormalW, lightDir), 0.0f);
    float NdotV = max(dot(NormalW, viewDir), 0.0f);
    float NdotH = max(dot(NormalW, halfVec), 0.0f);
    float VdotH = max(dot(viewDir, halfVec), 0.0f);
    fresnelR0 = lerp(fresnelR0, diffuseAlbedo.rgb, metallic); // 由金属度对菲涅尔系数插值
    float3 F = F_Schlick(fresnelR0, VdotH); 
    float D = D_GGX(NdotH, roughness);
    float G = G_Smith(NdotL, NdotV, roughness);
	
    float3 specular = (D * G * F) / (4.0f * NdotV * NdotL + 0.01);	
	
	// 1.2 直接光漫反射部分计算(兰伯特漫反射模型)	
    float3 kd = (1 - F) * (1 - metallic);
    float3 diffuse = kd * diffuseAlbedo.rgb / PI;	
	// 可选的迪士尼漫反射模型
#if Disney
    float FD90 = 0.5f + 2 * HdotV * HdotV * roughness;
    float FdV = 1 + (FD90 - 1) * pow(1 - NdotV, 5);
    float FdL = 1 + (FD90 - 1) * pow(1 - NdotL, 5);
    kd = FdV * FdL * (1 - metallic);
    diffuse = diffuseAlbedo.rgb * ((1 / PI) * kd);
#endif
	
	//1.3 直接光部分的最终结果
    float3 litColor = (diffuse + specular) * lightRadiance * NdotL;

	
	//---------------------------------
	// 2. 间接光部分的计算（IBL实现）
	//---------------------------------
	
	// 2.1 间接光漫反射
    float3 iblIrradiance = IBLDiffuseIrradiance(NormalW); // 在法线半球均匀采样求平均, 以此作为环境光的Irradiance
    float3 iblF = F_Schlick(fresnelR0, NdotV);  // 环境光没法计算半程向量, 所以用NdotV来代替(这会导致较强的边缘光)
    float3 iblKd = (1 - iblF) * (1 - metallic);
    float3 iblDiffuse = iblKd * iblIrradiance * diffuseAlbedo.rgb;
	
	// 2.2 间接光镜面反射
    float3 r = reflect(-viewDir, NormalW);
    float maxLod = 8.0f; // 立方体贴图最大mipmap等级
    float3 iblSpecularIrradiance = gCubeMap.SampleLevel(gsamLinearClamp, r, roughness * maxLod).rgb; 
	// 对预计算的BRDF部分直接采样
    float2 lut = gBRDFLUT.Sample(gsamLinearClamp, float2(NdotV, roughness)).rg;
    float3 iblSpecular = iblSpecularIrradiance * (iblF * lut.x + lut.y);
	
	
	// 2.3 间接光部分最终结果
    litColor += iblDiffuse + iblSpecular;
	
		
	//----------------------------------------------------------
	//	3. 最终输出
	//	需要做的有两步, 一是色调映射, 二是伽马矫正
	//  但这里用的环境贴图不是HDR格式, 做色调映射的话画面会很暗
	//----------------------------------------------------------
	
	// 色调映射, HDR映射到LDR
    // litColor = litColor / (litColor + 1.0f);
	
	// 伽马矫正
    litColor = pow(litColor, 1.0 / 2.2);

    return float4(litColor, diffuseAlbedo.a);
}


