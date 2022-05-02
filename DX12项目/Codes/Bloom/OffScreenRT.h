#pragma once

#include "../../Common/d3dUtil.h"

class OffScreenRT
{
public:

	OffScreenRT(ID3D12Device* device, UINT width, UINT height);

	OffScreenRT(const OffScreenRT& rhs) = delete;
	OffScreenRT& operator=(const OffScreenRT& rhs) = delete;
	~OffScreenRT() = default;

	ID3D12Resource* Resource() { return mRT1Map.Get(); }
	ID3D12Resource* HighLightResource() { return mRT2Map.Get(); }

	CD3DX12_GPU_DESCRIPTOR_HANDLE Srv() { return mRT1GpuSrv; }
	CD3DX12_GPU_DESCRIPTOR_HANDLE HighLightSrv() { return mRT2GpuSrv; }

	CD3DX12_CPU_DESCRIPTOR_HANDLE Rtv() { return mRT1CpuRtv; }
	CD3DX12_CPU_DESCRIPTOR_HANDLE HighLightRtv() { return mRT2CpuRtv; }

	void BuildDescriptors(
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv,
		CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv,
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv,
		UINT srvSize, UINT rtvSize);

	void OnResize(UINT newWidth, UINT newHeight);

	DXGI_FORMAT Format() { return mFormat; }

	FLOAT* ClearColor(){ return optClear.Color; }

private:
	void BuildDescriptors();
	void BuildResource();

private:

	ID3D12Device* md3dDevice = nullptr;

	UINT mWidth = 0;
	UINT mHeight = 0;
	DXGI_FORMAT mFormat = DXGI_FORMAT_R8G8B8A8_UNORM;
	float Clear[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
	CD3DX12_CLEAR_VALUE optClear{ mFormat, Clear };

	// 用作渲染目标
	CD3DX12_CPU_DESCRIPTOR_HANDLE mRT1CpuSrv;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mRT1GpuSrv;
	CD3DX12_CPU_DESCRIPTOR_HANDLE mRT1CpuRtv;

	// 用于提取亮处
	CD3DX12_CPU_DESCRIPTOR_HANDLE mRT2CpuSrv;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mRT2GpuSrv;
	CD3DX12_CPU_DESCRIPTOR_HANDLE mRT2CpuRtv;

	Microsoft::WRL::ComPtr<ID3D12Resource> mRT1Map = nullptr;
	Microsoft::WRL::ComPtr<ID3D12Resource> mRT2Map = nullptr;
};

OffScreenRT::OffScreenRT(ID3D12Device* device, UINT width, UINT height)
{
	md3dDevice = device;
	mWidth = width;
	mHeight = height;

	BuildResource();
}

void OffScreenRT::BuildResource()
{
	D3D12_RESOURCE_DESC texDesc;
	ZeroMemory(&texDesc, sizeof(D3D12_RESOURCE_DESC));
	texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	texDesc.Alignment = 0;
	texDesc.Width = mWidth;
	texDesc.Height = mHeight;
	texDesc.DepthOrArraySize = 1;
	texDesc.MipLevels = 1;
	texDesc.Format = mFormat;
	texDesc.SampleDesc.Count = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

	ThrowIfFailed(md3dDevice->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
		D3D12_HEAP_FLAG_NONE,
		&texDesc,
		D3D12_RESOURCE_STATE_GENERIC_READ,
		&optClear,
		IID_PPV_ARGS(&mRT1Map)));

	ThrowIfFailed(md3dDevice->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
		D3D12_HEAP_FLAG_NONE,
		&texDesc,
		D3D12_RESOURCE_STATE_COPY_SOURCE,
		&optClear,
		IID_PPV_ARGS(&mRT2Map)));
}

void OffScreenRT::BuildDescriptors(CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv, CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv, CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv, UINT srvSize, UINT rtvSize)
{
	mRT1CpuSrv = hCpuSrv;
	mRT1GpuSrv = hGpuSrv;
	mRT1CpuRtv = hCpuRtv;

	mRT2CpuSrv = hCpuSrv.Offset(1, srvSize);
	mRT2GpuSrv = hGpuSrv.Offset(1, srvSize);
	mRT2CpuRtv = hCpuRtv.Offset(1, rtvSize);

	BuildDescriptors();
}

void OffScreenRT::BuildDescriptors()
{
	// 创建srv
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.Format = mFormat;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = 1;
	md3dDevice->CreateShaderResourceView(mRT1Map.Get(), &srvDesc, mRT1CpuSrv);

	md3dDevice->CreateShaderResourceView(mRT2Map.Get(), &srvDesc, mRT2CpuSrv);


	// 法线图的rtv
	D3D12_RENDER_TARGET_VIEW_DESC rtvDesc = {};
	rtvDesc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
	rtvDesc.Format = mFormat;
	rtvDesc.Texture2D.MipSlice = 0;
	rtvDesc.Texture2D.PlaneSlice = 0;
	//是否需要手动填rtv描述符
	md3dDevice->CreateRenderTargetView(mRT1Map.Get(), &rtvDesc, mRT1CpuRtv);

	md3dDevice->CreateRenderTargetView(mRT2Map.Get(), &rtvDesc, mRT2CpuRtv);
}


void OffScreenRT::OnResize(UINT newWidth, UINT newHeight)
{
	if ((mWidth != newWidth) || (mHeight != newHeight))
	{
		mWidth = newWidth;
		mHeight = newHeight;

		// 改变窗口尺寸后重新创建资源和其描述符
		BuildResource();
	}
}