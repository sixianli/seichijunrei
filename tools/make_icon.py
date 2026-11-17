#!/usr/bin/env python3
"""App 图标生成器（1024×1024，RGB 无透明通道，符合 App Store 要求）。

用法：
  python3 tools/make_icon.py --sheet out.png      # 生成全部方案的对比图
  python3 tools/make_icon.py --concept B          # 把方案 B 写入 AppIcon.appiconset
"""
import argparse, math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048  # 超采样画布，最后缩小到 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON = os.path.join(ROOT, "SeichiJunrei", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
WHITE = (255, 255, 255)
JP_FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"

# ---------- 绘图工具 ----------
def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def vgradient(stops):
    """stops: [(位置0..1, (r,g,b)), ...]"""
    img = Image.new("RGB", (1, S))
    for y in range(S):
        t = y / (S - 1)
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            if p0 <= t <= p1:
                img.putpixel((0, y), lerp(c0, c1, (t - p0) / max(p1 - p0, 1e-6)))
                break
    return img.resize((S, S))

def radial(center_color, edge_color, cx=0.5, cy=0.5, r=0.75):
    mask = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(mask)
    steps = 120
    for i in range(steps, 0, -1):
        rr = r * S * i / steps
        d.ellipse((cx*S - rr, cy*S - rr, cx*S + rr, cy*S + rr), fill=int(255 * (1 - i / steps)))
    return Image.composite(Image.new("RGB", (S, S), center_color), Image.new("RGB", (S, S), edge_color), mask)

def glow(img, box, color, strength=150, blur=0.06):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse([v * S for v in box], fill=strength)
    m = m.filter(ImageFilter.GaussianBlur(S * blur))
    return Image.composite(Image.new("RGB", (S, S), color), img, m)

def torii(d, cx, top, w, h, color=WHITE):
    """鸟居：cx 中心，top 笠木顶部，w 宽，h 总高（单位：像素）"""
    k = w / 1146  # 以原始设计宽度为基准缩放
    d.polygon([(cx - w/2 - 80*k, top), (cx + w/2 + 80*k, top),
               (cx + w/2 + 20*k, top + 100*k), (cx - w/2 - 20*k, top + 100*k)], fill=color)
    d.rectangle((cx - w/2 + 40*k, top + 100*k, cx + w/2 - 40*k, top + 140*k), fill=color)
    d.rectangle((cx - w/2 + 60*k, top + 240*k, cx + w/2 - 60*k, top + 310*k), fill=color)
    d.rectangle((cx - 45*k, top + 140*k, cx + 45*k, top + 240*k), fill=color)
    for sx in (-1, 1):
        xt = cx + sx * (w/2 - 205*k)
        xb = cx + sx * (w/2 - 150*k)
        d.polygon([(xt - 60*k, top + 140*k), (xt + 60*k, top + 140*k),
                   (xb + 70*k, top + h), (xb - 70*k, top + h)], fill=color)

def sparkle(d, x, y, r, color=WHITE):
    d.polygon([(x, y - r), (x + r*.22, y - r*.22), (x + r, y), (x + r*.22, y + r*.22),
               (x, y + r), (x - r*.22, y + r*.22), (x - r, y), (x - r*.22, y - r*.22)], fill=color)

def viewfinder(d, m, L, t, color=WHITE):
    for (x, y, dx, dy) in [(m, m, 1, 1), (S-m, m, -1, 1), (m, S-m, 1, -1), (S-m, S-m, -1, -1)]:
        d.rectangle((min(x, x+dx*L), min(y, y+dy*t), max(x, x+dx*L), max(y, y+dy*t)), fill=color)
        d.rectangle((min(x, x+dx*t), min(y, y+dy*L), max(x, x+dx*t), max(y, y+dy*L)), fill=color)

def petal(d, cx, cy, r, angle, color):
    """樱花花瓣：从花心向外的水滴形，外缘中间有一个小缺口"""
    pts = []
    n = 80
    for i in range(n + 1):
        t = i / n                       # 0 → 1 沿右侧轮廓从花心到外缘
        y = -r * t
        x = r * 0.36 * math.sin(math.pi * min(t * 1.15, 1.0)) ** 0.8
        pts.append((x, y))
    right = pts
    notch = [(r * 0.10, -r), (0, -r * 0.86), (-r * 0.10, -r)]
    left = [(-x, y) for (x, y) in reversed(right)]
    shape = right + notch + left
    a = math.radians(angle)
    d.polygon([(cx + x*math.cos(a) - y*math.sin(a), cy + x*math.sin(a) + y*math.cos(a)) for x, y in shape], fill=color)

