# TeslaCamViewer — 设计文档

**日期**：2026-04-22
**平台**：iOS 17+（iPhone / iPad）
**状态**：设计阶段（brainstorming 产物，待 writing-plans 接棒）

## 1. 产品定位

为特斯拉车主做一个 iOS App，用于查看 TeslaCam U 盘上的行车记录仪视频并导出带水印的片段。

**使用场景**：车主发生事故或遇到值得保存的画面后，通过 Lightning/USB-C 转接头把特斯拉 U 盘接到 iPhone/iPad，在 App 里浏览事件、选择视角和时间范围，导出可分享的带时间戳水印的视频。

**核心价值**：
- 把特斯拉按"每分钟 × 每视角"切碎的零散 MP4 组织成连续、可浏览、可拼合的事件
- 在移动设备上完成原本需要电脑才能做的"选视角 + 修剪 + 合成水印 + 导出"
- 不把大视频复制到手机本地（iOS 存储紧张），直接在 U 盘上读写

**核心场景**：**导出为主，浏览是为了找要导出的素材**。UI 的主次顺序、交互精度、性能优化都围绕这个目标。

## 2. 功能范围

### 支持的数据源

| 目录 | 内容 | 支持 |
|---|---|---|
| `TeslaCam/SavedClips/` | 用户按喇叭主动保存的片段 | ✅ |
| `TeslaCam/SentryClips/` | 哨兵模式触发的片段 | ✅ |
| `TeslaCam/RecentClips/` | 最近滚动缓冲的片段（会被覆盖） | ✅ |

### 支持的视角（最多 6 路）

| 视角 | 文件名后缀 | 备注 |
|---|---|---|
| 前 | `-front.mp4` | |
| 后 | `-back.mp4` | |
| 左后视镜 | `-left_repeater.mp4` | |
| 右后视镜 | `-right_repeater.mp4` | |
| 左 B 柱 | `-left_pillar.mp4` | 仅新车型 |
| 右 B 柱 | `-right_pillar.mp4` | 仅新车型 |

老车型只有 4 路的情况自动适配——视角选择器里只展示实际存在的视角。

### 事件列表

- 三个 Tab：**主动保存** / **哨兵** / **最近**
- 每个 Tab 内按时间倒序
- 每项显示缩略图 + 时间 + 事件元信息（若 `event.json` 存在则显示地点/原因）
- 三类事件进入详情页后**体验完全一致**

### 详情页 / 播放 & 修剪

- **默认四宫格**同步播放前/后/左后视镜/右后视镜
- 单个格子可通过"配置网格"弹窗换成任意其他可用视角（包含 B 柱等）
- 若某格子配置的视角在事件中缺失，该格**留空显示黑帧 + 视角名提示**（不自动隐藏或变阵）
- 底部**时间轴 + 修剪条**：
  - 缩略图条（以主视角——默认前视角——抽帧）
  - 左右两个手柄，拖拽确定起止（秒粒度）
  - 播放头随当前播放位置移动；拖手柄时播放头联动预览
- **跨分钟文件无缝拼接**：一次哨兵触发的 ~1 分钟或多分钟视频在播放和时间轴上呈现为单条连续时间线

### 导出

支持两种导出模式（用户在导出面板里选择）：

1. **四宫格合成**：把当前网格的 4 路视角合成一个 2×2 的 MP4
2. **多视角独立导出**：从 6 个视角里多选 N 个，每个视角导出一个独立的 MP4（不拼接）

**共同规则**：
- 时间范围从修剪条继承
- 时间戳水印（动态，每帧基于原始录制时间）
- 视角标签（四宫格时每格标注）
- 水印位置用户可选（四角之一），默认**左下**
- **单次导出不能跨多个事件**（简化范围）

**导出去向**（先后顺序）：
1. 导出完成后**先自动存入系统相册**（若用户授权）
2. 随后弹出**系统分享面板**（AirDrop / 保存到文件 / 其他 App），用户可选择是否再分享一次
3. 若相册权限被拒，跳过步骤 1 直接到步骤 2

### 不在本期范围内（YAGNI）

