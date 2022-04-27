#pragma once

#include "../../Common/d3dUtil.h"

using Microsoft::WRL::ComPtr;

class BRDF
{
public:
	BRDF(ID3D12Device* device);

	BRDF(const BRDF& rhs) = delete;
	BRDF& operator=(const BRDF& rhs) = delete;
	~BRDF() = default;

	ID3D12Resource* Resource()
	{
		return mBRDF_LUT.Get();
	}
	CD3DX12_GPU_DESCRIPTOR_HANDLE Srv()const
	{
		return mGpuSrv;
	}

	CD3DX12_CPU_DESCRIPTOR_HANDLE Rtv()const
	{
		return mCpuRtv;
	}

	D3D12_VIEWPORT Viewport()const { return mViewport; }
	D3D12_RECT ScissorRect()const { return mScissorRect; }

	void BuildDescriptors(
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv,
		CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv,
		CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv);


private:
	void BuildDescriptors();
	void BuildResource();

private:

	ID3D12Device* md3dDevice = nullptr;

	D3D12_VIEWPORT mViewport;
	D3D12_RECT mScissorRect;

	UINT mWidth = 512;
	UINT mHeight = 512;
	DXGI_FORMAT mLUTFormat = DXGI_FORMAT_R16G16B16A16_FLOAT;


	CD3DX12_CPU_DESCRIPTOR_HANDLE mCpuSrv;
	CD3DX12_GPU_DESCRIPTOR_HANDLE mGpuSrv;
	CD3DX12_CPU_DESCRIPTOR_HANDLE mCpuRtv;

	ComPtr<ID3D12Resource> mBRDF_LUT = nullptr;
};


BRDF::BRDF(ID3D12Device* device)
{
	md3dDevice = device;

	mViewport = { 0.0f, 0.0f, (float)mWidth, (float)mHeight, 0.0f, 1.0f };
	mScissorRect = { 0, 0, (int)mWidth, (int)mHeight };

	BuildResource();
}

void BRDF::BuildResource()
{
	D3D12_RESOURCE_DESC texDesc;
	ZeroMemory(&texDesc, sizeof(D3D12_RESOURCE_DESC));
	texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	texDesc.Alignment = 0;
	texDesc.Width = mWidth;
	texDesc.Height = mHeight;
	texDesc.DepthOrArraySize = 1;
	texDesc.MipLevels = 1;
	texDesc.Format = mLUTFormat;
	texDesc.SampleDesc.Count = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

	float ClearColor[] = { 0.0f, 0.0f, 0.0f, 0.0f };
	// 创建资源
	CD3DX12_CLEAR_VALUE optClear(mLUTFormat, ClearColor);
	ThrowIfFailed(md3dDevice->CreateCommittedResource(
		&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
		D3D12_HEAP_FLAG_NONE,
		&texDesc,
		D3D12_RESOURCE_STATE_GENERIC_READ,
		&optClear,
		IID_PPV_ARGS(&mBRDF_LUT)));
}


void BRDF::BuildDescriptors(CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuSrv, CD3DX12_GPU_DESCRIPTOR_HANDLE hGpuSrv, CD3DX12_CPU_DESCRIPTOR_HANDLE hCpuRtv)
{
	mCpuSrv = hCpuSrv;
	mGpuSrv = hGpuSrv;
	mCpuRtv = hCpuRtv;

	BuildDescriptors();
}

void BRDF::BuildDescriptors()
{
	// 创建srv
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
	srvDesc.Format = mLUTFormat;
	srvDesc.Texture2D.MostDetailedMip = 0;
	srvDesc.Texture2D.MipLevels = 1;
	// 位置
	md3dDevice->CreateShaderResourceView(mBRDF_LUT.Get(), &srvDesc, mCpuSrv);


	// 接下来创建rtv
	D3D12_RENDER_TARGET_VIEW_DESC rtvDesc = {};
	rtvDesc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
	rtvDesc.Format = mLUTFormat;
	rtvDesc.Texture2D.MipSlice = 0;
	rtvDesc.Texture2D.PlaneSlice = 0;
	// 位置
	md3dDevice->CreateRenderTargetView(mBRDF_LUT.Get(), &rtvDesc, mCpuRtv);
}
