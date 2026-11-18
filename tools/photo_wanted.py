#!/usr/bin/env python3
"""生成 data/photo-wanted.md：每个名场面的“搜原作画面 / 搜实景照片”关键词清单。

  python3 tools/photo_wanted.py

- 搜原作画面：作品原名 + 地名 + “聖地巡礼 比較”。巡礼者常把原作截图和实景并排发出来，
  这样搜到的就是这一幕的原作画面（地点和这一幕必须真的对得上，数据核对见 data/sources）。
- 搜实景照片：日语地名 + 写真，另附“已筛选知识共享许可”的 Google 图片和 Wikimedia Commons 链接。
- 顺序沿用清单里原有的顺序（编号不乱），新加的名场面排在最后，删掉的名场面不再出现。
"""
import json, os, re, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "SeichiJunrei", "Resources", "catalog.json")
OUT = os.path.join(ROOT, "data", "photo-wanted.md")

HEADER = """# 名场面图片征集清单

每个名场面需要两张图：

- **原作画面**（只做对照，不会发给 AI，也不会放进 App）：用“搜原作画面”的词在 Google 图片里搜。
- **实景照片**（AI 生成插画的输入）：用“搜实景照片”的词搜。必须是 **自己拍的**，或 **CC0 / 公有领域 / CC BY / CC BY-SA** 许可（不能是 NC、ND），或 **作者明确授权**。在 Google 图片里点 **工具 → 使用权限 → 知识共享许可** 再挑；也可以点每条下面的现成链接。
- 实景照片最好和原作镜头同一个角度：站在机位上、朝“镜头朝向”拍。

找到后把两张图 + 实景照片的来源链接（或注明“自己拍的”）发给我，并写上编号或 ID。
"""

COMPASS = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]


def trim_place(p):
    return re.split(r"[（(]", p)[0].strip()


def main():
    cat = json.load(open(CATALOG, encoding="utf-8"))
    works = {w["id"]: w for w in cat["works"]}
    spots = {s["id"]: s for s in cat["spots"]}
    old = re.findall(r"^- ID：`([^`]+)`", open(OUT, encoding="utf-8").read(), re.M) if os.path.exists(OUT) else []
    order = [i for i in old if i in spots] + sorted(i for i in spots if i not in old)
    out = [HEADER]
    for n, sid in enumerate(order, 1):
        s, w = spots[sid], works[spots[sid]["workID"]]
        zh, ja = s["text"]["zh-Hans"], s["text"].get("ja", {})
        badge = {"anime": "日漫", "animeFilm": "日漫", "drama": "日剧", "film": "日影"}[w["mediaType"]]
        if w["mediaType"] == "film" and w.get("country") not in (None, "JP"):
            badge = "电影"
        zh_title = (w["text"].get("zh-Hans") or {}).get("title") or w["title"]
        ja_place = trim_place(ja.get("placeName") or zh["placeName"])
        frame_q = f"{w['title']} {ja_place} 聖地巡礼 比較"
        photo_q = f"{ja_place} 写真"
        enc = urllib.parse.quote(ja_place)
        heading = COMPASS[int(((s["sceneHeading"] % 360) + 22.5) // 45) % 8]
        photo = s.get("photo")
        cur = f"　·　[现在用的照片]({photo['pageURL']})" if photo and photo.get("pageURL") else "　·　还没有实景照片"
        out.append(f"""## {n}. {badge}《{zh_title}》{zh['sceneTitle']}

- ID：`{sid}`
- 地点：{zh['placeName']}　·　镜头朝向：面向{heading}{cur}
- 搜原作画面：

  ```
  {frame_q}
  ```
- 搜实景照片：

  ```
  {photo_q}
  ```
- 现成链接：[Google 图片·已筛选知识共享许可](https://www.google.com/search?tbm=isch&tbs=sur:cl&q={enc})　·　[Wikimedia Commons](https://commons.wikimedia.org/w/index.php?search={enc}&title=Special:MediaSearch&type=image)
""")
    open(OUT, "w", encoding="utf-8").write("\n".join(out))
    print(f"已生成 {os.path.relpath(OUT, ROOT)}：{len(order)} 个名场面")


if __name__ == "__main__":
    main()
