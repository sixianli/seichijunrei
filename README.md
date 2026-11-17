# 圣地巡礼 · Seichi Junrei

一个日本动画「圣地巡礼」主题的 iOS App：

1. **实时发现附近的名场面**：地图和卡片列表里，按距离显示你周围在动画中出现过的地点。
2. **了解这一幕**：点开就能看到对应的动画场景、集数，以及它在剧情中的意义和背景故事。
3. **按作品搜索名场面**：输入动画、电影或电视剧的名字（中文 / 日文 / 英文 / 罗马字都行），地图会自动缩放到这部作品的所有取景地；也可以按「动画 / 动画电影 / 电影 / 电视剧」筛选。
4. **成为那一幕的主角**：走到名场面的“机位”（镜头所在位置）后，App 会打开相机，把名场面画框悬浮在它在真实世界中的方向上。你转身、抬头的时候，画框会慢慢滑向画面中央；对准的那一刻，手机会震动、出现宽银幕黑边和彩纸——“哇，我就站在那一幕里！”

## 体验流程

```
地图/附近列表 ──点击──▶ 名场面详情（剧情、小贴士、距离）
      │                         │
      │ 进入机位半径              ▼
      └──顶部横幅──▶ 名场面模式
                    ├─ 未到达：大箭头指向圣地 + 距离（实时随朝向旋转）
                    └─ 已到达：相机取景 + AR 画框 + “向左转 35°/再抬头 10°”
                               └─ 对准并稳定 0.8 秒 ▶ 庆祝动画 + 拍照留念
```

后台定位授权为“始终允许”时，App 会对最近的 20 个圣地做地理围栏监控，靠近时推送通知。

## 设计：Liquid Glass

界面遵循 iOS 26 引入、iOS 27 继续改进的 **Liquid Glass** 设计语言和 Apple Human Interface Guidelines：

- **玻璃只用于控制层**：地图上的类型筛选、聚焦提示、到达横幅，名场面模式里浮在相机画面上的按钮、标题和转身指引 HUD。名场面卡片、列表、正文、分享卡等**内容保持实底**。
- 相邻的玻璃元素放进同一个 `GlassEffectContainer`，避免玻璃叠玻璃；可点击的玻璃控件带 `interactive` 按压反馈。
- 主要操作（进入名场面、拍照留念、分享）用带主题色的 `.glassProminent`，次要操作用 `.glass`。
- 导航栏、工具栏、搜索框、sheet、分段控件等系统控件用新 SDK 编译后自动呈现 Liquid Glass。
- 辅助功能：触控区域 ≥ 44pt；开启「减弱动态效果」时关闭彩纸、箭头晃动、脉冲动画；降低透明度 / 增强对比度由系统玻璃自动适配；标题使用动态字体。
- 兼容性：部署目标仍为 iOS 17。`Views/Glass.swift` 在 iOS 26+ 使用 `glassEffect` / `.glass` 按钮样式，在旧系统自动退回 Material 和标准按钮样式。需要用 **Xcode 26 或更新版本**编译。

## 巡礼分享卡

对准名场面的那一刻会自动记为「巡礼达成」（日期、朝向、位置都只保存在本机）。在名场面模式里点 **拍照留念**，或在详情页点 **分享**，就会生成一张竖版分享卡（1080×1350）：

- **作中 vs 现实**：上半张是你添加的名场面截图，下半张是现场照片（巡礼圈最经典的对比图）；没有截图时用「现场照片」单张版式
- 作品名、场景名、地点、到达日期、坐标与朝向，以及一枚「巡礼达成」印章
- 通过系统分享面板同时分享图片和配文（含 `#圣地巡礼 #君の名は` 等话题标签），可发到 X、Instagram、LINE、微信等；也能直接保存到相册
- 文案随界面语言切换（5 种语言）

选择图片而不是网页的原因：图片在所有社交平台和聊天软件里都能直接以大图显示，不依赖链接预览，也不需要服务器存储用户照片。以后有后端时，可以在卡片上附加一个可选的网页链接。

## 收费模式

> **当前处于免费公测期：收费已关闭**（`project.yml` 中 `SEICHI_PAYWALL_ENABLED: "NO"`），名场面模式不限次数，不显示付费墙。等用户校准的数据让体验足够好后，把它改为 `"YES"` 并发布新版本即可开启下面的收费模式（届时需要先在 App Store Connect 创建内购商品）。

免费下载 + 免费体验 + 旅行通行证 / 终身买断（不做自动续费订阅）：

