#!/usr/bin/env python3
"""名场面数据工具。格式说明见 data/README.md。

  python3 tools/catalog.py check [data/sources/x.json ...]   # 校验（默认全部来源文件）
  python3 tools/catalog.py build [--offline]                   # 生成 SeichiJunrei/Resources/catalog.json

build 会：合并全部来源文件 → 校验引用 → 用 OpenCC(s2twp) 补齐繁体中文 →
从 Wikimedia Commons 查询照片的作者 / 许可证（缓存到 data/photo-cache.json）。
"""
import glob, json, os, re, sys, urllib.error, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "data", "sources")
PHOTO_CACHE = os.path.join(ROOT, "data", "photo-cache.json")
OUT = os.path.join(ROOT, "SeichiJunrei", "Resources", "catalog.json")

LANGS = ["zh-Hans", "zh-Hant", "ja", "en", "ko"]
AUTHORED = ["zh-Hans", "ja", "en", "ko"]          # zh-Hant 由简中转换
MEDIA = {"anime", "animeFilm", "film", "drama"}
ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
SPOT_FIELDS = ["placeName", "sceneTitle", "episode", "highlight", "story", "access", "bestTime", "tips"]
# 简中长度建议（字符数），超出只警告
ZH_LEN = {"sceneTitle": (2, 18), "highlight": (60, 240), "story": (100, 380), "access": (8, 100),
          "bestTime": (6, 80), "tips": (10, 130)}
FREE_LICENSES = re.compile(r"^(cc0|pd|public domain|pdm|cc by(-sa)?( \d\.\d)?( [a-z]{2})?$|cc-by(-sa)?-\d\.\d)", re.I)


class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def err(self, where, msg): self.errors.append(f"{where}: {msg}")
    def warn(self, where, msg): self.warnings.append(f"{where}: {msg}")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def check_work(w, r):
    where = f"work {w.get('id', '?')}"
    for k in ["id", "title", "mediaType", "year", "creator", "tint", "aliases", "text"]:
        if k not in w: r.err(where, f"缺少字段 {k}")
    if not ID_RE.match(w.get("id", "")): r.err(where, "id 只能是小写字母、数字和连字符")
    if w.get("mediaType") not in MEDIA: r.err(where, f"mediaType 必须是 {sorted(MEDIA)}")
    if not isinstance(w.get("year"), int) or not 1900 <= w.get("year", 0) <= 2030: r.err(where, "year 不合法")
    if not re.match(r"^#[0-9A-Fa-f]{6}$", w.get("tint", "")): r.err(where, "tint 必须是 #RRGGBB")
    if "country" in w and not re.match(r"^[A-Z]{2}$", w["country"]): r.err(where, "country 必须是两位大写国家代码")
    text = w.get("text", {})
    for lang in AUTHORED:
        t = text.get(lang)
        if t is None: r.err(where, f"缺少 text.{lang}"); continue
        if "title" not in t: r.err(where, f"text.{lang}.title 缺失（ja 写空字符串）")
        if not t.get("synopsis"): r.err(where, f"text.{lang}.synopsis 缺失")
        if lang != "ja" and not t.get("title"): r.err(where, f"text.{lang}.title 不能为空")
    if not (text.get("zh-Hant") or {}).get("title"): r.err(where, "text.zh-Hant.title（台湾通行译名）缺失")


