
static const float weights[31] =
{
    0.00748799136, 0.00968984514, 0.0123182079, 0.0153835788, 0.0188732408, 0.0227465089, 0.0269316062, 0.0313248485, 0.0357927382, 0.0401772372, 0.0443041511, 0.0479941145,
	0.0510752797, 0.0533964932, 0.0548395552, 0.0553291887, 0.0548395552, 0.0533964932, 0.0510752797, 0.0479941145, 0.0443041511, 0.0401772372, 0.0357927382, 0.0313248485,
	0.0269316062, 0.0227465089, 0.0188732408, 0.0153835788, 0.0123182079, 0.00968984514, 0.00748799136
};

// 将模糊半径固定为15
static const int gBlurRadius = 15;


Texture2D gInput            : register(t0);
RWTexture2D<float4> gOutput : register(u0);

#define N 256
#define CacheSize (N + 2*gBlurRadius)  // 两头分别多分配了一点, 用来处理越界.
groupshared float4 gCache[CacheSize];

[numthreads(N, 1, 1)]
void HorzBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	//
	// 通过将图像加载到本地储存, 以此来减轻带宽的负载.
	// 若对N个像素进行模糊处理, 则需要 N + 2*BlurRadius 个像素需要加载.
	// 两头多出来的用于处理越界情况.
	//
	
	// 此线程组运行 N 个线程. 为了获取填充两头多出来的部分
	// 就需要 2*BlurRadius 个线程多采集一个像素.
	if(groupThreadID.x < gBlurRadius)
	{
		// 对图像左边的越位采样进行钳位操作.(即钳制在0号位)
		int x = max(dispatchThreadID.x - gBlurRadius, 0);
		gCache[groupThreadID.x] = gInput[int2(x, dispatchThreadID.y)];
	}
	if(groupThreadID.x >= N-gBlurRadius)
	{
		// 对图像右侧的越位采样进行钳位操作.
		int x = min(dispatchThreadID.x + gBlurRadius, gInput.Length.x-1);
		gCache[groupThreadID.x+2*gBlurRadius] = gInput[int2(x, dispatchThreadID.y)];
	}

	// 对图像边界的越界采样进行钳位.
	gCache[groupThreadID.x+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];

	// 等待组内所有线程完成上面的操作.
	GroupMemoryBarrierWithGroupSync();
	
	//
	// 现在对每个像素进行模糊操作.
	//

	float4 blurColor = float4(0, 0, 0, 0);
	
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.x + gBlurRadius + i;
		
		blurColor += weights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}


// 垂直方向的模糊操作, 与水平方向的操作一致.
// 只是在钳位上略有不同.
[numthreads(1, N, 1)]
void VertBlurCS(int3 groupThreadID : SV_GroupThreadID,
				int3 dispatchThreadID : SV_DispatchThreadID)
{
	if(groupThreadID.y < gBlurRadius)
	{
		// 钳位
		int y = max(dispatchThreadID.y - gBlurRadius, 0);
		gCache[groupThreadID.y] = gInput[int2(dispatchThreadID.x, y)];
	}
	if(groupThreadID.y >= N-gBlurRadius)
	{
		int y = min(dispatchThreadID.y + gBlurRadius, gInput.Length.y-1);
		gCache[groupThreadID.y+2*gBlurRadius] = gInput[int2(dispatchThreadID.x, y)];
	}
	
	gCache[groupThreadID.y+gBlurRadius] = gInput[min(dispatchThreadID.xy, gInput.Length.xy-1)];


	// 等待其他线程的同步操作
	GroupMemoryBarrierWithGroupSync();
	

	float4 blurColor = float4(0, 0, 0, 0);
	
	for(int i = -gBlurRadius; i <= gBlurRadius; ++i)
	{
		int k = groupThreadID.y + gBlurRadius + i;
		
		blurColor += weights[i+gBlurRadius]*gCache[k];
	}
	
	gOutput[dispatchThreadID.xy] = blurColor;
}