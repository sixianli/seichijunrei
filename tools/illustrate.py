#!/usr/bin/env python3
"""把名场面的实景照片转成“动画背景美术”风格的插画（详情页封面）。

  python3 tools/illustrate.py              # 给所有还没有插画、但有实景照片的名场面生成
  python3 tools/illustrate.py ID [ID ...]  # 只生成（或重画）指定的名场面
  python3 tools/illustrate.py --dry-run    # 只列出要生成哪些

版权原则（重要）：
- 输入只用 catalog.json 里自由许可（CC0 / CC BY / CC BY-SA / 公有领域）的实景照片，绝不用作品截图；
- 提示词只描述通用的画风和光线，不出现任何作品名、角色名、作者名，不画人物；
- 插画是原照片的改编作品：App 里注明“据 <作者> 的照片绘制”和原许可证（CC BY-SA 的插画同样以 CC BY-SA 提供）。

通过 Vercel AI Gateway 调用 openai/gpt-image-2 的图片编辑接口（/v1/images/edits）。
API Key 由运行环境的网络代理注入（Authorization 头），脚本里只写占位符。
"""
import base64, io, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "SeichiJunrei", "Resources", "catalog.json")
OUT_DIR = os.path.join(ROOT, "SeichiJunrei", "Resources", "Illustrations")
ENDPOINT = "https://ai-gateway.vercel.sh/v1/images/edits"
MODEL = "openai/gpt-image-2"
UA = "SeichiJunreiCatalog/1.0 (illustration build script)"

PROMPT = (
    "Repaint this photo as background art from a Japanese animated feature film. It must NOT look like a photo: "
    "flat cel-shaded painting, simplified hand-painted textures, clean crisp outlines on buildings and structures, "
    "painted clouds with soft edges, vivid luminous colors, subtle glow and bloom. Keep exactly the same location, "
    "camera position, viewing angle and composition, and keep every landmark in place so the real place stays "
    "instantly recognizable. Lighting and season: {light}. Do not add any people, characters or animals; remove any "
    "people from the photo. Leave signboards plain or with simple shapes; no readable text, no letters, no logos, "
    "no watermark."
)

# 已经人工挑过光线的名场面（其余按“最佳到访时间”自动生成）
LIGHT_OVERRIDES = {
    "kiminonawa-suga-shrine": "warm late-afternoon sunlight from the right, half of the stairs in golden light and "
                              "half in cool blue shadow, bright hazy sky",
    "slamdunk-kamakurakokomae": "bright clear summer afternoon, deep blue sky with towering white cumulus clouds over "
                                "a sparkling blue sea, strong sunlight and crisp shadows",
    "spirited-away-dogo-onsen": "early night just after dusk, deep blue-violet sky, every paper window and lantern "
                                "glowing with warm golden light, soft warm light spilling onto the street, gentle mist",
}


def lighting(spot):
    if spot["id"] in LIGHT_OVERRIDES:
        return LIGHT_OVERRIDES[spot["id"]]
    best = (spot.get("text", {}).get("en", {}) or {}).get("bestTime", "")
    base = "beautiful natural light that matches this description of the best time to visit: " + best if best else \
        "bright clear afternoon with soft cumulus clouds"
    return base + "; luminous sky, rich but natural colors"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def size_for(img_bytes):
    from PIL import Image
    w, h = Image.open(io.BytesIO(img_bytes)).size
    r = w / h
    if r > 1.2: return "1536x1024"
    if r < 0.83: return "1024x1536"
    return "1024x1024"


def multipart(fields, files):
    boundary = "----seichi" + str(int(time.time() * 1000))
    out = io.BytesIO()
    for k, v in fields.items():
        out.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    for k, (name, data, ctype) in files.items():
        out.write(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{name}\"\r\n"
                  f"Content-Type: {ctype}\r\n\r\n".encode())
        out.write(data)
        out.write(b"\r\n")
    out.write(f"--{boundary}--\r\n".encode())
    return out.getvalue(), f"multipart/form-data; boundary={boundary}"


def generate(spot):
    from PIL import Image
    photo = fetch(spot["photo"]["url"])
    body, ctype = multipart(
        {"model": MODEL, "prompt": PROMPT.format(light=lighting(spot)), "size": size_for(photo), "n": "1"},
        {"image": ("photo.jpg", photo, "image/jpeg")})
    req = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
        "Content-Type": ctype, "User-Agent": UA,
        "Authorization": "Bearer proxy-injected",   # 真正的 Key 由网络代理注入
    })
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                data = json.load(r)
            break
        except Exception as e:  # noqa: BLE001
            if attempt == 2: raise
            time.sleep(10 * (attempt + 1))
    png = base64.b64decode(data["data"][0]["b64_json"])
    im = Image.open(io.BytesIO(png)).convert("RGB")
    im.thumbnail((1280, 1280))
    path = os.path.join(OUT_DIR, f"{spot['id']}.jpg")
    im.save(path, "JPEG", quality=82, optimize=True, progressive=True)
    return path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    os.makedirs(OUT_DIR, exist_ok=True)
    spots = json.load(open(CATALOG, encoding="utf-8"))["spots"]
    if args:
        todo = [s for s in spots if s["id"] in args and s.get("photo")]
    else:
        todo = [s for s in spots if s.get("photo")
                and not os.path.exists(os.path.join(OUT_DIR, f"{s['id']}.jpg"))]
    print(f"{len(todo)} 个名场面要生成插画")
    if dry:
        for s in todo: print(" ", s["id"], "|", lighting(s)[:90])
        return
    failed = []

    def run(s):
        try:
            p = generate(s)
            print("✓", s["id"], os.path.getsize(p) // 1024, "KB", flush=True)
        except Exception as e:  # noqa: BLE001
            failed.append(s["id"])
            print("✗", s["id"], e, flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(run, todo))
    if failed:
        print("失败：", " ".join(failed))
        sys.exit(1)


if __name__ == "__main__":
    main()