- Android 或其他平台
- 画中画、并排双视角导出
- 车辆数据水印（车速、位置——U 盘本身不存这些）
- 跨事件合并（把几次相邻触发拼成一个长视频）
- 云端备份 / iCloud 同步
- 事件收藏 / 标签 / 搜索
- 视频编辑（滤镜、字幕、音频调整等）

## 3. 总体架构

五个模块，自下而上分层，每个模块职责单一。

```
┌──────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│   EventList / GridConfig / GridPlayer / ExportSheet  │
└──────────────┬───────────────────────────────────────┘
               │ @Observable ViewModels
┌──────────────▼───────────────────────────────────────┐
│                    Domain Layer                      │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ LibraryStore │  │ PlaybackCtrl │  │ ExportJob  │ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬─────┘ │
└─────────┼─────────────────┼─────────────────┼───────┘
          │                 │                 │
┌─────────▼─────────────────▼─────────────────▼───────┐
│                  Infrastructure                      │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ TeslaCamScan │  │ MultiAVPlayer│  │ AVCompose  │ │
│  │ (文件系统扫描) │  │ (多路同步播放) │  │ (视频合成)  │ │
│  └──────────────┘  └──────────────┘  └────────────┘ │
└──────────────────────────────────────────────────────┘
```

**五个模块**：

1. **TeslaCamScanner**（Infrastructure）——扫描 security-scoped URL 下的 TeslaCam 文件夹，识别三类目录，把每个子文件夹解析为 `TeslaEvent`。纯数据层，不依赖 UI。
2. **LibraryStore**（Domain，`@Observable`）——持有扫描出的事件集合，暴露按类型筛选的三个列表给 Views 订阅。
3. **MultiAVPlayerController**（Domain）——管理 ≤4 个同步的 `AVPlayer`，把多个 `MinuteSegment` 下的同视角文件拼成一条 `AVMutableComposition`，对外暴露"统一时间轴（CMTime）"概念。
4. **ExportJob**（Domain）——接收 `(视角列表, 时间范围, 布局, 水印位置)`，用 `AVMutableComposition` + `AVVideoComposition` + `CALayer` 生成一个或多个 MP4，写入相册并调起分享。
5. **SwiftUI Views**——纯呈现层，通过 ViewModel 访问 Domain，不直接读文件系统也不直接操作 `AVPlayer`。

**边界约定**：
- Scanner 输出不可变值类型（`TeslaEvent`、`MinuteSegment`）
- PlaybackCtrl 对 UI 只暴露"统一时间轴（秒）"概念，内部负责切换分钟边界
- ExportJob 作为独立后台任务运行，通过 `Progress` 对象向 UI 汇报进度

## 4. 数据模型

所有核心数据类型。放在 `Domain/Models/` 目录下，纯 Swift 结构体，无框架依赖。

```swift
enum CameraAngle: String, CaseIterable, Codable {
    case front
    case back
    case leftRepeater
    case rightRepeater
    case leftPillar
    case rightPillar

    /// 特斯拉 U 盘文件名后缀（不含点和扩展名）
    var fileSuffix: String { ... }

    /// 默认四宫格展示这 4 个
    static var defaultGrid: [CameraAngle] {
        [.front, .back, .leftRepeater, .rightRepeater]
    }
}

enum EventType { case saved, sentry, recent }

/// 一个"分钟切片"——某个时间点下所有可用视角文件的集合
/// 注意：这不是"前视角的某分钟文件"，而是"该分钟点位下，各视角文件的字典"。
struct MinuteSegment {
    let timestamp: Date                     // 切片起始时间（秒级）
    let duration: CMTime                    // 通常 ~60s
    let filesByAngle: [CameraAngle: URL]    // 缺失视角不出现
}

/// 一个事件 = TeslaCam 子文件夹（或 RecentClips 的展平伪事件）
struct TeslaEvent: Identifiable {
    let id: String                          // 文件夹相对路径
    let type: EventType
    let startTime: Date
    let segments: [MinuteSegment]           // 按时间排序
    let availableAngles: Set<CameraAngle>   // 所有 segment 的并集
    let thumbnailURL: URL?                  // thumb.png（若有）
    let eventMetadata: EventMetadata?       // event.json（若有）

    var totalDuration: CMTime { ... }       // 所有 segment 累加
}

struct EventMetadata: Codable {
    let timestamp: Date?
    let city: String?
    let reason: String?
}

/// 时间范围（修剪状态）
struct TrimRange {
    let start: CMTime
    let end: CMTime
    // 不变量: 0 <= start < end <= event.totalDuration
}

/// 导出参数
struct ExportRequest {
    enum Layout {
        case singlesPerAngle(angles: [CameraAngle])  // 每视角一个文件
        case gridCombined(angles: [CameraAngle])     // 合成一个 2×2（期望 4 项）
    }
    enum WatermarkPosition {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    let event: TeslaEvent
    let layout: Layout
    let range: TrimRange
    let watermarkPosition: WatermarkPosition
}
```

