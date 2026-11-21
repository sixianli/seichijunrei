# 圣地巡礼 · Seichi Junrei

一款日本动画、日剧、日影「圣地巡礼」主题的 iOS App：在地图上找到附近的名场面取景地，走到当年的镜头位置，用相机对准那一幕并拍照留念。

## 主要功能

- **发现附近的名场面**：地图和列表按距离显示你周围在作品中出现过的地点；后台定位设为“始终允许”时，靠近最近的 20 个圣地会收到通知。
- **了解这一幕**：每个名场面有对应的作品、集数、剧情背景（标注是否剧透）、怎么去、最佳到访时间和巡礼须知。
- **按作品搜索**：用中文、日文、英文、韩文或罗马字输入作品名，地图会缩放到这部作品的全部取景地；也可以按「日漫 / 日剧 / 日影」筛选。内置 79 部作品、102 个名场面。
- **对准名场面**：走到镜头所在的位置后打开相机，名场面画框浮在它在现实中的方向上，App 提示你转身、抬头；对准时手机震动并播放庆祝动画。
- **请人帮我拍**：把手机交给同伴，App 识别画面里的人，一次给拍照的人一条指令（转向、抬头、前进后退等），对齐后自动倒数拍照，并按原作构图裁切。
- **分享卡**：生成一张“作中 vs 现实”的竖版对比图，可保存到相册或分享到社交平台。
- **校准与投稿**：在现场可以帮忙校准机位、上传现场照片、投稿新的名场面。
- **导航**：可选 Google 地图、Apple 地图、高德地图或百度地图。
- **多语言**：简体中文、繁體中文、日本語、English、한국어，可以在 App 的设置里直接切换。

## 系统要求

- iPhone，iOS 17 或更高版本（指南针和相机需要真机）
- 构建需要 macOS、Xcode 26 或更高版本，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（一个按 `project.yml` 生成 Xcode 工程的工具）

## 从源码构建

```bash
brew install xcodegen
xcodegen generate
open SeichiJunrei.xcodeproj
```

在 Xcode 里选择自己的开发者 Team，然后连接 iPhone 运行。

修改代码、名场面数据或多语言文本前，请先读 [开发说明](docs/development.md)。

## 项目结构

```
SeichiJunrei/          App 源码（界面、定位与相机服务、资源）
Packages/SeichiCore/   与平台无关的核心逻辑（方位计算、转身指引、搜索等）及单元测试
SeichiJunreiUITests/   端到端测试
data/                  名场面数据源（格式见 data/README.md）
tools/                 数据生成、多语言和校验脚本
docs/                  开发说明
```

## 已知限制

- 坐标来自公开资料整理，机位朝向多为根据地图和画面构图推算，尚未全部在现场核实。
- App 不收录作品截图、剧照和海报。详情页的实景照片来自 Wikimedia Commons，并标注作者和许可证；对比图里的原作截图由用户从自己的相册选择，只保存在本机。

## 版权

© 2026 sixianli. 保留所有权利。本仓库源码仅供在 GitHub 上浏览，未经作者书面许可，禁止复制、修改、分发或用于任何用途（包括上架应用商店）。

© 2026 sixianli. All rights reserved. This source code is published for viewing on GitHub only. No permission is granted to copy, modify, distribute, or use it for any purpose (including publishing to app stores) without the author's prior written consent.
