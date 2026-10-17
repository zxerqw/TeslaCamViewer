# TeslaCamViewer

面向特斯拉车主的 iOS 应用：在 iPhone / iPad 上浏览 TeslaCam U 盘里的行车记录仪视频，修剪片段，并导出带时间戳水印的视频。

视频直接从 U 盘读取，不整盘复制到手机。一次哨兵或主动保存里按分钟切开的多路 MP4，会拼成一条连续时间线来播放和导出。

## 功能

- 扫描 `SavedClips`、`SentryClips`、`RecentClips`
- 按「主动保存 / 哨兵 / 最近」分栏列出事件
- 最多六路视角：前、后、左右后视镜、左右 B 柱；老车型只有四路时自动适配
- 默认四宫格同步播放，可更换格子里的视角
- 时间轴修剪（秒级），跨分钟文件无缝拼接
- 导出四宫格合成视频，或按视角分别导出独立 MP4
- 动态时间戳水印，水印位置可选
- 导出后保存到系统相册，并调起系统分享面板

要求 iOS 17 及以上，支持 iPhone 与 iPad。

## 环境

- Xcode 15+（Swift 5.9）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [xcbeautify](https://github.com/cpisciotta/xcbeautify)（`make` 用来格式化构建输出）

```bash
brew install xcodegen xcbeautify
```

## 构建与运行

工程文件由 `project.yml` 生成，不纳入版本库。

```bash
make generate   # 根据 project.yml 生成 TeslaCamViewer.xcodeproj
make build      # 为模拟器编译
make test       # 跑完整测试
make run        # 安装并在模拟器启动
```

真机：

```bash
make list-devices
make run-device
# 指定设备：DEVICE_ID='设备名或 UUID' make run-device
```

默认模拟器是 `iPhone 17`，可用 `SIMULATOR='iPhone 16 Pro' make test` 覆盖。

签名使用自动签名。`project.yml` 里的 Team ID 需要换成你自己的 Apple Developer Team，否则无法安装到真机。

## 目录

```
TeslaCamViewer/          App 源码（SwiftUI + Domain + Infrastructure）
TeslaCamViewerTests/     单元测试与集成测试
project.yml              XcodeGen 工程描述
Makefile                 构建、测试、模拟器与真机安装
docs/                    设计与实现计划
```

## 许可

[MIT](LICENSE)