| 档位 | 内容 | 商品 ID（StoreKit） | 测试价格 |
| --- | --- | --- | --- |
| 免费 | 地图、搜索、剧情介绍、方向指引；名场面取景模式可免费体验 **3 处不同的名场面**（同一处重复进入不扣次数） | — | 0 |
| 7 天旅行通行证 | 不限次数的名场面取景、对准庆祝、拍照 | `com.xianlisi.seichijunrei.pass7`（非续期订阅） | $2.99 |
| 30 天旅行通行证 | 同上 | `com.xianlisi.seichijunrei.pass30`（非续期订阅） | $4.99 |
| 终身解锁 | 永久解锁 | `com.xianlisi.seichijunrei.lifetime`（非消耗型） | $14.99 |

- 通行证到期不会自动扣费；连续购买会顺延（从上一张的到期时间开始计算）。
- 权益根据 StoreKit 2 的完整交易记录计算，退款后的交易会被排除；付费墙里有“恢复购买”。
- 本地测试：`SeichiJunrei.storekit` 已挂到 Run scheme，在模拟器里运行即可模拟购买；`SeichiJunreiTests` 用 StoreKitTest 跑真实的购买、顺延、恢复、退款流程。
- 上架前：在 App Store Connect 用上面的商品 ID 创建商品（或改 `StoreProductID`），加入 Small Business Program（抽成 15%），并在 App 描述里写清楚通行证不自动续费。

## 发布到 TestFlight（GitHub Actions）

工作流 `.github/workflows/testflight.yml`：在 GitHub 上手动触发，CI 会用 App Store Connect API 密钥自动签名、打包 Release 版并上传，构建号自动递增（`github.run_number`）。

**一次性准备（在苹果网站上）**