**设计要点**：

- **`MinuteSegment` 按"时间点"而非"视角文件"组织**：跨分钟拼接变成对 segments 数组的顺序遍历，视角缺失自然表达为字典键不存在。
- **`availableAngles` 放在事件级别**：UI 一拿到事件就知道视角选择器里该展示哪几个选项。
- **时间分层**：事件级用 `Date`（显示、排序），播放/导出用 `CMTime`（精确到 `AVFoundation` 时间基准）。

## 5. 关键流程数据流

### 流程 A · 扫描 U 盘

```
用户点 "选择 TeslaCam 文件夹"
  → UIDocumentPicker (folder mode)
  → 用户在 Files 里选 U 盘上的 TeslaCam
  → 获得 security-scoped URL，保存 bookmark 到 UserDefaults
  → TeslaCamScanner.scan(folder:)
      ├─ 枚举 RecentClips/*.mp4（展平成单个"最近"伪事件）
      ├─ 枚举 SavedClips/*/
      └─ 枚举 SentryClips/*/
        每个子文件夹：
          - 解析文件夹名 → 起始 Date
          - glob *.mp4 → 按正则解析文件名
          - 同时间戳下不同视角聚成一个 MinuteSegment
          - 读 event.json（若有）
          - 读 thumb.png（若有）
  → 发射 [TeslaEvent]，按 startTime 倒序
  → LibraryStore.events 更新
  → SwiftUI List 渲染（按 Tab 筛选）
```

### 流程 B · 网格播放 & 修剪

```
点列表里的事件
  → Navigate to GridPlayerView(event:)
  → 初始网格 = event.availableAngles ∩ CameraAngle.defaultGrid
  → MultiAVPlayerController(event, angles: grid)
      ├─ 对每个 angle 创建一个 AVMutableComposition（拼接该视角跨所有 MinuteSegment 的文件）
      ├─ 每个 composition 包一个 AVPlayer
      ├─ 使用共享 masterClock 同步 ≤4 个 player
      └─ 暴露统一 currentTime: CMTime
  → 渲染 2×2 网格（UIViewRepresentable 包 AVPlayerLayer）
  → 底部 TrimBar：
      - 缩略图条（AVAssetImageGenerator）
      - 左/右手柄（TrimRange.start/end）
      - 播放头（currentTime）

用户交互：
  - 播放/暂停：所有 player 同步 play/pause
  - 拖播放头：seek all players to same CMTime
  - 拖手柄：更新 TrimRange，播放头跳到手柄位置预览
  - 点某格 → 网格配置 popover → 换视角

点"导出" → sheet 弹出 ExportSheet(event, trimRange, currentGridAngles)
```

### 流程 C · 导出

```
ExportSheet 收集参数：
  ├─ 布局：
  │    - "四宫格合成" → 用当前网格的 4 个视角
  │    - "多视角独立" → 用户从 6 个里勾选 ≥1 个
  ├─ 时间范围：从 TrimRange 继承（可再微调）
  └─ 水印位置：默认左下，四角可选

ExportJob.run(ExportRequest)
  → 根据 Layout 创建一个或多个 AVMutableComposition
  → 配合 AVVideoComposition：
      - singlesPerAngle：原分辨率
      - gridCombined：自定义 instruction 把 4 路缩到 1/4 平铺
      - CALayer 叠加水印（CATextLayer + 时间驱动动画）
  → AVAssetExportSession(preset: .preset1920x1080)
  → Progress → SwiftUI 进度条订阅
  → 完成：
      ├─ PHPhotoLibrary 写入相册
      └─ ActivityViewController 待用户确认后调起分享
  → ExportResult 返回 UI：提示"已保存到相册 · 分享"
```

