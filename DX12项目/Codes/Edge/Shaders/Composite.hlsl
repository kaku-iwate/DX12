//***************************************************************************************
// Composite.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Combines two images.
//***************************************************************************************

Texture2D gBaseMap : register(t0);
Texture2D gSobelMap : register(t1);
Texture2D gNormalMap : register(t2);
Texture2D gDepthMap : register(t3);

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

static const float width = 1600;
static const float height = 1200;

static const float4 black = { 0.0f, 0.0f, 0.0f, 1.0f };
static const float4 white = { 1.0f, 1.0f, 1.0f, 1.0f };

struct VertexOut
{
	float4 PosH    : SV_POSITION;
	float2 TexC    : TEXCOORD;
    int index : TEXCOORD1;
};

VertexOut VS(uint vid : SV_VertexID)
{
	VertexOut vout;
	
    // 得到纹理索引, 源图像位于左上角, 索贝尔图像位于右上角
    // 法线边缘位于左下, 深度边缘位于右下
    int mapIndex = vid / 6; 
    vout.index = mapIndex;
    
    vid %= 6;
	vout.TexC = gTexCoords[vid];
    
    float offsetX = 1.0f;
    float offsetY = 1.0f;
	
    
    if(mapIndex >= 2)
    {
        mapIndex -= 2;
        offsetX -= mapIndex;
        offsetY = 0.0f;
    }
    else
    {
        offsetX -= mapIndex;
    }
	
    // 将[0,1]的纹理空间转换为NDC中的四个矩形
        vout.PosH = float4(vout.TexC.x - offsetX, offsetY - vout.TexC.y, 0.0f, 1.0f);

        return vout;
    }

// 使用Roberts算子
float4 normalEdge(float2 texIn)
{	
    float X = 1.0f / width;
    float Y = 1.0f / height;
    float2 offsetX = { X, 0.0f };
    float2 offsetY = { 0.0f, Y };
    
    
    float3 centerNormal = gNormalMap.SampleLevel(gsamPointClamp, texIn, 0.0f).xyz;
	
    for (int i = -1; i < 2; i++)
    {
        for (int j = -1; j < 2; j++)
        {
            float2 tex = texIn + i * offsetX + j * offsetY;
            float3 neighborNormal = gNormalMap.SampleLevel(gsamPointClamp, tex, 0.0f).xyz;
            if (dot(neighborNormal, centerNormal) < 0.9f)
            {
                return black;
            }
        }
    }

    return white;
    
    //float3 s[4];
    //s[0] = gNormalMap.SampleLevel(gsamPointClamp, texIn, 0.0f).xyz;
    //s[1] = gNormalMap.SampleLevel(gsamPointClamp, texIn+offsetX, 0.0f).xyz;
    //s[2] = gNormalMap.SampleLevel(gsamPointClamp, texIn-offsetY, 0.0f).xyz;
    //s[3] = gNormalMap.SampleLevel(gsamPointClamp, texIn-offsetY+offsetX, 0.0f).xyz;
    
    //float gx = dot(s[0], -s[3]);
    //float gy = dot(-s[1], s[2]);
    
    //float res = sqrt(gx * gx + gy * gy);

    //return res < 1.25f ? black : white;
}

float4 depthEdge(float2 texIn)
{
    float centerDepth = gDepthMap.SampleLevel(gsamPointClamp, texIn, 0.0f).x;
	
    float X = 1.0f / width;
    float Y = 1.0f / height;
    float2 offsetX = { X, 0.0f };
    float2 offsetY = { 0.0f, Y };
    

	
    for (int i = -1; i < 2; i++)
    {
        for (int j = -1; j < 2; j++)
        {
            float2 tex = texIn + i * offsetX + j * offsetY;
            float neighborDepth = gDepthMap.SampleLevel(gsamPointClamp, tex, 0.0f).x;
            if (abs(neighborDepth - centerDepth) > 0.01f)
            {
                return black;
            }
        }
    }

    return white;
}

float4 sobelEdge(float2 texIn)
{
    return gSobelMap.SampleLevel(gsamPointClamp, texIn, 0.0f);
}

float4 PS(VertexOut pin) : SV_Target
{
    float4 color = (0.0f);
    if(pin.index == 0)
    {
        color = gBaseMap.SampleLevel(gsamPointClamp, pin.TexC, 0.0f);
    }
    else if(pin.index == 1)
    {
        color = sobelEdge(pin.TexC);
    }
    else if(pin.index == 2)
    {
        color = normalEdge(pin.TexC);
    }
    else
    {
        color = depthEdge(pin.TexC);
    }
    
    return color;
}