def check_spot(s, r):
    where = f"spot {s.get('id', '?')}"
    for k in ["id", "workID", "latitude", "longitude", "sceneHeading", "arrivalRadius", "spoiler", "text"]:
        if k not in s: r.err(where, f"缺少字段 {k}")
    if not ID_RE.match(s.get("id", "")): r.err(where, "id 只能是小写字母、数字和连字符")
    lat, lon = s.get("latitude", 0), s.get("longitude", 0)
    if not (24 <= lat <= 46 and 122 <= lon <= 154): r.err(where, f"坐标不在日本范围内：{lat},{lon}")
    for k in ("latitude", "longitude"):
        v = s.get(k)
        if isinstance(v, float) and len(repr(v).split(".")[-1]) < 4: r.warn(where, f"{k} 精度过低：{v}")
    if not 0 <= s.get("sceneHeading", -1) < 360: r.err(where, "sceneHeading 必须在 0..<360")
    p = s.get("scenePitch")
    if p is not None and not -30 <= p <= 45: r.err(where, "scenePitch 必须在 -30…45")
    if not 10 <= s.get("arrivalRadius", 0) <= 300: r.err(where, "arrivalRadius 必须在 10…300")
    if not isinstance(s.get("spoiler"), bool): r.err(where, "spoiler 必须是 true/false")
    if s.get("verified", False) is not False: r.err(where, "verified 只能是 false")
    photo = s.get("photo")
    if isinstance(photo, dict):
        check_photo_dict(photo, where, r)
    elif photo is not None and not str(photo).startswith("File:"):
        r.err(where, "photo 必须是 Commons 文件名 File:... 或照片对象")
    if not s.get("sourceURL"): r.warn(where, "没有 sourceURL")
    months = s.get("bestMonths")
    if months is None: r.warn(where, "没有 bestMonths（最佳到访月份）")
    elif not (isinstance(months, list) and months and all(isinstance(m, int) and 1 <= m <= 12 for m in months)
              and len(set(months)) == len(months)):
        r.err(where, "bestMonths 必须是 1–12 的整数列表，不重复")
    ap = s.get("accessPoint")
    if ap is None: r.warn(where, "没有 accessPoint（步行起点：车站出口 / 巴士站）")
    else:
        alat, alon = ap.get("latitude", 0), ap.get("longitude", 0)
        if not (24 <= alat <= 46 and 122 <= alon <= 154): r.err(where, f"accessPoint 坐标不在日本范围内：{alat},{alon}")
        else:
            import math
            d = math.hypot((alat - lat) * 111000, (alon - lon) * 111000 * math.cos(math.radians(lat)))
            if d > 5000: r.err(where, f"accessPoint 离机位 {d:.0f} m，太远（应是步行起点）")
        for lang in AUTHORED:
            if not ((s.get("text", {}).get(lang) or {}).get("accessPointName") or "").strip():
                r.err(where, f"有 accessPoint 但缺少 text.{lang}.accessPointName")
    text = s.get("text", {})
    for lang in AUTHORED:
        t = text.get(lang)
        if t is None: r.err(where, f"缺少 text.{lang}"); continue
        for f in SPOT_FIELDS:
            if not (t.get(f) or "").strip(): r.err(where, f"text.{lang}.{f} 为空")
    zh = text.get("zh-Hans", {})
    for f, (lo, hi) in ZH_LEN.items():
        n = len(zh.get(f) or "")
        if n and not lo <= n <= hi: r.warn(where, f"zh-Hans.{f} 长度 {n}，建议 {lo}–{hi}")


def check_photo_dict(photo, where, r):
    for k in ("url", "pageURL", "author", "license"):
        if not photo.get(k): r.err(where, f"photo.{k} 缺失")
    if not FREE_LICENSES.match(photo.get("license", "")):
        r.err(where, f"photo.license {photo.get('license')} 不可用（只接受 CC0 / PD / CC BY / CC BY-SA）")
    if not str(photo.get("url", "")).startswith("https://"): r.err(where, "photo.url 必须是 https")


def load_overrides(r):
    """data/photo-overrides*.json：{spotID: 照片对象或 Commons 文件名}，用于补图 / 替换不合适的照片"""
    out = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "photo-overrides*.json"))):
        for sid, photo in load(p).items():
            if isinstance(photo, dict): check_photo_dict(photo, f"{os.path.basename(p)} {sid}", r)
            out[sid] = photo
    return out


def check_file(path, r):
    try:
        data = load(path)
    except Exception as e:  # noqa: BLE001
        r.err(path, f"JSON 无法解析：{e}"); return None
    if set(data) - {"works", "spots"}: r.err(path, "顶层只能有 works / spots")
    for w in data.get("works", []): check_work(w, r)
    for s in data.get("spots", []): check_spot(s, r)
    return data


def merge(paths, r):
    works, spots = {}, {}
    for p in paths:
        data = check_file(p, r)
        if not data: continue
        for w in data.get("works", []):
            if w["id"] in works: r.err(p, f"作品 {w['id']} 重复定义")
            works[w["id"]] = w
        for s in data.get("spots", []):
            if s["id"] in spots: r.err(p, f"名场面 {s['id']} 重复")
            spots[s["id"]] = s
    for sid, photo in load_overrides(r).items():
        if sid not in spots: r.err("photo-overrides", f"名场面 {sid} 不存在")
        else: spots[sid] = dict(spots[sid], photo=photo)
    for s in spots.values():
        if s.get("workID") not in works: r.err(f"spot {s['id']}", f"workID {s.get('workID')} 不存在")
    used = {s["workID"] for s in spots.values()}
    for w in works:
        if w not in used: r.warn(f"work {w}", "没有任何名场面")
    # 距离过近的重复点
    items = list(spots.values())
    for i, a in enumerate(items):
        for b in items[i + 1:]:
            if abs(a["latitude"] - b["latitude"]) < 0.00005 and abs(a["longitude"] - b["longitude"]) < 0.00005:
                r.warn(f"spot {a['id']}", f"和 {b['id']} 坐标几乎相同")
    return works, spots