**设计要点**：

- 播放用的 composition 不复用给导出（导出要加水印层、可能要合成网格，内容不同）
- 水印用 `CALayer.animationTool`，时间戳 `CATextLayer` 以 `CAKeyframeAnimation` 驱动，避免预渲染每帧
- 多视角独立导出并行跑多个 `AVAssetExportSession`（iOS 默认并发上限由系统控制，超出则排队）
- 导出结束立即调用 `stopAccessingSecurityScopedResource()`，避免句柄泄漏

## 6. 错误处理策略

分三层，每层处理方针不同。

### 层 1 · 用户可恢复错误（UI 引导）

| 场景 | 处理 |
|---|---|
| 选错文件夹（不是 TeslaCam 结构） | 空态页："在选中的文件夹里没找到 RecentClips / SavedClips / SentryClips。请选择 U 盘根目录或 TeslaCam 文件夹。" + 重新选择按钮 |
| Security-scoped bookmark 失效 | 启动时检测，引导重新选择 |
| 相册权限被拒 | 非阻塞，生成临时文件后调起分享面板，提示"授权相册后可直接保存" |
| 磁盘空间不足 | 预估输出大小 ≈ 源体积 × 0.7；不足时提示"预计需 X GB，请清理 Y GB 后重试" |

### 层 2 · 数据异常（降级，不中断主流程）

| 场景 | 处理 |
|---|---|
| 事件文件夹损坏（JSON / 时间戳解析失败） | 扫描时 `try?` + 日志，跳过该事件 |
| 某视角文件缺失 | `MinuteSegment.filesByAngle` 无该键；`availableAngles` 自动缺失；UI 网格配置置灰 |
| 分钟文件损坏（`isPlayable == false`） | Composition 跳过该段，播放时该段黑帧 + 底部提示；导出同样跳过 |
| `event.json` 缺失或异常 | `EventMetadata == nil`，列表不显示原因/地点 |
| `thumb.png` 缺失 | 用 `AVAssetImageGenerator` 从 front.mp4 第一秒生成，缓存到沙箱 |

### 层 3 · 不可恢复错误

| 场景 | 处理 |
|---|---|
| AVFoundation 初始化失败 | 错误冒泡到最外层，转本地化文案展示 |
| 内存告警（大事件 + 大网格） | 监听 `didReceiveMemoryWarningNotification` → 暂停播放、释放非可见视角的 player、提示"内存不足，已暂停" |

### 错误反馈机制

用一个 `AppError: LocalizedError` 枚举统一表达：

```swift
enum AppError: LocalizedError {
    case notTeslaCamFolder
    case bookmarkStale
    case photoLibraryDenied
    case diskSpaceInsufficient(needed: Int64, available: Int64)
    case eventCorrupted(id: String, underlying: Error)
    case exportFailed(underlying: Error)
    case memoryPressure
    // ...
    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}
```

UI 层用统一的 `ErrorBanner` / `ErrorAlert` 组件消费 `AppError`，避免到处散落 Alert 代码。

## 7. 测试策略

### 单元测试（XCTest，覆盖率目标 > 80%）

覆盖不依赖文件系统和 AVFoundation 的纯逻辑：

- `CameraAngle.fileSuffix` / `defaultGrid`
- 文件名解析：`"2024-07-15_14-32-01-front.mp4"` → `(Date, CameraAngle)`
- 文件夹名解析：`"2024-07-15_14-32-01"` → `Date`
- `MinuteSegment` 聚合：给 `(Date, CameraAngle, URL)` 元组集合，正确输出 `[MinuteSegment]`
- `availableAngles` 并集计算
- `TrimRange` 边界（手柄不越过彼此、不出事件时长）
- `AppError` 本地化文案

