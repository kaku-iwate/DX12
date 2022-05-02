
static const float weights[31] =
{
    0.00748799136, 0.00968984514, 0.0123182079, 0.0153835788, 0.0188732408, 0.0227465089, 0.0269316062, 0.0313248485, 0.0357927382, 0.0401772372, 0.0443041511, 0.0479941145,
	0.0510752797, 0.0533964932, 0.0548395552, 0.0553291887, 0.0548395552, 0.0533964932, 0.0510752797, 0.0479941145, 0.0443041511, 0.0401772372, 0.0357927382, 0.0313248485,
	0.0269316062, 0.0227465089, 0.0188732408, 0.0153835788, 0.0123182079, 0.00968984514, 0.00748799136
};

// ��ģ���뾶�̶�Ϊ15
static const int gBlurRadius = 15;


Texture2D gInput            : register(t0);
RWTexture2D<float4> gOutput : register(u0);

#define N 256
#define CacheSize (N + 2*gBlurRadius)  // ��ͷ�ֱ�������һ��, ��������Խ��.
groupshared float4 gCache[CacheSize];

[numthreads(N, 1, 1)]
void HorzBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	//
	// ͨ����ͼ����ص����ش���, �Դ����������ĸ���.
	// ����N�����ؽ���ģ������, ����Ҫ N + 2*BlurRadius ��������Ҫ����.
	// ��ͷ����������ڴ���Խ�����.
	//
	
	// ���߳������� N ���߳�. Ϊ�˻�ȡ�����ͷ������Ĳ���
	// ����Ҫ 2*BlurRadius ���̶߳�ɼ�һ������.
	if(groupThreadID.x < gBlurRadius)
	{
		// ��ͼ����ߵ�Խλ��������ǯλ����.(��ǯ����0��λ)
		int x = max(dispatchThreadID.x - gBlurRadius, 0);
		gCache[groupThreadID.x] = gInput[int2(x, dispatchThreadID.y)];
	}
	if(groupThreadID.x >= N-gBlurRadius)
	{
		// ��ͼ���Ҳ��Խλ��������ǯλ����.
		int x = min(dispatchThreadID.x + gBlurRadius, gInput.Length.x-1);
		gCache[groupThreadID.x+2*gBlurRadius] = gInput[int2(x, dispatchThreadID.y)];
	}

	// ��ͼ��߽��Խ���������ǯλ.
	gCache[groupThreadID.x+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];

	// �ȴ����������߳��������Ĳ���.
	GroupMemoryBarrierWithGroupSync();
	
	//
	// ���ڶ�ÿ�����ؽ���ģ������.
	//

	float4 blurColor = float4(0, 0, 0, 0);
	
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.x + gBlurRadius + i;
		
		blurColor += weights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}


// ��ֱ�����ģ������, ��ˮƽ����Ĳ���һ��.
// ֻ����ǯλ�����в�ͬ.
[numthreads(1, N, 1)]
void VertBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	if(groupThreadID.y < gBlurRadius)
	{
		// ǯλ
		int y = max(dispatchThreadID.y - gBlurRadius, 0);
		gCache[groupThreadID.y] = gInput[int2(dispatchThreadID.x, y)];
	}
	if(groupThreadID.y >= N-gBlurRadius)
	{
		int y = min(dispatchThreadID.y + gBlurRadius, gInput.Length.y-1);
		gCache[groupThreadID.y+2*gBlurRadius] = gInput[int2(dispatchThreadID.x, y)];
	}
	
	gCache[groupThreadID.y+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];


	// �ȴ������̵߳�ͬ������
	GroupMemoryBarrierWithGroupSync();
	

	float4 blurColor = float4(0, 0, 0, 0);
	
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.y + gBlurRadius + i;
		
		blurColor += weights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}