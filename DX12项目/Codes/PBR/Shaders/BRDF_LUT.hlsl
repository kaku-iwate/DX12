#include "Common.hlsl"

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
	float4 PosH : SV_POSITION;
    float2 TexC : TEXCOORD;
};
 
VertexOut VS(uint vid : SV_VertexID)
{
    VertexOut vout = (VertexOut) 0.0f;
    
    vout.TexC = gTexCoords[vid];
    vout.PosH = float4(vout.TexC.x * 2 - 1, 1 - vout.TexC.y * 2, 0.0f, 1.0f);
	
	return vout;
}

// º∆À„BRDF_LUT
float4 PS(VertexOut pin) : SV_Target
{   	
    float2 lut = IntegrateBRDF(pin.TexC.x, pin.TexC.y);
    return float4(lut, 0.0f, 1.0f);
}

