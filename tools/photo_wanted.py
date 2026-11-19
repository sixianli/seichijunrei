#!/usr/bin/env python3
"""生成 data/photo-wanted.md：每个名场面的“搜原作画面 / 搜实景照片”关键词清单（中、日、英三种）。

  python3 tools/photo_wanted.py

- 编号固定（data/photo-numbers.json）：已有的名场面永远用同一个号，新加的接在最大号后面，
  删掉的名场面空着号不复用。发图时说“第 N 张”不会因为增删名场面而对不上。
- 搜原作画面：作品名 + 地点（建筑物）+ 名场面关键词 + 巡礼词；备用一条用“作品名 + 名场面名字”。
  巡礼者常把原作截图和实景并排发出来，这样搜到的就是这一幕的原作画面。
- 搜实景照片：日文 / 英文地名 + 写真 / photo，另附“已筛选知识共享许可”的 Google 图片和 Wikimedia Commons 链接。
- 状态：已有插画的标“✅ 已有插画”，不用再找；data/photo-status.json 里记着“已收到待生成”“需要重发”的编号。
"""
import json, os, re, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "SeichiJunrei", "Resources", "catalog.json")
NUMBERS = os.path.join(ROOT, "data", "photo-numbers.json")
STATUS = os.path.join(ROOT, "data", "photo-status.json")
OUT = os.path.join(ROOT, "data", "photo-wanted.md")

PILGRIMAGE = {"ja": "聖地巡礼 比較", "zh-Hans": "圣地巡礼 对比", "en": "anime pilgrimage real life comparison"}
PILGRIMAGE_LIVE = {"ja": "ロケ地 比較", "zh-Hans": "取景地 对比", "en": "filming location then and now"}
COMPASS = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
LANG_NAME = {"ja": "日文", "zh-Hans": "中文", "en": "英文"}


def trim_place(p):
    return re.split(r"[（(]", p)[0].strip()


def join_unique(parts):
    """拼搜索词，去掉已经被前面包含的重复词"""
    out = []
    for p in parts:
        p = (p or "").strip()
        if not p:
            continue
        flat = " ".join(out).replace(" ", "").lower()
        if p.replace(" ", "").lower() in flat:
            continue
        out.append(p)
    return " ".join(out)


def work_title(w, lang):
    if lang == "ja":
        return w["title"]
    return ((w.get("text") or {}).get(lang) or {}).get("title") or w["title"]


