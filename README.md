# 圣地巡礼 · Seichi Junrei

一个日本动画「圣地巡礼」主题的 iOS App：

1. **实时发现附近的名场面**：地图和卡片列表里，按距离显示你周围在动画中出现过的地点。
2. **了解这一幕**：点开就能看到对应的动画场景、集数，以及它在剧情中的意义和背景故事。
3. **按作品搜索名场面**：输入日漫、日剧、日影的名字（中文 / 日文 / 英文 / 韩文 / 罗马字都行），地图会自动缩放到这部作品的所有取景地；也可以按「日漫 / 日剧 / 日影」筛选（各语言用当地最常用的叫法）。内置 72 部作品、101 个名场面。
4. **成为那一幕的主角**：走到名场面的“机位”（镜头所在位置）后，App 会打开相机，把名场面画框悬浮在它在真实世界中的方向上。你转身、抬头的时候，画框会慢慢滑向画面中央；对准的那一刻，手机会震动、出现宽银幕黑边和彩纸——“哇，我就站在那一幕里！”
5. **请人帮我拍**：你站到主角的位置当模特，把手机交给同伴（或路人）。App 实时识别画面里的人，一次只给拍照的人一条大字指令（转向、抬头、前进/后退、左右挪、举高/放低），人物大小差一点时自动变焦；对齐后自动倒数 3 秒拍照，拍完再按原作构图自动裁切，把你精确放到主角的位置。指引语言可以单独切换（比如请日本路人帮忙时切成日语）。
6. **导航**：可以选 Google 地图 / Apple 地图 / 高德地图 / 百度地图，也可以在设置里设为默认。

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

## 用户校准机位（CloudKit）

免费公测期的核心目标是用用户的现场数据把机位校准准确：

- 入口：详情页「我在现场，帮忙校准机位」，以及名场面模式底部的「校准机位」。
- 校准页实时显示 GPS 精度、朝向（含误差）、俯仰角、离现有机位的距离，并给出质量提示（`SeichiCore/Calibration.swift`，有单元测试）。
- 提交到 **CloudKit 公共数据库**（容器 `iCloud.com.xianlisi.seichijunrei`，记录类型 `Calibration`），用户无需登录 App；断网或未登录 iCloud 时先保存在本机，下次启动自动补传，也可以复制 JSON 发给开发者。
- 提交内容：位置、朝向、俯仰角、精度、备注、App 版本、语言区域；不含姓名、联系方式、照片。隐私清单已声明「精确位置 · App 功能 · 不关联身份 · 不用于跟踪」，在 App Store Connect 填写隐私标签时保持一致。