### 集成测试（Scanner + 真实 Fixture）

`Tests/Fixtures/` 下放几个小型 TeslaCam 样本：

- `fixture-6cam-saved/` — 新车 6 路，1 个 SavedClip，3 个 MinuteSegment
- `fixture-4cam-sentry/` — 老车 4 路，2 个 SentryClip
- `fixture-corrupted/` — 损坏 JSON、缺视角、重复时间戳
- `fixture-recent/` — 只 RecentClips 展平片段

MP4 用 `ffmpeg -f lavfi -i testsrc -t 5 ...` 生成的 5 秒小文件，checked in。

### AVFoundation 集成测试（真机跑，不在 CI）

- 4 路同步播放：seek 后时间差 < 100ms
- 导出单视角：分辨率、时长、容器正确
- 导出四宫格：输出分辨率匹配目标、帧数 ≈ 时长 × fps
- 水印存在：导出视频的某帧 OCR 时间戳与源一致

### UI 测试（XCUITest，只覆盖关键路径）

启动 → 选文件夹 → 列表 → 点事件 → 播放 → 拖修剪条 → 导出 → 成功提示。

不测试视觉样式；视觉样式走 SwiftUI Preview 快照审核。

### 不自动化的

- 相册权限弹窗
- AirDrop / 系统分享面板（调起即通过）
- 外接 U 盘拔插时序（手工 checklist）

## 8. 技术选型

| 层面 | 选择 | 理由 |
|---|---|---|
| iOS 最低版本 | 17.0 | 用 `@Observable` 新框架简化状态管理 |
| UI 框架 | SwiftUI 为主 | 代码量小、声明式；播放器 / 时间轴用 `UIViewRepresentable` 桥接 UIKit |
| 视频处理 | AVFoundation | 零外部依赖、硬件加速、App Store 最友好 |
| 状态管理 | `@Observable` | iOS 17 原生 |
| 文件访问 | `UIDocumentPickerViewController` + security-scoped bookmark | 系统标准路径，配转接头访问 U 盘 |
| 测试 | XCTest | 原生 |
| 依赖管理 | SwiftPM | 预计无第三方依赖，仅系统框架 |

**显式拒绝**：

- FFmpeg / FFmpegKit — 依赖体积大、硬件加速需要额外配置、App Store 审核多一层风险，AVFoundation 能覆盖全部需求
- UIKit 纯编码 — SwiftUI 对本项目的列表/表单 UI 已经够用
- 第三方视频播放库 — 没必要

## 9. 模块拆分（预览，详细在实现计划里）

按模块大致的文件边界：

```
TeslaCamViewer/
├── App/                           # App 入口、根 View
├── Domain/
│   ├── Models/                    # CameraAngle, TeslaEvent, MinuteSegment, ...
│   ├── LibraryStore.swift
│   ├── PlaybackController.swift
│   └── ExportJob.swift
├── Infrastructure/
│   ├── TeslaCamScanner.swift
│   ├── MultiAVPlayer.swift
│   ├── AVComposer.swift           # 网格合成 + 水印
│   └── BookmarkStore.swift
├── Features/
│   ├── EventList/
│   ├── GridPlayer/
│   ├── GridConfig/
│   └── ExportSheet/
├── UI/                            # 共享组件（ErrorBanner, TrimBar, ...）
└── Resources/                     # Localizable, Assets
Tests/
├── Unit/
├── Integration/
└── Fixtures/
```

**模块边界检查**：
- 每个模块能独立回答"做什么、怎么用、依赖什么"
- `Domain` 通过协议（`ScannerProtocol`、`PlayerProtocol` 等）依赖 `Infrastructure`，不直接 import 具体类；具体实现在 App 组装层注入
- `Features/*` 只知道 `Domain`，不知道 `Infrastructure`

## 10. 下一步

本文档完成后进入 writing-plans 阶段，产出可执行的实现计划。实现计划将：
- 把每个模块拆成 1-3 天可完成的任务
- 每个任务配 TDD 顺序（先写测试再写实现）
- 指定任务间依赖关系
- 包含 fixture 准备步骤
