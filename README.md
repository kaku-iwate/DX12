# DX12
项目中使用了《DirectX 12 3D游戏开发实战》也就是龙书所给出的代码框架.  并且担心不同功能间相互影响, 整合在一起恐怕复杂度剧增, 自己水平不够难以掌握, 因此各个功能都是独立开来分别完成的.  

在多数实现中可以用 WASD 进行移动, 按住鼠标左键转动视角.  

另外在较低版本的的VS中打开项目可能会出现MSB8020错误.  

MSBuild 8020错误 : 项目代码都使用Visual Studio 2019构建, 若使用低于2019的版本则会出现这个错误.  
解决方法 : 项目 >> 属性 >> 常规 >> 平台工具集 >> 切换到对应版本工具集后确认即可.  


# **各个功能的简要展示**  

1.基于几何着色器的曲面细分  

2.图像与几何两种方式的边缘检测

[3.基于法线贴图与位移贴图的波浪模拟](#波浪模拟)

[4.PCSS](#PCSS软阴影)

[5.延迟渲染](#延迟渲染)

[6.PBR](#PBR)

## 边缘检测
### 1. 边缘检测实现该睡

### 2. 实现效果图
![edge](https://user-images.githubusercontent.com/79561572/165698802-85d70bd0-c269-4e1d-955f-b76e12d5bd1f.png)

左上为源图像, 右上为索贝尔算子的逆图像, 左下为法线边缘, 右下为深度边缘.  

<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>


## 波浪模拟
### 1. 波浪模拟的实现概述

在波浪模拟中因为顶点位移只涉及Y轴(即高度)一个维度上的位移, 因此利用法线贴图的A通道, 将两者整合到了一起.  
在具体实现中, 因顶点着色器不能对贴图进行采样, 因此本该在顶点着色器进行的所有的计算都挪到了曲面细分阶段.  

在DX12中, 顶点着色器与几何着色器中间有一个由三部分组成的曲面细分阶段:  
(1). 外壳着色器: (1.1) 常量外壳着色器, 用于控制边与内部的细分因子、 (1.2) 控制点外壳着色器  
(2). 镶嵌器阶段, 根据细分因子进行曲面细分, 无法控制
(3). 域着色器, 相当于细分后新增顶点的顶点着色器  

需要注意的是, 在域着色器中似乎只能使用 SampleLevel 方法对贴图采样(即必须指定 mipmap 等级).  
猜测应该是曲面细分阶段与生俱来就有实现动态LOD的能力, 外壳着色器阶段根据距离远近来增减细分因子, 而在域着色器中也应该与细分因子增减相对应地来增减 mipmap 等级. 

### 2. 实现效果图
![20220428_0041412022428049172](https://user-images.githubusercontent.com/79561572/165559384-b4bf9208-228c-40bc-a63a-929168338259.gif)  



<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>


## PCSS软阴影
### 1. PCSS软阴影实现概述

相较于PCF, PCSS主要改善在可以动态调整filter大小, 其核心主要有三步:  
  (1). 搜索一定范围内的遮挡物平均深度  
  (2). 根据平均深度来计算PCF的filter大小  
  (3). PCF部分  

计算filter大小的公式为:

![图片1](https://user-images.githubusercontent.com/79561572/165554169-2dc04a7f-801d-40be-86e0-d8a0bc70fab9.png)

在具体实现中, 第一步搜索平均深度的范围定为了固定大小. 而第三步中过多的采样会对帧率影响极大, 因此使用16个点的泊松分布采样. 但是在filter较大时因采样分布固定且数量太少会导致阴影分层很严重, 如果对泊松分布进行随机旋转, 可以改善分层, 但又会导致噪点问题. 没能找到较好的解决方法, 所以将filter大小限制在较小范围内以来改善分层问题.

### 2. 实现效果图
![PCSS](https://user-images.githubusercontent.com/79561572/165555067-bd7a68e6-a944-48ca-ba73-3d84d9ed82fb.png)  


<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>


## 延迟渲染
### 1. 延迟渲染实现概述
延迟渲染需要两个pass, 第一个pass中将计算光照所需的各种数据写入到渲染目标, 第二个pass中使用这些数据来计算光照. 

在具体的实现中, pass1用到了格式不同的三个渲染目标, 分别储存1.位置、2.法线、3.颜色, 并在位置、法线渲染目标空余的A通道储存粗糙度等数据. pass2绘制一个全屏四边形,并对对应纹理坐标的三种数据进行采样用以计算光照.

### 2. 实现效果图
![DeferredShading](https://user-images.githubusercontent.com/79561572/165546247-317c510a-6139-4cf5-85b0-f3046661f03e.png)


其中三个小窗从左到右分别对应1.颜色2.法线3.位置  



<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>

## PBR
### 1. PBR实现概述

PBR核心为渲染方程, 其公式如下

![image](https://user-images.githubusercontent.com/79561572/165524163-7156a9b3-f7db-426b-9975-5d1999d4ea94.png)

可将渲染方程拆分为两部分: 漫反射 + 镜面反射.

其中漫反射有兰伯特模型以及迪士尼的模型, 而镜面反射为Cook-Torrance模型.

需要利用此方程计算的光源也可以分为两种: 一是数量已知、位置固定的直接光, 可以直接套公式计算; 二是位于法线半球上的环境光, 实时渲染中无法直接计算, 实践中用IBL来近似实现.


### 2.整体实现的效果

着色器文件均位于 Shaders 文件夹下, 其中 Common.hlsl 包含了DGF 项的实现以及IBL中所需要的辐照度、BRDF积分等计算. 而PBR主体的实现位于 PBR.hlsl 文件当中.

在程序运行中可用WASD进行移动， 按住鼠标左键可转动视角.

![PBR](https://user-images.githubusercontent.com/79561572/165525515-40f28063-5ff5-4b9e-976c-191f62695aec.png)  






<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>
