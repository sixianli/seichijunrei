# 交接文档（Handoff）

更新时间：2026-11-20 · main 最新合并：PR #16（`4571098`）

新线程开始前请先完整读一遍本文件和 `README.md`。

---

## 0. 和用户协作的规则（必须遵守）

- **只用简体中文回复。** 用户明确说过“禁止用英文回答我”。
- **main 分支的合并由你来做。** PR 的 CI 全绿后，自己把 PR 标为就绪并合并。需要发 TestFlight 时由你触发，发完告诉用户。
- **E2E 不通过，不得发 TestFlight。** 每个功能路径都要有端到端测试覆盖，新功能必须同时补上 E2E。发布流程 `testflight.yml` 里的 `e2e-gate` 会检查同一个提交的 CI，没通过就拒绝发布。不要绕过它，不要跳过或禁用测试来换绿灯。
- **收集反馈的流程：**
  1. 用户一条条发问题，你先记下来。
  2. 用户说“反馈完了 / 以上就是这一波”后，把所有要确认的问题一次性用 AskUserQuestion 卡片发给用户。如果卡片发不出去，就在文字里列出来。
  3. 实现、充分测试（含 5 种语言截图检查），然后发版。
- **多语言必须逐个检查：** 简中、繁中、日、英、韩，每个组件、每个页面都要截图检查，不能有文字溢出、按钮被挤压。用户对这一点非常在意。
- **需要先问用户的事：**
  - 提交 App Store 审核、开启收费；
  - 花钱的批量 AI 生成（插画要攒够 10 张，或用户说“先处理”）。
- **隐私与安全：**
  - 不要在聊天里要密钥，密钥只能通过 request_credential 获取。
  - 用户邮箱是隐私，只存在仓库变量 `CONTACT_EMAIL` 里，不要写进代码或文档。
  - 用户自己拍的照片绝不能放进 App 或仓库。
- **版权：**
  - 原作截图和第三方受版权保护的照片，绝不能发给 AI。
  - 原作截图只用来人工对照角度。
- **收录标准：** 只收全球知名的作品、广为人知的名场面，地点必须确认过或被广泛引用，不凑数。名场面分两类分别标注：
  - `scene`：名场面·取景地；
  - `landmark`：官方圣地。

---

## 1. 当前状态

- **TestFlight：** 最新是 0.6.2（PR #15）。
- **main 上还没发 TestFlight 的改动（PR #16）：**
  - 新增 E2E 测试，并给 TestFlight 加了发布关卡。
  - 修复：模拟器里进名场面模式时相机启动崩溃；真机上没拿到摄像头时也不再启动相机。
  - 修复：投稿页填过内容后，下滑不会再把整页关掉；滑动时自动收起键盘。
  - 修复：「我的投稿」整行作为一个可访问元素，左滑可以删除。
- **下一版版本号：** 0.6.3。用户没有要求单独发这一版，计划和下一轮反馈或新功能一起发。
- **CI 测试规模：**
  - SeichiCore 单元测试；
  - Release 真机包编译；
  - 43 个 UI 测试：`SmokeUITests` 25 个（含 5 种语言截图巡检）+ `FeatureE2ETests` 18 个。

---

## 2. 未完成的任务

### A. 插画素材（等用户发图）

用户会成对发图，每对带编号：原作画面（只做对照）+ 自己拍的实景照片。

- **需要重发（上次没收到图片文件）：**
  - 第 11 张：`hyouka-minashi-jinja`
  - 第 12 张：`haruhi-kitakou`
  - 第 21 张：`koenokatachi-shin-ohashi`
  - 第 22 张：`summerwars-ueda-castle`
  - 第 33 张：`mononoke-shiratani-moss-forest`
- **第 36 张 `ponyo-tomonoura-joyato`：** 收到过，但照片只存在上一个线程的临时目录里，已经丢失。**需要请用户在新线程重发。** `data/photo-status.json` 里它仍记在 `received`，用户重发后保持不变即可。
- **生成规则：**
  - 攒够 10 张（或用户说“先处理”）才批量生成。
  - 怪物之子不做夜景版，只用白天版。
- **生成前的处理：**
  1. 用 `tools/cover_signs.py` 盖掉带字的招牌和商标。
  2. 去掉画面里的人。
  3. 再用 `tools/illustrate.py` 生成（Vercel AI Gateway，`openai/gpt-image-2`；密钥由代理注入）。