# ---------- build ----------

def to_hant():
    try:
        import opencc  # pip install opencc-python-reimplemented
    except ImportError:
        sys.exit("需要 OpenCC：pip install opencc-python-reimplemented")
    c = opencc.OpenCC("s2twp")
    # 台湾习惯用「」『』作引号
    quotes = str.maketrans({"“": "「", "”": "」", "‘": "『", "’": "』"})
    return lambda text: c.convert(text).translate(quotes)


def fill_hant(text, convert, keep=()):
    hans = text.get("zh-Hans", {})
    hant = dict(text.get("zh-Hant") or {})
    for k, v in hans.items():
        if k in keep: continue
        if not hant.get(k) and isinstance(v, str): hant[k] = convert(v)
    return hant


def strip_html(s):
    s = re.sub(r"<[^>]+>", "", s or "")
    return re.sub(r"\s+", " ", s).strip()


def _commons_query(titles):
    """一次查询多张图片（最多 50 张），遇到 429 限流时退避重试。"""
    import time
    q = urllib.parse.urlencode({"action": "query", "titles": "|".join(titles), "prop": "imageinfo",
                                "iiprop": "url|extmetadata", "iiurlwidth": 1280, "format": "json",
                                "maxlag": 5})
    req = urllib.request.Request(f"https://commons.wikimedia.org/w/api.php?{q}",
                                 headers={"User-Agent": "SeichiJunreiCatalog/1.0 (data build script)"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)["query"]
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 5: raise
            time.sleep(5 * 2 ** attempt)


def _photo_meta(page):
    if "imageinfo" not in page: return None
    info = page["imageinfo"][0]
    meta = info.get("extmetadata", {})
    return {
        "url": info.get("thumburl") or info["url"],
        "pageURL": info.get("descriptionurl"),
        "author": strip_html(meta.get("Artist", {}).get("value")) or "Wikimedia Commons",
        "license": strip_html(meta.get("LicenseShortName", {}).get("value")),
        "licenseURL": meta.get("LicenseUrl", {}).get("value"),
    }


def resolve_photos(spots, offline, r):
    import time
    cache = load(PHOTO_CACHE) if os.path.exists(PHOTO_CACHE) else {}
    missing = sorted({s["photo"] for s in spots.values() if isinstance(s.get("photo"), str)} - set(cache))
    if not offline:
        for i in range(0, len(missing), 50):
            batch = missing[i:i + 50]
            try:
                result = _commons_query(batch)
            except Exception as e:  # noqa: BLE001
                r.warn("photos", f"Commons 查询失败：{e}")
                break
            # API 会把标题规范化（下划线→空格等），按规范化后的标题对应回去
            norm = {n["to"]: n["from"] for n in result.get("normalized", [])}
            for page in result.get("pages", {}).values():
                title = norm.get(page.get("title"), page.get("title"))
                cache[title] = _photo_meta(page)
            for t in batch:
                cache.setdefault(t, None)
            time.sleep(1)
    for s in spots.values():
        title = s.get("photo")
        if not title or isinstance(title, dict): continue
        meta = cache.get(title)
        if title not in cache:
            r.warn(f"spot {s['id']}", f"照片 {title} 尚未查询（离线或查询失败）")
        elif not meta:
            r.warn(f"spot {s['id']}", f"Commons 上找不到 {title}，已忽略")
        elif not FREE_LICENSES.match(meta.get("license") or ""):
            r.warn(f"spot {s['id']}", f"{title} 的许可证 {meta.get('license')} 不可用，已忽略")
    with open(PHOTO_CACHE, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, indent=1, sort_keys=True)
    return {t: m for t, m in cache.items() if m and FREE_LICENSES.match(m.get("license") or "")}


ILLUSTRATIONS = os.path.join(ROOT, "data", "illustrations.json")
ILLUSTRATION_DIR = os.path.join(ROOT, "SeichiJunrei", "Resources", "Illustrations")


def attach_illustrations(out_spots, r):
    """data/illustrations.json + Illustrations/<id>.jpg → 名场面的 illustration 字段。

    catalog 来源：插画据该名场面的实景照片绘制，basedOn 记下那张照片（署名用），可切换看实景；
    owner 来源：据开发者自己拍的照片绘制（不公开），只有 realPhotoMatches 为 true 才允许切换看目录里的实景照片。
    """
    meta = {k: v for k, v in load(ILLUSTRATIONS).items() if not k.startswith("_")}
    files = {os.path.splitext(f)[0] for f in os.listdir(ILLUSTRATION_DIR) if f.endswith(".jpg")} \
        if os.path.isdir(ILLUSTRATION_DIR) else set()
    by_id = {s["id"]: s for s in out_spots}
    used = {m.get("file", sid) for sid, m in meta.items()}
    for f in sorted(files - used): r.err("illustrations", f"{f}.jpg 没有在 illustrations.json 里登记来源")
    for sid in sorted(sid for sid, m in meta.items() if m.get("file", sid) not in files):
        r.warn("illustrations", f"{sid} 已登记但还没有插画文件")
    for sid in sorted(sid for sid, m in meta.items() if m.get("file", sid) in files):
        m, s = meta[sid], by_id.get(sid)
        fname = m.get("file", sid)
        if s is None:
            r.err("illustrations", f"名场面 {sid} 不存在"); continue
        if m.get("source") == "catalog":
            if not s.get("photo"):
                r.err("illustrations", f"{sid} 标为 catalog 来源，但名场面没有实景照片"); continue
            s["illustration"] = {"file": fname, "basedOn": s["photo"], "showsRealPhoto": True}
        elif m.get("source") == "owner":
            s["illustration"] = {"file": fname, "showsRealPhoto": bool(m.get("realPhotoMatches")) and bool(s.get("photo"))}
        else:
            r.err("illustrations", f"{sid} 的 source 只能是 catalog 或 owner")


def build(offline):
    r = Report()
    paths = sorted(glob.glob(os.path.join(SOURCES, "*.json")))
    works, spots = merge(paths, r)
    if r.errors: return r
    convert = to_hant()
    photos = resolve_photos(spots, offline, r)
    out_works = []
    for w in sorted(works.values(), key=lambda w: w["id"]):
        w = dict(w)
        text = dict(w["text"])
        text["zh-Hant"] = fill_hant(text, convert)
        w["text"] = {k: text[k] for k in LANGS if k in text}
        out_works.append(w)
    out_spots = []
    for s in sorted(spots.values(), key=lambda s: (s["workID"], s["id"])):
        s = dict(s)
        text = dict(s["text"])
        text["zh-Hant"] = fill_hant(text, convert)
        s["text"] = {k: text[k] for k in LANGS if k in text}
        title = s.pop("photo", None)
        if isinstance(title, dict): s["photo"] = {k: title[k] for k in ("url", "pageURL", "author", "license", "licenseURL") if title.get(k)}
        elif title in photos: s["photo"] = photos[title]
        s.setdefault("verified", False)
        out_spots.append(s)
    attach_illustrations(out_spots, r)
    if r.errors: return r
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"works": out_works, "spots": out_spots}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    counts = {}
    for s in out_spots:
        m = works[s["workID"]]["mediaType"]
        counts[m] = counts.get(m, 0) + 1
    print(f"已生成 {os.path.relpath(OUT, ROOT)}：{len(out_works)} 部作品，{len(out_spots)} 个名场面 {counts}，"
          f"{sum('photo' in s for s in out_spots)} 张实景照片，{sum('illustration' in s for s in out_spots)} 张插画封面")
    return r


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("check", "build"):
        sys.exit(__doc__)
    if args[0] == "check":
        r = Report()
        paths = args[1:] or sorted(glob.glob(os.path.join(SOURCES, "*.json")))
        if args[1:]:
            for p in paths: check_file(p, r)
        else:
            merge(paths, r)
    else:
        r = build("--offline" in args)
    for w in r.warnings: print("警告 ", w)
    for e in r.errors: print("错误 ", e)
    if r.errors: sys.exit(1)
    if args[0] == "check": print(f"OK（{len(r.warnings)} 条警告）")


if __name__ == "__main__":
    main()