**一次性配置（苹果开发者网站 / CloudKit Console）**

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list/cloudContainer) → 右上角筛选切到 **iCloud Containers** → `+` → 填 `iCloud.com.xianlisi.seichijunrei`。
2. 回到 App ID `com.xianlisi.seichijunrei` → 勾选 **iCloud**（选 Include CloudKit support）→ Configure → 勾选上面的容器 → Save。
3. 打开 [CloudKit Console](https://icloud.developer.apple.com) → 选择该容器 → **Development** 环境 → Schema → Record Types → 新建 `Calibration`，添加字段：

   | 字段 | 类型 |
   | --- | --- |
   | `spotID` | String（勾选 Queryable、Sortable） |
   | `latitude` / `longitude` | Double |
   | `location` | Location |
   | `horizontalAccuracy` / `heading` / `headingAccuracy` / `pitch` | Double |
   | `note` / `appVersion` / `locale` | String |
   | `capturedAt` | Date/Time（勾选 Sortable） |

   再在 Indexes 里给 `recordName` 加 Queryable 索引（这样 Console 里才能列出全部记录）。
4. **Deploy Schema Changes…** 部署到 **Production**（TestFlight 和 App Store 版本都写入 Production 环境；没部署时提交会失败并保存在用户手机上，部署后自动补传）。
5. 查看数据：CloudKit Console → Production → Public Database → Records → 类型 `Calibration` → 按 `spotID` 查询。

## 用户投稿（CloudKit）

巡礼者可以给名场面上传现场照片，也可以投稿新的名场面。数据存在同一个 CloudKit 容器的公共数据库，图片用 CKAsset 保存，不需要另外的服务器或对象存储。

**在 CloudKit Console 里新建 3 个记录类型**（先在 Development 建好，再 Deploy Schema Changes 到 Production）：

| 记录类型 | 字段（类型） | 需要的索引 |
|---|---|---|
| `SpotPhoto` | spotID (String), image (Asset), caption (String), status (String), width (Int64), height (Int64), locale (String), appVersion (String) | spotID：Queryable |
| `SceneSubmission` | workTitle, mediaType, sceneTitle, episode, placeName, story, status, locale, appVersion (都是 String)；latitude, longitude, heading, pitch (Double)；location (Location)；photo (Asset) | status：Queryable |
| `Report` | targetType (String), targetID (String), reason (String) | targetID：Queryable |

安全角色保持默认即可（所有人可读、登录 iCloud 的用户可创建、只有创建者可修改）。

**审核**（在 CloudKit Console → Public Database → Records 里操作）：

- 新名场面：`SceneSubmission` 的 `status` 默认是 `pending`，改成 `approved` 后所有人可见，改成 `rejected` 表示不通过（投稿人能在“我的投稿”里看到状态）。
- 照片：先发后管。被 3 位不同用户举报会自动隐藏；确认违规可以把 `status` 改成 `hidden` 或直接删除记录。举报记录在 `Report` 里。
- 设置页的“联系我们”邮箱来自仓库变量 `CONTACT_EMAIL`（Settings → Secrets and variables → Actions → Variables），不写进源码。

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

支持 **简体中文、繁體中文、日本語、English、한국어**。默认跟随系统，也可以在 App 的 **设置 → 语言** 里直接切换，立即生效（不需要去系统设置）。

- 界面文案、权限说明、App 名称：唯一来源是 `tools/l10n.py`，运行 `python3 tools/l10n.py generate` 生成各语言的 `.lproj/*.strings`；`python3 tools/l10n.py check` 会校验 key 是否齐全、占位符是否一致（CI 也会跑）。
- 作品类型用各语言最口语化的叫法：简中「日漫 / 日剧 / 日影」、繁中「動漫 / 日劇 / 日片」、日语「アニメ / ドラマ / 実写映画」、英语「Anime / J-dramas / Movies」、韩语「애니 / 일드 / 일본 영화」；在日本取景的外国电影（如《非诚勿扰》）显示为「电影」。
- 名场面内容：见下面的「圣地数据」。搜索会匹配所有语言的作品名，例如「너의 이름은」「Laid-Back Camp」「灌籃高手」「龙猫」都能找到对应作品。

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

数据源在 `data/sources/*.json`（按日漫 TV / 动画电影 / 吉卜力 / 日影 / 日剧分文件），格式见 [`data/README.md`](data/README.md)。App 读取的 `SeichiJunrei/Resources/catalog.json` 由工具生成，不要手改：

```bash
python3 tools/catalog.py check      # 校验（CI 会跑）
python3 tools/catalog.py build      # 合并 → 繁中自动转换（OpenCC）→ 查询实景照片的作者/许可证 → catalog.json
```

每个名场面除了坐标、机位朝向和到达半径，还有：为什么是名场面、剧情背景（标记是否含剧透）、怎么去、最佳到访时间、巡礼须知，以及作品简介、年份、导演/制作。

> ⚠️ **坐标来自公开资料整理**（自治体/观光局页面、巡礼记录，并用 OpenStreetMap 核对），朝向多为根据地图和画面构图推算，所以全部标记为 `verified: false`。用户在现场可以「校准机位」，数据提交到 CloudKit，之后再合并回 `data/sources`。
>
> ⚠️ **不收录作品截图、剧照和海报**（版权）。详情页的「实景照片」来自 Wikimedia Commons，只使用 CC0 / 公有领域 / CC BY / CC BY-SA 许可的图片，并在页面上标注作者和许可证；作品图标是用主题色 + 作品名首字生成的。用户可以从自己的相册选一张名场面截图（只保存在本机），用于取景叠图和帮拍模式标记主角位置。

## 下一步可以做的

- 接入远程圣地数据库（社区投稿 + 审核），并按区域增量下载
- 巡礼打卡集章、路线规划（一天逛完同一部作品的多个地点）
- 支持横屏的帮拍模式（很多名场面是 16:9 横构图）
- ARKit Geo Tracking（支持的城市可做到更高精度的定位）