def sakura(d, cx, cy, r, color, center=None):
    for k in range(5):
        petal(d, cx, cy, r, k * 72, color)
    if center:
        d.ellipse((cx - r*.16, cy - r*.16, cx + r*.16, cy + r*.16), fill=center)

def map_pin(d, cx, top, w, color):
    """定位针：圆头 + 尖底"""
    r = w / 2
    d.ellipse((cx - r, top, cx + r, top + w), fill=color)
    d.polygon([(cx - r*0.86, top + r*1.5), (cx + r*0.86, top + r*1.5), (cx, top + w*1.62)], fill=color)

# ---------- 方案 ----------
def concept_A():
    """黄昏鸟居 + 取景框（当前方案）"""
    img = vgradient([(0, (34, 52, 130)), (0.62, (232, 92, 142)), (1, (255, 190, 120))])
    img = glow(img, (0.30, 0.52, 0.70, 0.92), (255, 226, 190))
    d = ImageDraw.Draw(img)
    torii(d, S/2, S*0.335, S*0.56, S*0.405)
    viewfinder(d, S*0.14, S*0.13, S*0.028)
    sparkle(d, S*0.74, S*0.24, S*0.06)
    return img

def concept_B():
    """樱花定位针：樱粉底 + 白色定位针，针头里是一朵樱花"""
    img = radial((255, 196, 214), (236, 92, 140), cy=0.38, r=0.9)
    d = ImageDraw.Draw(img)
    map_pin(d, S/2, S*0.14, S*0.46, WHITE)
    sakura(d, S/2, S*0.37, S*0.17, (240, 98, 146), center=(255, 214, 102))
    for (x, y, r, a) in [(0.20, 0.76, 0.07, 200), (0.80, 0.70, 0.06, 150), (0.74, 0.86, 0.045, 230), (0.24, 0.26, 0.05, 160)]:
        petal(d, S*x, S*y, S*r, a, (255, 236, 242))
    return img

def concept_C():
    """方位罗盘：深夜蓝 + 金色罗盘，指针指向鸟居"""
    img = radial((40, 62, 120), (12, 18, 46), r=0.8)
    d = ImageDraw.Draw(img)
    gold = (246, 200, 92)
    c, R = S/2, S*0.34
    d.ellipse((c-R, c-R, c+R, c+R), outline=gold, width=int(S*0.022))
    for i in range(72):
        a = math.radians(i * 5)
        l = S*0.035 if i % 18 == 0 else S*0.016
        r0 = R - S*0.03
        d.line([(c + r0*math.sin(a), c - r0*math.cos(a)), (c + (r0-l)*math.sin(a), c - (r0-l)*math.cos(a))],
               fill=gold, width=int(S*0.008))
    # 指针（北指向鸟居方向）
    d.polygon([(c, c - R*0.50), (c + S*0.05, c), (c, c + S*0.02), (c - S*0.05, c)], fill=(236, 84, 92))
    d.polygon([(c, c + R*0.62), (c + S*0.05, c), (c, c - S*0.02), (c - S*0.05, c)], fill=(230, 232, 240))
    d.ellipse((c - S*0.025, c - S*0.025, c + S*0.025, c + S*0.025), fill=gold)
    torii(d, c, c - R*0.80, S*0.14, S*0.10, color=gold)
    return img

