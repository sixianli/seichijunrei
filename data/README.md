# 名场面数据（source of truth）

App 读取的 `SeichiJunrei/Resources/catalog.json` 由本目录生成，不要手改：

```
python3 tools/catalog.py check  data/sources/<file>.json   # 校验单个来源文件
python3 tools/catalog.py build                              # 合并全部来源 → catalog.json（含繁中转换、图片版权信息）
```

每个来源文件 `data/sources/*.json` 结构：`{"works": [Work...], "spots": [Spot...]}`。
同一部作品只能在一个文件里定义；spot 的 `workID` 可以引用任意文件里的作品。

## Work（作品）

| 字段 | 说明 |
|---|---|
| `id` | 小写英文 + 连字符，例如 `totoro` |
| `title` | 日文原名（官方表记），如 `となりのトトロ` |
| `mediaType` | `anime`（TV 动画）/ `animeFilm`（动画电影）/ `film`（真人电影）/ `drama`（电视剧） |
| `year` | 首播 / 上映年份（整数） |
| `creator` | 日文署名：导演 / 制作公司（电视剧写电视台或平台 + 编剧），如 `宮崎駿 / スタジオジブリ` |
| `tint` | 主题色 `#RRGGBB`，取作品代表色 |
| `aliases` | 搜索用别名：英文名、罗马字、各语言常用译名、简称、导演/主演名 |
| `officialURL` | 可选，官方网站 |
| `text` | 各语言文案，键 `zh-Hans` `zh-Hant` `ja` `en` `ko`，见下 |

`text.<lang>`：
- `title`：该语言最常用的正式译名（大陆用大陆译名《千与千寻》，繁中用台湾译名《神隱少女》，韩语用韩国上映名，英语用官方英文名）。`ja` 留空字符串 `""`（直接显示原名）。
- `creator`：该语言写法（如 `宫崎骏 / 吉卜力工作室`）。`ja` 可省略。
- `synopsis`：作品简介 2–3 句，**不剧透**。（`zh-Hant` 可省略，构建时由简中自动转换。）

`zh-Hant` 只需要给 `title`（台湾通行译名），其余字段构建时从简中转换。

## Spot（名场面）

| 字段 | 说明 |
|---|---|
| `id` | 小写英文 + 连字符，`<作品>-<地点>`，如 `totoro-sayama-hills` |
| `workID` | 对应 Work 的 `id` |
| `latitude` `longitude` | **用户应该站的位置**（复现镜头的机位），WGS84，至少 5 位小数 |
| `sceneHeading` | 镜头朝向：从机位看出去的方位角，正北为 0，顺时针（0..<360） |
| `scenePitch` | 可选，俯仰角：仰视为正、俯视为负（-30…45） |
| `arrivalRadius` | 到达判定半径（米），通常 30–80；大面积景点可到 150 |
| `spoiler` | `story` 是否含剧透（结局、角色生死、关键反转等）→ true |
| `sourceURL` | 坐标/取景地依据的出处（官方观光页、自治体、可靠的巡礼记录等） |
| `photo` | 可选。**真实地点**的 Wikimedia Commons 照片文件名，如 `File:Suga Shrine stairs.jpg`；只接受 CC0 / PD / CC BY / CC BY-SA。不要用动画截图、海报 |
| `verified` | 固定写 `false`（只有实地校准后才改） |
| `text` | 各语言文案，键 `zh-Hans` `ja` `en` `ko`（`zh-Hant` 自动转换，可省略） |

`text.<lang>`：
- `placeName`：地点名 +（城市·区域），如 `須賀神社 男坂（东京·四谷）`
- `sceneTitle`：名场面标题，简短（中文 ≤16 字）
- `episode`：出现位置，如 `第1话`、`剧场版 · 结尾`、`第3集`；不确定时写到能确认的粒度
- `highlight`：**为什么这一幕是名场面**，1–2 句（中文 40–100 字）
- `story`：剧情背景——这一幕之前发生了什么、角色此刻的心情、这一幕之后的意义（中文 150–300 字）
- `access`：怎么去：最近车站 + 步行分钟数 / 公交（中文 20–80 字）
- `bestTime`：最佳到访时间：季节、时段、光线（中文 15–60 字）
- `tips`：巡礼须知：礼仪、开放时间、门票、私人土地等（中文 20–100 字）

语言要求：每种语言都写成该语言母语者自然的说法，不要直译腔；人名、作品名用各地区通行译名。
