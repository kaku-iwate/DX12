#pragma once

#include "../../Common/d3dUtil.h"

class NormalDepth
{
public:

	NormalDepth(ID3D12Device* device, UINT width, UINT height);

	NormalDepth(const NormalDepth& rhs) = delete;
	NormalDepth& operator=(const NormalDepth& rhs) = delete;
	~NormalDepth() = default;

	ID3D12Resource* NormalMap() { return mNormalMap.Get(); }
	CD3DX12_GPU_DESCRIPTOR_HANDLE NormalSrv() { return mNormalGpuSrv; }
	CD3DX12_CPU_DESCRIPTOR_HANDLE NormalRtv() { return mNormalCpuRtv; }

	void BuildDescriptors(
		ID3D12Resource* depthBuffer,
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv,
		CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv,
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv,
		UINT srvSize);

	void OnResize(UINT newWidth, UINT newHeight);

	DXGI_FORMAT format() { return mNormalMapFormat; }

private:
	void BuildDescriptors(ID3D12Resource* depthBuffer);
	void BuildResource();

private:

	ID3D12Device* md3dDevice = nullptr;

	UINT mWidth = 0;
	UINT mHeight = 0;
	DXGI_FORMAT mNormalMapFormat = DXGI_FORMAT_R16G16B16A16_FLOAT;

	// 法线相关描述符
	CD3DX12_CPU_DESCRIPTOR_HANDLE mNormalCpuSrv;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mNormalGpuSrv;
	CD3DX12_CPU_DESCRIPTOR_HANDLE mNormalCpuRtv;

	// 深度相关描述符
	CD3DX12_CPU_DESCRIPTOR_HANDLE mDepthCpuSrv;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mDepthGpuSrv;

	// Two for ping-ponging the textures.
	Microsoft::WRL::ComPtr<ID3D12Resource> mNormalMap = nullptr;
};

NormalDepth::NormalDepth(ID3D12Device* device, UINT width, UINT height)
{
	md3dDevice = device;
	mWidth = width;
	mHeight = height;

	BuildResource();
}

void NormalDepth::BuildResource()
{
	D3D12_RESOURCE_DESC texDesc;
	ZeroMemory(&texDesc, sizeof(D3D12_RESOURCE_DESC));
	texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	texDesc.Alignment = 0;
	texDesc.Width = mWidth;
	texDesc.Height = mHeight;
	texDesc.DepthOrArraySize = 1;
	texDesc.MipLevels = 1;
	texDesc.Format = mNormalMapFormat;
	texDesc.SampleDesc.Count = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

	float normalClearColor[] = { 0.0f, 0.0f, 1.0f, 0.0f };
	CD3DX12_CLEAR_VALUE optClear(mNormalMapFormat, normalClearColor);
	ThrowIfFailed(md3dDevice->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
		D3D12_HEAP_FLAG_NONE,
		&texDesc,
		D3D12_RESOURCE_STATE_GENERIC_READ,
		&optClear,
		IID_PPV_ARGS(&mNormalMap)));
}

void NormalDepth::BuildDescriptors(ID3D12Resource* depthBuffer, CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv, CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv, CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv, UINT srvSize)
{
	mNormalCpuSrv = hCpuSrv;
	mNormalGpuSrv = hGpuSrv;
	mNormalCpuRtv = hCpuRtv;

	mDepthCpuSrv = hCpuSrv.Offset(1, srvSize);
	mDepthGpuSrv = hGpuSrv.Offset(1, srvSize);

	BuildDescriptors(depthBuffer);
}

void NormalDepth::BuildDescriptors(ID3D12Resource* depthBuffer)
{
	// 为法线图创建srv
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.Format = mNormalMapFormat;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = 1;
	md3dDevice->CreateShaderResourceView(mNormalMap.Get(), &srvDesc, mNormalCpuSrv);

	// 为深度图创建srv
	srvDesc.Format = DXGI_FORMAT_R24_UNORM_X8_TYPELESS;
	md3dDevice->CreateShaderResourceView(depthBuffer, &srvDesc, mDepthCpuSrv);


	// 法线图的rtv
	D3D12_RENDER_TARGET_VIEW_DESC rtvDesc = {};
	rtvDesc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
	rtvDesc.Format = mNormalMapFormat;
	rtvDesc.Texture2D.MipSlice = 0;
	rtvDesc.Texture2D.PlaneSlice = 0;
	//是否需要手动填rtv描述符
	md3dDevice->CreateRenderTargetView(mNormalMap.Get(), &rtvDesc, mNormalCpuRtv);
}


void NormalDepth::OnResize(UINT newWidth, UINT newHeight)
{
	if ((mWidth != newWidth) || (mHeight != newHeight))
	{
		mWidth = newWidth;
		mHeight = newHeight;
		
		// 改变窗口尺寸后重新创建资源和其描述符
		BuildResource();
	}
}