def main():
    cat = json.load(open(CATALOG, encoding="utf-8"))
    works = {w["id"]: w for w in cat["works"]}
    spots = {s["id"]: s for s in cat["spots"]}
    numbers = json.load(open(NUMBERS, encoding="utf-8")) if os.path.exists(NUMBERS) else {}
    status = json.load(open(STATUS, encoding="utf-8")) if os.path.exists(STATUS) else {}
    nxt = max(numbers.values(), default=0) + 1
    for sid in spots:                       # 新名场面按 catalog 里的顺序接着编号
        if sid not in numbers:
            numbers[sid] = nxt
            nxt += 1
    json.dump(dict(sorted(numbers.items(), key=lambda x: x[1])), open(NUMBERS, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    received = set(status.get("received", []))
    resend = set(status.get("resend", []))
    live = [(numbers[sid], sid) for sid in spots]
    live.sort()

    def title_of(sid):
        s, w = spots[sid], works[spots[sid]["workID"]]
        return f"《{work_title(w, 'zh-Hans')}》{s['text']['zh-Hans']['sceneTitle']}"

    head = ["# 名场面图片征集清单", "",
            "每个名场面需要两张图：", "",
            "- **原作画面**（只做对照，不会发给 AI，也不会放进 App）：用“搜原作画面”的词在 Google 图片里搜，中、日、英哪个搜得准用哪个。",
            "- **实景照片**（AI 生成插画的输入）：最好是 **自己拍的**；网上的要 **CC0 / 公有领域 / CC BY / CC BY-SA**（不能是 NC、ND）。"
            "在 Google 图片里点 **工具 → 使用权限 → 知识共享许可** 再挑，或点每条下面的现成链接。",
            "- 实景照片最好和原作镜头同一个角度：站在机位上、朝“镜头朝向”拍。", "",
            "发图时写上 **编号**（编号固定不变，增删名场面也不会改）。标了“✅ 已有插画”的不用再找。", ""]
    if resend or received:
        head += ["## 现在的进度", ""]
        if resend:
            head.append("- **需要重新发**（上次没收到图片文件）：")
            head += [f"  - 第 {numbers[sid]} 张 {title_of(sid)}" for sid in sorted(resend, key=lambda x: numbers[x]) if sid in spots]
        if received:
            head.append("- **已收到，等攒够 10 张一起生成**：")
            head += [f"  - 第 {numbers[sid]} 张 {title_of(sid)}" for sid in sorted(received, key=lambda x: numbers[x]) if sid in spots]
        head.append("")
    head += [f"共 {len(live)} 个名场面；编号有空缺是因为那些名场面已经删掉了。", ""]
    out = ["\n".join(head)]

    for n, sid in live:
        s, w = spots[sid], works[spots[sid]["workID"]]
        t = s["text"]
        is_anime = w["mediaType"] in ("anime", "animeFilm")
        badge = {"anime": "日漫", "animeFilm": "日漫", "drama": "日剧", "film": "日影"}[w["mediaType"]]
        if w["mediaType"] == "film" and w.get("country") not in (None, "JP"):
            badge = "电影"
        kind = "官方圣地" if s.get("kind") == "landmark" else "名场面·取景地"
        if s.get("illustration"):
            state = "✅ 已有插画，不用再找"
        elif sid in received:
            state = "📥 已收到，等生成"
        elif sid in resend:
            state = "⚠️ 需要重新发"
        else:
            state = "🔍 需要找图"

        frame_lines = []
        for lang in ("ja", "zh-Hans", "en"):
            tx = t.get(lang) or t["zh-Hans"]
            work = work_title(w, lang)
            place = trim_place(tx.get("placeName") or "")
            terms = tx.get("searchTerms") or []
            word = (PILGRIMAGE if is_anime else PILGRIMAGE_LIVE)[lang]
            main_q = join_unique([work, place] + terms[:2] + [word])
            scene_q = join_unique([work, tx.get("sceneTitle")] + terms[:1])
            frame_lines.append(f"  - {LANG_NAME[lang]}：\n\n    ```\n    {main_q}\n    ```\n"
                               f"    名场面名字：\n\n    ```\n    {scene_q}\n    ```")

        ja_place = trim_place((t.get("ja") or {}).get("placeName") or t["zh-Hans"]["placeName"])
        en_place = trim_place((t.get("en") or {}).get("placeName") or ja_place)
        enc = urllib.parse.quote(ja_place)
        heading = COMPASS[int(((s["sceneHeading"] % 360) + 22.5) // 45) % 8]
        photo = s.get("photo")
        cur = f"　·　[现在用的照片]({photo['pageURL']})" if photo and photo.get("pageURL") else ""
        out.append(f"""## 第 {n} 张　{badge}{title_of(sid)}

- 状态：{state}　·　类型：{kind}　·　ID：`{sid}`
- 地点：{t['zh-Hans']['placeName']}　·　镜头朝向：面向{heading}{cur}
- 搜原作画面（作品名 + 地点 + 名场面关键词）：
{chr(10).join(frame_lines)}
- 搜实景照片：

  ```
  {ja_place} 写真
  ```
  ```
  {en_place} photo
  ```
- 现成链接：[Google 图片·已筛选知识共享许可](https://www.google.com/search?tbm=isch&tbs=sur:cl&q={enc})　·　[Wikimedia Commons](https://commons.wikimedia.org/w/index.php?search={enc}&title=Special:MediaSearch&type=image)
""")
    open(OUT, "w", encoding="utf-8").write("\n".join(out))
    print(f"已生成 {os.path.relpath(OUT, ROOT)}：{len(live)} 个名场面，最大编号 {max(numbers.values())}")


if __name__ == "__main__":
    main()