- **用户照片：** 只放在临时目录（scratchpad），绝不提交到仓库。
- **状态维护：** 每次收到或生成后，更新 `data/photo-status.json`，再运行 `python3 tools/photo_wanted.py` 重新生成 `data/photo-wanted.md`。编号固定在 `data/photo-numbers.json`，不要改已有编号。
- **素材清单 `photo-wanted.md` 的格式要求（用户提的）：**
  - 每个名场面给中、日、英三种搜索词；
  - 每条搜索词都要包含作品名 + 地点或建筑 + 名场面名字。

### B. 新名场面配图（长期）

第 103–135 张还没有插画，随用户发图逐步补。

### C. 发布 0.6.3（有新内容时）

1. 新功能或新反馈改完后开 PR，CI 全绿再合并。
2. 触发 `testflight.yml`，参数 `marketing_version=0.6.3`。
3. `e2e-gate` 会等合并提交的 CI 结果；通过后才上传。
4. 上传完成后告诉用户。

### D. 测不到的地方（已知限制，告诉过用户）

- 系统付款弹窗：购买逻辑由 StoreKitTest 单元测试覆盖。
- 真实的后台地理围栏推送：只测了“点通知回到指引”。
- 真机相机画面和 Vision 的识别效果。

---

## 3. 关键技术信息

### 工程与本地检查

- **工程：** SwiftUI，iOS 17+，用 XcodeGen 生成工程（`project.yml`）。
- **SeichiCore 测试（Linux 可跑）：** `cd Packages/SeichiCore && swift test`。Swift 工具链在 `/opt/swift/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin`；新容器里可能没有，可以只依赖 CI。
- **多语言文案：** 唯一来源是 `tools/l10n.py`。运行 `python3 tools/l10n.py generate` 生成，用 `check` 校验（CI 也会跑）。
- **数据：**
  - 源数据在 `data/sources/*.json`，运行 `python3 tools/catalog.py build` 生成 `SeichiJunrei/Resources/catalog.json`。不要手改 catalog.json。
  - 各语言的 `searchTerms` 条数必须一致（按下标一一对应），不一致时 catalog.py 会报错。

### UI 测试

- **测试开关**（只在 Debug 构建且 `SEICHI_UITEST=1` 时生效）：见 `SeichiJunrei/Services/TestHooks.swift`。
  - 选图时直接给一张模拟照片。
  - 外部链接不跳出 App，地址记录到 `debugLastURL` 标签。
  - `SEICHI_MODERATION` 指定审核结果。
  - `SEICHI_RESET_PREFS` 清掉帮拍相关的偏好。
- **其他环境变量：**
  - 模拟位置与姿态：`SEICHI_SIM_LAT/LON/HEADING/PITCH`、`SEICHI_SIM_SUBJECT`、`SEICHI_SIM_SCENE_IMAGE`。
  - 启动后直接打开页面：`SEICHI_OPEN_SPOT`、`SEICHI_OPEN_JOURNEY`。
  - 模拟社区与投稿：`SEICHI_FAKE_SUBMIT`、`SEICHI_FAKE_COMMUNITY`。
  - 付费状态：`SEICHI_ENTITLEMENT`、`SEICHI_PAYWALL`、`SEICHI_FREE_USED`。
- **测试公共工具：** `SeichiJunreiUITests/UITestBase.swift`。
  - `launch`、`launchAtDetail`；
  - `scrollTo`：先往下翻再往回翻，目标被键盘挡住时会先收起键盘；
  - `dismissKeyboard`、`lastOpenedURL`、`snapshot`。
- **踩过的坑：**
  - `@AppStorage` 的偏好会在测试之间残留，需要在 `TestHooks.resetPreferencesIfNeeded` 里清掉。
  - 用启动参数 `-key value` 设置偏好时，会把 App 运行中写入的值也盖住（NSArgumentDomain 优先）。所以要测“设置后生效”的偏好，不能用启动参数覆盖。
  - 被键盘盖住的元素，XCUITest 仍会认为“可点”。

### 查 CI 失败

- **查看日志：** `gh api repos/sixianli/seichijunrei/actions/jobs/<job_id>/logs | grep -E "error:|FAIL "`。
- **截图和录屏：**
  1. 下载 artifact `ui-screenshots`：`gh api .../actions/artifacts/<id>/zip`。
  2. 解压后用 `manifest.json` 里的 `suggestedHumanReadableName` 对应文件。
  3. 崩溃日志是 `.ips` 文件。
  4. 录屏 `.mp4` 可以用 ffmpeg 拼成缩略图拼图来看。
- **注意：** 一次 artifact 约 500 MB，看完删掉。

### 发布

- **TestFlight：** `.github/workflows/testflight.yml`（workflow_dispatch，输入 `marketing_version`）。先跑 `e2e-gate`，再跑 `upload`。
- **开发分支：** 各线程按系统给的分支名开发；PR 合并后，把分支重置到最新的 main。