1. **注册 Bundle ID**：[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → Identifiers → `+` → App IDs → 填 `com.xianlisi.seichijunrei`（In-App Purchase 能力默认开启）。
2. **创建 App 记录**：[App Store Connect](https://appstoreconnect.apple.com) → 我的 App → `+` 新建 App → 平台 iOS，选择上面的 Bundle ID，SKU 随意（如 `seichijunrei`）。App 名称在 App Store 中必须唯一。
3. **创建 API 密钥**：App Store Connect → 用户和访问 → 集成 → App Store Connect API → 团队密钥 → `+`，访问权限选 **管理（Admin）**（CI 需要用它创建云端托管的分发证书）。下载 `.p8` 文件（只能下载一次），记下 **密钥 ID** 和页面上方的 **Issuer ID**。
4. **查看 Team ID**：[developer.apple.com/account](https://developer.apple.com/account) → 会员资格详细信息。

**在 GitHub 仓库里配置**（Settings → Secrets and variables → Actions）

| 类型 | 名称 | 值 |
| --- | --- | --- |
| Secret | `APP_STORE_CONNECT_API_KEY_ID` | 密钥 ID |
| Secret | `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| Secret | `APP_STORE_CONNECT_API_KEY` | `.p8` 文件的全部内容（含 BEGIN/END 两行） |
| Variable | `APPLE_TEAM_ID` | Team ID（10 位） |

也可以用简写名 `ASC_KEY_ID`、`ASC_ISSUER_ID`、`ASC_KEY_P8`。Secret 是加密保存的，不会出现在日志里；公开仓库被 fork 后发起的 PR 也拿不到。这个工作流只能由有写权限的人手动触发。

**发布**：Actions → TestFlight → Run workflow → 填版本号（如 `0.1.0`）→ 运行。成功后，苹果通常会在 5–30 分钟内处理完构建；然后在 App Store Connect 的 TestFlight 页面把自己加为内部测试员，用 iPhone 上的 TestFlight App 安装即可。没有配置密钥时，工作流只做一次不签名的打包演练，并在运行摘要里列出缺少的配置。

> 内购商品需要在 App Store Connect →「App 内购买项目」里按上面「收费模式」中的商品 ID 创建；TestFlight 中的购买走沙盒环境，不会真的扣款。

## 多语言

支持 **简体中文、繁體中文、日本語、English、한국어**，跟随系统语言；其他语言回退到英语。

- 界面文案、权限说明、App 名称：唯一来源是 `tools/l10n.py`，运行 `python3 tools/l10n.py generate` 生成各语言的 `.lproj/*.strings`；`python3 tools/l10n.py check` 会校验 key 是否齐全、占位符是否一致（CI 也会跑）。
- 名场面内容：`spots.json` 的基础字段是简体中文，每条记录的 `translations` 里放其他语言的作品译名、地点、标题、剧情、小贴士。搜索时会匹配所有语言的作品名，例如输入「너의 이름은」「Laid-Back Camp」「灌籃高手」都能找到对应作品。

## 技术要点

| 模块 | 说明 |
| --- | --- |
| `Packages/SeichiCore` | 与平台无关的纯 Swift 逻辑，**可在 Linux/macOS 上单元测试**：距离/方位角（haversine）、转身指引、防抖锁定、罗盘平滑、摄像头朝向融合、取景器投影 |
| `CameraOrientation` | 用 CoreMotion 的**重力向量 + 已校准磁场**直接计算“背面摄像头光轴”的方位角和仰角。竖起手机拍照时比 `CLHeading`（以手机顶部为准）更稳定；摄像头接近垂直时自动退回手机顶部方向 |
| `SceneGuidance` | 计算需要转动的有符号角度（自动处理 359°→1° 跨越），罗盘精度差时会自动放宽容差 |
| `AlignmentLatch` | 对准需保持 0.8 秒才触发；带迟滞，避免在阈值边缘来回闪烁 |
| `SpotSearch` | 按作品名搜索：大小写、全角/半角、平假名/片假名互通，忽略「。☆！△」等符号和空格，支持别名（如 `Your Name` / `你的名字` / `kimi no na wa`）。作品名命中时返回该作品全部名场面，只命中地点/场景名时只返回对应地点 |
| `ViewfinderProjection` | 根据相机真实视场角（含 aspect-fill 裁切）把名场面方向投影到屏幕坐标，实现轻量 AR 画框 |
| App 层 | SwiftUI + MapKit（iOS 17 `Map` API）+ Observation、AVFoundation 相机、UserNotifications 地理围栏通知、触感反馈“越接近震得越密” |

## 运行

需要 macOS + Xcode 26 以上（也可以不用 Mac，直接用下面的 GitHub Actions 发布到 TestFlight），以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
open SeichiJunrei.xcodeproj
```

在 Xcode 里选择你的开发团队后，即可在真机上运行（指南针、相机都需要真机）。

**不在日本也能调试**：Debug 构建中，详情页底部有“（调试）模拟站在这个机位”，名场面模式里有“记录机位”按钮。后者会把当前的经纬度、朝向和俯仰角复制成 JSON 片段，方便在现场校准数据。

核心逻辑测试：

```bash
cd Packages/SeichiCore && swift test
```

## 圣地数据

数据在 `SeichiJunrei/Resources/spots.json`，每条记录的结构如下：

```jsonc
{
  "id": "yurucamp-motosu",
  "work": "ゆるキャン△", "workLocalized": "摇曳露营△",
  "mediaType": "anime",                        // anime | animeFilm | film | drama
  "aliases": ["Yuru Camp", "Laid-Back Camp"],  // 搜索用别名
  "placeName": "本栖湖 浩庵露营场（山梨·身延町）",
  "sceneTitle": "夜空下的富士山", "episode": "第1話",
  "story": "……剧情背景……", "trivia": "……巡礼礼仪/小知识……",
  "latitude": 35.4648, "longitude": 138.588,   // 机位：站在这里
  "sceneHeading": 132.5,                       // 镜头朝向，真北顺时针（度）
  "scenePitch": 5,                             // 镜头仰角（可选）
  "arrivalRadius": 60,                         // 到达判定半径（米）
  "sceneImage": null,                          // Asset 名或 https URL（需有授权）
  "verified": false,                           // 是否已实地校准
  "tint": "#3E8E5E"
}
```

> ⚠️ **内置的 17 个示例圣地（动画 14 个、真人电影 1 个、电视剧 2 个），坐标都是大致位置，朝向/俯仰多为估计值**（只有本栖湖一条的朝向是根据坐标指向富士山顶算出来的），所以都标记为 `verified: false`。上线前请去现场用“记录机位”功能校准。
>
> ⚠️ **动画截图有版权**。仓库里没有附带任何截图，没有图片时会显示一张插画风的占位图。正式使用请取得版权方授权，或与官方/地方政府的巡礼合作项目对接后，再填写 `sceneImage`。
>
> 在此之前，用户可以在详情页 **「添加名场面截图」**，从自己的相册里选一张截图（只保存在本机），到达机位后它会半透明地叠加在相机画面上，帮你对准同一个构图；也可以点 **「网上搜这一幕」** 去查看对比图。
>
> 坐标已经用 OpenStreetMap（Nominatim）核对过；「西宫北高」在 OSM 里没有找到，所以它的到达半径设得比较大。

## 下一步可以做的

- 接入远程圣地数据库（社区投稿 + 审核），并按区域增量下载
- 名场面截图与实拍照片“对比/叠图”分享卡片
- 巡礼打卡集章、路线规划（一天逛完同一部作品的多个地点）
- 日语/英语本地化（String Catalog）
- ARKit Geo Tracking（支持的城市可做到更高精度的定位）
