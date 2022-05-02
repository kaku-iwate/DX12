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
    vout.index = 0;
    
	vout.TexC = gTexCoords[vid];

	
    // 将[0,1]的纹理空间转换为NDC中的四个矩形
    vout.PosH = float4(vout.TexC.x * 2 - 1, 1 - vout.TexC.y * 2, 0.0f, 1.0f);

    return vout;
}


float4 PS(VertexOut pin) : SV_Target
{
    float4 color = (0.0f);

    color = gBaseMap.Sample(gsamPointClamp, pin.TexC, 0.0f);
	
    if (color.r < 0.6 && color.g < 0.6 && color.b < 0.6)
        color = float4(0, 0, 0, 1);

    return color;
}


