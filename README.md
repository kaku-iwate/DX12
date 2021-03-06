# DX12
项目中使用了《DirectX 12 3D游戏开发实战》也就是龙书所给出的代码框架.  并且担心不同功能间相互影响, 整合在一起恐怕复杂度剧增, 自己水平不够难以掌握, 因此各个功能都是独立开来分别完成的.  

在多数实现中可以用 WASD 进行移动, 按住鼠标左键转动视角.  

另外在较低版本的的VS中打开项目可能会出现MSB8020错误.  

MSBuild 8020错误 : 项目代码都使用Visual Studio 2019构建, 若使用低于2019的版本则会出现这个错误.  
解决方法 : 项目 >> 属性 >> 常规 >> 平台工具集 >> 切换到对应版本工具集后确认即可.  


# **各个功能的简要展示**  

[1.基于几何着色器的曲面细分](#几何着色器)

[2.图像与几何两种方式的边缘检测](#边缘检测)

[3.基于法线贴图与位移贴图的波浪模拟](#波浪模拟)

[4.泛光效果](#Bloom)

[5.PCSS](#PCSS软阴影)

[6.延迟渲染](#延迟渲染)

[7.PBR](#PBR)

## 几何着色器
### 1. 实现
几何着色器擅长创建与销毁几何图形. 在看过的示例中, 公告牌技术与粒子系统均使用几何着色器进行实现. 
具体实现中, 为了便于观察细分将PSO设置线框模式, 并由数字键1,2,3(位于QWER键上面的数字键)来变更细分等级.  
    
### 2. 实现效果图  
  
![gs1](https://user-images.githubusercontent.com/79561572/165715665-791bcd18-e1c5-424a-b10a-10f0f0053b53.png)  
未经细分的球体  
  
![gs2](https://user-images.githubusercontent.com/79561572/165715825-b734d206-dc9d-4880-91e2-22c881afce37.png)  
一次细分后的球体  
  
  
![gs3](https://user-images.githubusercontent.com/79561572/165715878-67e51b01-c0fd-435c-8e09-a8b293f407f4.png)  
二次细分后的球体  

  
<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>  
      
      
## 边缘检测
### 1. 边缘检测实现概述  
索贝尔算子部分利用计算着色器进行输出, 计算着色器独立于渲染流水线之外, 因此其调用(不是 Draw Call 而是 Dispatch Call), 格式(UAV), PSO设置, 输出设置(RWTexture2D"<"Type">")等等均与平时有所不同, 需要留意. 另外, Dispatch 分派调用时, 需指定线程数, 而N卡与A卡对线程数的对齐要求不同.  
  
法线与深度部分曾尝试使用 Roberts 算子进行边缘检测, 但效果并不好, 边缘会断断续续. 因此使用较为粗糙的办法, 对3x3范围内的点进行采样比较来检测边缘.  
  

### 2. 实现效果图
按住鼠标左键可转动视角, 按住鼠标右键可控制距离.

![edge](https://user-images.githubusercontent.com/79561572/165698802-85d70bd0-c269-4e1d-955f-b76e12d5bd1f.png)

左上为源图像, 右上为索贝尔算子的逆图像  
左下为法线边缘, 右下为深度边缘.  
  
<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>


## 波浪模拟
### 1. 波浪模拟的实现概述

在波浪模拟中因为顶点位移只涉及Y轴(即高度)一个维度上的位移, 因此利用法线贴图的A通道, 将两者整合到了一起.  
在具体实现中, 因顶点着色器不能对贴图进行采样, 因此本该在顶点着色器进行的所有的计算都挪到了曲面细分阶段.  

在DX12中, 顶点着色器与几何着色器中间有一个由三部分组成的曲面细分阶段:  
 1. 外壳着色器: (1.1) 常量外壳着色器, 用于控制边与内部的细分因子、 (1.2) 控制点外壳着色器  
 2. 镶嵌器阶段, 根据细分因子进行曲面细分, 无法控制  
 3. 域着色器, 相当于细分后新增顶点的顶点着色器  

另外, 在域着色器中似乎只能使用 SampleLevel 方法对贴图采样(即必须指定 mipmap 等级). 后面查了后才知道 sample 方法GPU会自动指定 mipmap 等级, 通过 ddx 和 ddy 来看相邻像素间的uv坐标差距, 差的越多证明物体距离摄像机更远, mipmap 等级也要更高.

### 2. 实现效果图
![20220428_0041412022428049172](https://user-images.githubusercontent.com/79561572/165559384-b4bf9208-228c-40bc-a63a-929168338259.gif)  



<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>  

## Bloom
### 1. Bloom实现概述
泛光效果的步骤如下:  
1. 正常渲染  
2. 提取出高亮部分  
3. 对高亮部分进行模糊 
4. 对原图像以及模糊后的高亮部分图像进行叠加  

其中模糊部分使用了高斯模糊, 并利用其可分离性, 将 N² 次采样降低为 2N. 对于其他不具备分离性的卷积操作, 也可以这样操作来减少采样, 优化性能.

在具体实现中, 问题主要出现在最后一步上, 直接叠加的话, 高亮部分画面一片白, 观感很差.  
给高亮部分加个权值或者使用 Reinhard 色调映射(其公式为 A / (A + 1))的话, 效果也不是很好.  
  
后面参考了 LearnOpenGL 上 HDR 部分的曝光色调映射.  
https://learnopengl-cn.github.io/05%20Advanced%20Lighting/06%20HDR/  
曝光色调映射公式为: 1.0 - exp(-Color * exposure), 其中 exposure 可理解为曝光度, 其值越高, 暗部细节越多, 反之则亮部细节越多.  

### 实现效果图  
  
![bloom](https://user-images.githubusercontent.com/79561572/166232270-1c9617a4-0615-4c27-b158-ee16efdd7407.png)  
  
  其中左下角小窗口为高亮部分模糊后的结果.
  
  <p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>  
    
## PCSS软阴影
### 1. PCSS软阴影实现概述

相较于PCF, PCSS主要改善在可以动态调整filter大小, 其核心主要有三步:  
  1. 搜索一定范围内的遮挡物平均深度  
  2. 根据平均深度来计算PCF的filter大小  
  3. PCF部分  

计算filter大小的公式为:

![图片1](https://user-images.githubusercontent.com/79561572/165554169-2dc04a7f-801d-40be-86e0-d8a0bc70fab9.png)

在具体实现中, 第一步搜索平均深度的范围定为了固定大小. 而第三步中过多的采样会对帧率影响极大.   
因此使用16个点的泊松分布采样. 这一部分参考了 Nvidia 的实现:  
https://developer.download.nvidia.com/whitepapers/2008/PCSS_Integration.pdf  
但是因为采样分布固定且数量太少会导致阴影分层,特别是filter较大时分层很严重. 效果如下:  
![shadow1](https://user-images.githubusercontent.com/79561572/166132227-ea0e5b43-225c-4e14-a97a-4d8ad66ee96e.png)    
<p align="center">1. 阴影分层 </p><br>  
  
  
如果生成伪随机数, 对泊松分布进行旋转, 可以改善分层, 但又会导致噪点问题. 而比噪点更影响观感的是近距离时阴影会有类似于摩尔纹的部分(红圈处), 效果如下:  
  
![shadow2-2](https://user-images.githubusercontent.com/79561572/166132338-4d9deaf1-848b-4ccd-984f-0032dfd454c8.png)  
<p align="center">2. 阴影噪点与摩尔纹 </p><br>  

对于这样的噪点与摩尔纹, 在虎书上看到过高斯模糊对其效果很好. 但这要把阴影部分单独渲染到一张纹理上进行模糊再叠加回去, 一是很耗性能, 二是很麻烦.  
后面参考了 Games 202 作业1的框架, 其中对于每个纹理坐标都重新生成一次随机的泊松分布盘, 只需增大一些泊松分布盘以及采样数量即可得到较好的软阴影, 效果如下:  
  ![shadow3](https://user-images.githubusercontent.com/79561572/166133134-6e5982a6-d952-4256-b859-9b29011d032b.png)  
<p align="center">3. 每次重新生成泊松分布盘 </p><br>  


### 2. 最终效果图

![shadow3](https://user-images.githubusercontent.com/79561572/166133171-437b3124-261b-409a-9180-403a9151e4f2.png)  
虽然PCSS软阴影的实现流程很容易理解, 但想要高效实现却很难.


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

需要利用此方程计算的光源也可以分为两种: 一是数量已知、位置固定的直接光, 可以直接套公式计算; 二是位于法线半球上的环境光, 实时渲染中中用 IBL 来近似实现.

具体实现参考了LearnOpenGL以及知乎上的众多文章.
https://learnopengl-cn.github.io/07%20PBR/03%20IBL/01%20Diffuse%20irradiance/


### 2.整体实现的效果

着色器文件均位于 Shaders 文件夹下, 其中 Common.hlsl 包含了DGF 项的实现以及IBL中所需要的辐照度、BRDF积分等计算. 而PBR主体的实现位于 PBR.hlsl 文件当中.

在程序运行中可用WASD进行移动， 按住鼠标左键可转动视角.

![PBR](https://user-images.githubusercontent.com/79561572/165525515-40f28063-5ff5-4b9e-976c-191f62695aec.png)  
  
  
其中对DGF三项的实现代码为:  
  
F: 菲涅尔项, 使用Fresnel-Schlick近似  
![F](https://user-images.githubusercontent.com/79561572/165925046-0deb26fd-2858-4af6-9001-666f2a3287d7.png)  
  
D: 法线分布函数, 使用GGX模型, 其拥有更长的尾部  
![D](https://user-images.githubusercontent.com/79561572/165925147-b047f395-b9ad-4a83-8304-178b66b406a4.png)  
  
G: 几何遮蔽, 分为两部分, 一是因微表面不平整而产生的对于入射光的几何阴影, 二是对于出射光的几何遮蔽  
![G](https://user-images.githubusercontent.com/79561572/165925376-89020727-cc55-4cba-b9dd-752993cd6838.png)  
  
  
<p align="center"><a href="#DX12">🔙 返回目录 🔙</a></p><br>
