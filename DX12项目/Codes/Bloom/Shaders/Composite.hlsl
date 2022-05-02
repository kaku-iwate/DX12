Texture2D gBaseMap : register(t0);
Texture2D gHighLightMap : register(t1);

SamplerState gsamPointWrap        : register(s0);
SamplerState gsamPointClamp       : register(s1);
SamplerState gsamLinearWrap       : register(s2);
SamplerState gsamLinearClamp      : register(s3);
SamplerState gsamAnisotropicWrap  : register(s4);
SamplerState gsamDepthMap : register(s5);

static const float2 gTexCoords[6] = 
{
	float2(0.0f, 1.0f),
	float2(0.0f, 0.0f),
	float2(1.0f, 0.0f),
	float2(0.0f, 1.0f),
	float2(1.0f, 0.0f),
	float2(1.0f, 1.0f)
};


struct VertexOut
{
	float4 PosH    : SV_POSITION;
	float2 TexC    : TEXCOORD;
    int index : TEXCOORD1;
};

VertexOut VS(uint vid : SV_VertexID)
{
	VertexOut vout;
    
	vout.TexC = gTexCoords[vid % 6];	
	
	// 输出最终结果
    vout.PosH = float4(vout.TexC.x * 2 - 1, 1 - vout.TexC.y * 2, 0.0f, 1.0f);
    vout.index = 0;
	
	if(vid >= 6)
    {
		// 输出高亮部分的模糊图像
        vout.PosH.xy = vout.PosH.xy * 0.25 + float2(-0.75, -0.55f);
        vout.index = 1;
    }

    return vout;
}


float4 PS(VertexOut pin) : SV_Target
{
    float3 baseColor = gBaseMap.SampleLevel(gsamPointClamp, pin.TexC, 0.0f).rgb;

    float3 bloomColor = gHighLightMap.SampleLevel(gsamPointClamp, pin.TexC, 0.0f).rgb;
	
	if(pin.index == 1)
        return float4(bloomColor, 1.0f);
	
    baseColor += bloomColor;
	
	// 曝光色调映射
	// 其中 exposure 越高, 暗部细节越多; 而较低时, 亮部细节增多, 暗部细节减少 
    float exposure = 0.6f;
    float3 result = 1.0 - exp(-baseColor * exposure);
	
	// 伽马矫正
    result = pow(result, 1 / 2.2);

    return float4(result, 1.0f);
}