def concept_D():
    """胶片中的富士山：一格电影胶片，里面是富士山与夕阳"""
    img = Image.new("RGB", (S, S), (24, 26, 34))
    d = ImageDraw.Draw(img)
    fx0, fy0, fx1, fy1 = S*0.16, S*0.22, S*0.84, S*0.78
    frame = vgradient([(0, (255, 140, 120)), (0.55, (255, 196, 140)), (1, (120, 170, 220))]).crop((0, int(fy0), S, int(fy1)))
    frame = frame.resize((int(fx1 - fx0), int(fy1 - fy0)))
    img.paste(frame, (int(fx0), int(fy0)))
    d = ImageDraw.Draw(img)
    d.ellipse((S*0.56, S*0.33, S*0.70, S*0.47), fill=(255, 238, 200))       # 夕阳
    d.polygon([(S*0.16, S*0.78), (S*0.44, S*0.44), (S*0.50, S*0.42), (S*0.56, S*0.44), (S*0.84, S*0.78)], fill=(58, 74, 120))
    d.polygon([(S*0.40, S*0.49), (S*0.44, S*0.44), (S*0.50, S*0.42), (S*0.56, S*0.44), (S*0.60, S*0.49),
               (S*0.55, S*0.475), (S*0.50, S*0.50), (S*0.45, S*0.475)], fill=WHITE)  # 雪顶
    # 胶片齿孔
    for row in (0.14, 0.82):
        for i in range(7):
            x = S*0.13 + i * S*0.11
            d.rounded_rectangle((x, S*row, x + S*0.07, S*row + S*0.045), radius=S*0.01, fill=(236, 236, 240))
    return img

def concept_E():
    """彗星夜空：深蓝星空中一道彗星，地平线上的鸟居剪影"""
    img = vgradient([(0, (10, 16, 52)), (0.7, (46, 54, 128)), (1, (236, 130, 150))])
    d = ImageDraw.Draw(img)
    import random
    rnd = random.Random(7)
    for _ in range(140):
        x, y, r = rnd.random() * S, rnd.random() * S * 0.62, rnd.choice([2, 3, 4, 6])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255))
    # 彗星尾迹（渐变的长条）
    tail = Image.new("L", (S, S), 0)
    td = ImageDraw.Draw(tail)
    for i in range(60):
        t = i / 59
        x = S*0.18 + t * S*0.55
        y = S*0.16 + t * S*0.30
        rr = S*0.012 + t * S*0.028
        td.ellipse((x - rr, y - rr, x + rr, y + rr), fill=int(40 + 215 * t))
    tail = tail.filter(ImageFilter.GaussianBlur(S * 0.012))
    img = Image.composite(Image.new("RGB", (S, S), (190, 230, 255)), img, tail)
    d = ImageDraw.Draw(img)
    d.ellipse((S*0.70, S*0.43, S*0.77, S*0.50), fill=WHITE)
    # 地平线与鸟居剪影
    d.rectangle((0, S*0.86, S, S), fill=(22, 20, 48))
    torii(d, S/2, S*0.60, S*0.40, S*0.27, color=(22, 20, 48))
    return img

def concept_F():
    """「聖」字朱印：和纸色底 + 朱红圆印（御朱印风格）"""
    img = radial((252, 246, 232), (238, 226, 204), r=0.9)
    d = ImageDraw.Draw(img)
    red = (206, 40, 46)
    c, R = S/2, S*0.37
    d.ellipse((c-R, c-R, c+R, c+R), fill=red)
    d.ellipse((c-R*0.88, c-R*0.88, c+R*0.88, c+R*0.88), outline=(252, 246, 232), width=int(S*0.012))
    font = ImageFont.truetype(JP_FONT, int(S*0.40))
    box = d.textbbox((0, 0), "聖", font=font)
    d.text((c - (box[0] + box[2]) / 2, c - (box[1] + box[3]) / 2), "聖", font=font, fill=(252, 246, 232))
    sparkle(d, S*0.80, S*0.20, S*0.05, red)
    return img

def concept_G():
    """玻璃层叠：Liquid Glass 风格的半透明圆层 + 中央定位针"""
    img = radial((120, 200, 255), (40, 70, 200), cx=0.3, cy=0.25, r=1.1)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for (cx, cy, r, a) in [(0.36, 0.40, 0.30, 70), (0.64, 0.58, 0.30, 70), (0.50, 0.50, 0.24, 90)]:
        ld.ellipse((S*(cx - r), S*(cy - r), S*(cx + r), S*(cy + r)), fill=(255, 255, 255, a),
                   outline=(255, 255, 255, 200), width=int(S*0.006))
    layer = layer.filter(ImageFilter.GaussianBlur(S * 0.002))
    img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
    d = ImageDraw.Draw(img)
    map_pin(d, S/2, S*0.30, S*0.30, WHITE)
    torii(d, S/2, S*0.355, S*0.16, S*0.12, color=(60, 100, 230))
    return img

def concept_H():
    """海边道口：日落海面 + 铁道道口标志（湘南风）"""
    img = vgradient([(0, (255, 166, 120)), (0.55, (255, 214, 160)), (0.56, (60, 140, 200)), (1, (24, 80, 150))])
    img = glow(img, (0.36, 0.40, 0.64, 0.68), (255, 240, 200), strength=200, blur=0.03)
    d = ImageDraw.Draw(img)
    # 道口立柱
    d.rectangle((S*0.47, S*0.36, S*0.53, S*0.92), fill=(30, 30, 36))
    # X 字标志（黄黑条纹）
    for ang in (35, -35):
        bar = Image.new("RGBA", (int(S*0.62), int(S*0.10)), (0, 0, 0, 0))
        bd = ImageDraw.Draw(bar)
        bd.rectangle((0, 0, bar.width, bar.height), fill=(250, 204, 40, 255))
        stripe = int(S*0.06)
        for x in range(-bar.height, bar.width, stripe * 2):
            bd.polygon([(x, bar.height), (x + bar.height, 0), (x + bar.height + stripe, 0), (x + stripe, bar.height)],
                       fill=(30, 30, 36, 255))
        bar = bar.rotate(ang, expand=True, resample=Image.BICUBIC)
        img.paste(bar, (int(S/2 - bar.width/2), int(S*0.30 - bar.height/2)), bar)
    d = ImageDraw.Draw(img)
    # 两盏红色警示灯
    for x in (0.38, 0.62):
        d.ellipse((S*(x-0.055), S*0.50, S*(x+0.055), S*0.61), fill=(30, 30, 36))
        d.ellipse((S*(x-0.04), S*0.515, S*(x+0.04), S*0.595), fill=(236, 50, 50) if x < 0.5 else (90, 30, 30))
    d.rectangle((S*0.33, S*0.545, S*0.67, S*0.565), fill=(30, 30, 36))
    return img

CONCEPTS = {
    "A": ("黄昏鸟居", concept_A), "B": ("樱花定位针", concept_B), "C": ("方位罗盘", concept_C),
    "D": ("胶片富士", concept_D), "E": ("彗星夜空", concept_E), "F": ("圣字朱印", concept_F),
    "G": ("玻璃层叠", concept_G), "H": ("海边道口", concept_H),
}

def render(key):
    return CONCEPTS[key][1]().resize((1024, 1024), Image.LANCZOS).convert("RGB")

def squircle_mask(size, radius_ratio=0.2237):
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * radius_ratio), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def contact_sheet(path):
    cell, pad, label_h = 360, 48, 70
    cols, rows = 4, 2
    W = cols * cell + (cols + 1) * pad
    H = rows * (cell + label_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (W, H), (242, 242, 247))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", 32)
    mask = squircle_mask(cell)
    for i, key in enumerate(CONCEPTS):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + label_h + pad)
        icon = render(key).resize((cell, cell), Image.LANCZOS)
        shadow = Image.new("L", (cell + 40, cell + 40), 0)
        ImageDraw.Draw(shadow).rounded_rectangle((20, 28, cell + 20, cell + 28), radius=int(cell * 0.2237), fill=70)
        shadow = shadow.filter(ImageFilter.GaussianBlur(12))
        sheet.paste((200, 200, 210), (x - 20, y - 20), shadow)
        sheet.paste(icon, (x, y), mask)
        text = f"{key}  {CONCEPTS[key][0]}"
        tw = d.textlength(text, font=font)
        d.text((x + (cell - tw) / 2, y + cell + 18), text, font=font, fill=(40, 40, 50))
    sheet.save(path)
    print("wrote", path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet")
    ap.add_argument("--concept", choices=list(CONCEPTS))
    a = ap.parse_args()
    if a.sheet:
        contact_sheet(a.sheet)
    if a.concept:
        img = render(a.concept)
        os.makedirs(os.path.dirname(APPICON), exist_ok=True)
        img.save(APPICON, "PNG")
        print("wrote", APPICON, img.size, img.mode, "concept", a.concept)

if __name__ == "__main__":
    main()
