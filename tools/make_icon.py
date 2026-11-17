#!/usr/bin/env python3
"""App 图标生成器（1024×1024，RGB 无透明通道，符合 App Store 要求）。

用法：
  python3 tools/make_icon.py --sheet out.png                 # 第二批（小人 + 日本名景）对比图
  python3 tools/make_icon.py --sheet out.png --set symbols   # 第一批（符号类）对比图
  python3 tools/make_icon.py --concept 5                     # 把方案 5 写入 AppIcon.appiconset
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

# ---------- 第二批：小人站在日本名景中（背影构图，让人代入“我就在这里”） ----------
def person(d, cx, feet, h, color, pack=(0, 0, 0), raise_phone=True, screen=(255, 255, 255)):
    """背影小人：举着手机对准风景，背着小背包。cx 中心 x，feet 脚底 y，h 身高（像素）"""
    hw = h * 0.17                                  # 半个肩宽
    # 腿
    d.rounded_rectangle((cx - hw*0.78, feet - h*0.40, cx - hw*0.12, feet), radius=h*0.04, fill=color)
    d.rounded_rectangle((cx + hw*0.12, feet - h*0.40, cx + hw*0.78, feet), radius=h*0.04, fill=color)
    # 身体（上宽下窄）
    d.polygon([(cx - hw, feet - h*0.74), (cx + hw, feet - h*0.74),
               (cx + hw*0.86, feet - h*0.36), (cx - hw*0.86, feet - h*0.36)], fill=color)
    d.ellipse((cx - hw, feet - h*0.80, cx + hw, feet - h*0.66), fill=color)   # 圆肩
    # 头
    r = h * 0.105
    d.ellipse((cx - r, feet - h*0.98, cx + r, feet - h*0.98 + 2*r), fill=color)
    # 背包
    d.rounded_rectangle((cx - hw*0.62, feet - h*0.70, cx + hw*0.62, feet - h*0.44), radius=h*0.05, fill=pack)
    # 左臂自然下垂
    d.polygon([(cx - hw, feet - h*0.74), (cx - hw*0.70, feet - h*0.74),
               (cx - hw*1.05, feet - h*0.42), (cx - hw*1.35, feet - h*0.44)], fill=color)
    if raise_phone:
        # 右臂举起手机（举过肩，像在对准眼前的风景拍照）
        sx, sy = cx + hw*0.85, feet - h*0.74
        ex, ey = cx + hw*1.75, feet - h*1.02
        w = h * 0.06
        ang = math.atan2(ey - sy, ex - sx) + math.pi / 2
        ox, oy = math.cos(ang) * w, math.sin(ang) * w
        d.polygon([(sx - ox, sy - oy), (sx + ox, sy + oy), (ex + ox, ey + oy), (ex - ox, ey - oy)], fill=color)
        pw, ph = h * 0.13, h * 0.20
        d.rounded_rectangle((ex - pw/2, ey - ph*0.95, ex + pw/2, ey + ph*0.05), radius=h*0.025, fill=color)
        d.rounded_rectangle((ex - pw/2 + h*0.018, ey - ph*0.95 + h*0.018, ex + pw/2 - h*0.018, ey + ph*0.05 - h*0.018),
                            radius=h*0.015, fill=screen)

def mountain(d, cx, base, w, h, color, snow=WHITE):
    d.polygon([(cx - w/2, base), (cx - w*0.06, base - h), (cx + w*0.06, base - h), (cx + w/2, base)], fill=color)
    sh = h * 0.30
    d.polygon([(cx - w*0.06 - sh*0.55, base - h + sh), (cx - w*0.06, base - h), (cx + w*0.06, base - h),
               (cx + w*0.06 + sh*0.55, base - h + sh), (cx + w*0.03, base - h + sh*0.72), (cx, base - h + sh),
               (cx - w*0.04, base - h + sh*0.70)], fill=snow)

def blossoms(d, pts, colors):
    for i, (x, y, r) in enumerate(pts):
        d.ellipse((x - r, y - r, x + r, y + r), fill=colors[i % len(colors)])

def red_torii(d, cx, top, w, h, color, dark=(40, 30, 30)):
    """朱红鸟居（笠木为深色），用于严岛 / 稻荷"""
    k = w / 1000
    d.polygon([(cx - w/2 - 60*k, top), (cx + w/2 + 60*k, top), (cx + w/2 + 15*k, top + 70*k), (cx - w/2 - 15*k, top + 70*k)], fill=dark)
    d.rectangle((cx - w/2 + 20*k, top + 70*k, cx + w/2 - 20*k, top + 120*k), fill=color)
    d.rectangle((cx - w/2 + 50*k, top + 210*k, cx + w/2 - 50*k, top + 265*k), fill=color)
    for sx in (-1, 1):
        x = cx + sx * (w/2 - 170*k)
        d.rectangle((x - 45*k, top + 120*k, x + 45*k, top + h), fill=color)

def concept_P1():
    """富士山与樱：清晨的富士山，前景樱花枝，小人背影眺望"""
    img = vgradient([(0, (120, 180, 240)), (0.55, (255, 210, 200)), (1, (255, 236, 220))])
    d = ImageDraw.Draw(img)
    mountain(d, S*0.52, S*0.80, S*1.05, S*0.46, (70, 98, 168))
    d.rectangle((0, S*0.80, S, S), fill=(120, 150, 110))
    d.polygon([(0, S*0.84), (S, S*0.78), (S, S), (0, S)], fill=(92, 124, 86))
    # 樱花枝
    d.line([(0, S*0.08), (S*0.30, S*0.20), (S*0.42, S*0.18)], fill=(96, 60, 50), width=int(S*0.022))
    blossoms(d, [(S*x, S*y, S*r) for x, y, r in [(0.05, 0.05, .07), (0.15, 0.13, .07), (0.27, 0.22, .06), (0.38, 0.14, .05),
                 (0.10, 0.22, .05), (0.22, 0.06, .05), (0.33, 0.27, .04), (0.45, 0.20, .04), (0.02, 0.17, .05)]],
             [(255, 183, 206), (255, 206, 222), (248, 160, 190)])
    person(d, S*0.60, S*0.97, S*0.42, (40, 44, 70), pack=(220, 90, 90))
    return img

def pagoda(d, cx, base, w, h, color, roof=(60, 40, 40)):
    tiers = 5
    th = h * 0.82 / tiers
    for i in range(tiers):
        y = base - i * th
        tw = w * (1 - i * 0.12)
        d.rectangle((cx - tw*0.30, y - th*0.75, cx + tw*0.30, y), fill=color)
        d.polygon([(cx - tw/2, y - th*0.62), (cx + tw/2, y - th*0.62), (cx + tw*0.36, y - th*1.0), (cx - tw*0.36, y - th*1.0)], fill=roof)
    top = base - tiers * th
    d.rectangle((cx - w*0.02, top - h*0.18, cx + w*0.02, top), fill=roof)

def concept_P2():
    """五重塔与富士：远处的富士山，红色五重塔，小人站在观景台"""
    img = vgradient([(0, (255, 150, 120)), (0.6, (255, 200, 160)), (1, (255, 230, 200))])
    d = ImageDraw.Draw(img)
    mountain(d, S*0.62, S*0.70, S*0.95, S*0.40, (150, 130, 170), snow=(255, 246, 240))
    blossoms(d, [(S*x, S*y, S*r) for x, y, r in [(0.10, 0.72, .10), (0.25, 0.76, .09), (0.85, 0.74, .10), (0.98, 0.70, .08), (0.60, 0.78, .08)]],
             [(250, 170, 196), (255, 196, 214)])
    pagoda(d, S*0.30, S*0.76, S*0.30, S*0.56, (214, 70, 52))
    d.rectangle((0, S*0.80, S, S), fill=(70, 52, 60))
    d.rectangle((0, S*0.80, S, S*0.815), fill=(140, 100, 90))
    person(d, S*0.66, S*0.96, S*0.40, (34, 28, 40), pack=(240, 190, 70))
    return img

def tokyo_tower(d, cx, base, h, color, white=(250, 246, 240)):
    w = h * 0.36
    def x_at(t, side):  # t: 0 底 → 1 顶
        half = w/2 * (1 - t) ** 1.6 + h * 0.008
        return cx + side * half
    segs = 10
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        col = color if i % 2 == 0 else white
        y0, y1 = base - t0 * h, base - t1 * h
        d.polygon([(x_at(t0, -1), y0), (x_at(t0, 1), y0), (x_at(t1, 1), y1), (x_at(t1, -1), y1)], fill=col)
    # 两层展望台
    for t, ww in ((0.36, 0.20), (0.62, 0.09)):
        y = base - t * h
        d.rectangle((cx - h*ww/2, y - h*0.035, cx + h*ww/2, y), fill=white)
    # 底部拱门
    d.ellipse((cx - w*0.28, base - h*0.12, cx + w*0.28, base + h*0.10), fill=(30, 26, 60))

def concept_P3():
    """东京塔夜景：暮色中的东京塔，城市天际线，小人仰望"""
    img = vgradient([(0, (30, 26, 90)), (0.6, (160, 70, 140)), (1, (255, 150, 110))])
    d = ImageDraw.Draw(img)
    import random
    rnd = random.Random(3)
    for _ in range(60):
        x, y = rnd.random() * S, rnd.random() * S * 0.4
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 255, 255))
    tokyo_tower(d, S*0.40, S*0.84, S*0.76, (236, 90, 40))
    # 城市天际线
    x = 0
    while x < S:
        bw = rnd.uniform(0.06, 0.12) * S
        bh = rnd.uniform(0.08, 0.22) * S
        d.rectangle((x, S*0.86 - bh, x + bw, S), fill=(28, 24, 58))
        for wy in range(int(S*0.86 - bh + 20), int(S*0.86), 46):
            for wx in range(int(x + 16), int(x + bw - 16), 40):
                if rnd.random() < 0.35:
                    d.rectangle((wx, wy, wx + 14, wy + 18), fill=(255, 214, 120))
        x += bw
    d.rectangle((0, S*0.86, S, S), fill=(20, 18, 40))
    person(d, S*0.70, S*0.98, S*0.40, (12, 10, 26), pack=(70, 160, 240))
    return img

def figure_mask(cx, feet, h):
    """精致的背影人物剪影（遮罩）：齐肩短发、过膝外套、小背包、双手自然垂下、重心在右腿。
    坐标以身高为单位：脚底 y=0，头顶 y=-1（约 6.5 头身）。"""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    P = lambda x, y: (cx + x * h, feet + y * h)
    poly = lambda pts: d.polygon([P(x, y) for x, y in pts], fill=255)
    ell = lambda x0, y0, x1, y1: d.ellipse((*P(x0, y0), *P(x1, y1)), fill=255)
    rr = lambda x0, y0, x1, y1, r: d.rounded_rectangle((*P(x0, y0), *P(x1, y1)), radius=r * h, fill=255)

    # 头与齐肩短发（发梢略微外翘、左右不完全对称，显得自然）
    ell(-0.074, -1.000, 0.074, -0.846)
    poly([(-0.078, -0.940), (-0.090, -0.880), (-0.098, -0.826), (-0.104, -0.800), (-0.074, -0.806),
          (-0.040, -0.818), (0.040, -0.818), (0.078, -0.804), (0.108, -0.810), (0.096, -0.870), (0.080, -0.940)])
    # 脖子
    poly([(-0.028, -0.830), (0.028, -0.830), (0.030, -0.790), (-0.030, -0.790)])
    # 过膝外套：从脖子顺滑落下的斜肩 → 微收腰 → 下摆展开
    poly([(-0.150, -0.712), (-0.136, -0.748), (-0.104, -0.774), (-0.050, -0.796), (0.050, -0.796),
          (0.104, -0.774), (0.136, -0.748), (0.150, -0.712), (0.150, -0.680),
          (0.128, -0.560), (0.140, -0.420), (0.156, -0.322), (-0.156, -0.322), (-0.140, -0.420),
          (-0.128, -0.560), (-0.150, -0.680)])
    # 手臂：从肩线自然垂下，向手腕逐渐变细，手在大腿旁
    poly([(-0.152, -0.716), (-0.136, -0.748), (-0.118, -0.700), (-0.134, -0.590), (-0.150, -0.470),
          (-0.176, -0.470), (-0.174, -0.596), (-0.168, -0.690)])
    ell(-0.181, -0.486, -0.145, -0.436)
    poly([(0.136, -0.748), (0.152, -0.716), (0.168, -0.690), (0.176, -0.596), (0.178, -0.474),
          (0.152, -0.474), (0.138, -0.590), (0.118, -0.700)])
    ell(0.147, -0.490, 0.183, -0.440)
    # 腿：右腿承重伸直，左腿微屈稍向内
    poly([(-0.096, -0.330), (-0.018, -0.330), (-0.026, -0.180), (-0.038, -0.040), (-0.080, -0.040), (-0.086, -0.180)])
    poly([(0.018, -0.330), (0.100, -0.330), (0.094, -0.180), (0.090, -0.040), (0.046, -0.040), (0.036, -0.180)])
    # 鞋（扁平的鞋形）
    rr(-0.094, -0.050, -0.020, 0.000, 0.022)
    rr(0.036, -0.050, 0.110, 0.000, 0.022)
    return m

def concept_P4():
    """海上大鸟居：夕阳下立在海中的朱红大鸟居和倒影，旅人背影静静眺望（逆光剪影 + 轮廓光）"""
    img = vgradient([(0, (255, 140, 90)), (0.56, (255, 206, 140)), (0.57, (230, 140, 110)), (1, (120, 80, 130))])
    img = glow(img, (0.38, 0.40, 0.62, 0.64), (255, 238, 190), strength=220, blur=0.03)
    d = ImageDraw.Draw(img)
    vermilion = (226, 60, 40)
    red_torii(d, S*0.46, S*0.24, S*0.62, S*0.33, vermilion)
    refl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(refl)
    red_torii(rd, S*0.46, S*0.24, S*0.62, S*0.33, (226, 60, 40, 255), dark=(60, 30, 30, 255))
    refl = refl.transpose(Image.FLIP_TOP_BOTTOM).resize((S, int(S*0.6)))
    refl.putalpha(refl.split()[3].point(lambda a: int(a * 0.35)))
    img.paste(refl, (0, int(S*0.57 - S*0.6*0.43)), refl)
    d = ImageDraw.Draw(img)
    for i in range(10):  # 水面波纹
        y = S*0.62 + i * S*0.035
        d.line([(S*0.12 + i*20, y), (S*0.80 - i*15, y)], fill=(255, 220, 190), width=4)

    # 湿润的沙滩：从暖紫过渡，靠近水边反射天光
    shore = vgradient([(0, (150, 96, 120)), (0.86, (150, 96, 120)), (0.90, (112, 70, 104)), (1, (70, 44, 76))])
    shore_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shore_mask).polygon([(0, S*0.875), (S*0.55, S*0.905), (S, S*0.86), (S, S), (0, S)], fill=255)
    img = Image.composite(shore, img, shore_mask)
    d = ImageDraw.Draw(img)
    d.line([(0, S*0.875), (S*0.55, S*0.905), (S, S*0.86)], fill=(255, 196, 150), width=6)   # 水线高光

    cx, feet, h = S*0.765, S*0.965, S*0.44
    fig = figure_mask(cx, feet, h)

    # 1) 湿沙上的倒影（压扁、模糊、半透明）
    refl_fig = fig.transpose(Image.FLIP_TOP_BOTTOM)
    refl_fig = refl_fig.crop((0, int(S - feet), S, S)).resize((S, int((feet) * 0.16)))
    rlayer = Image.new("L", (S, S), 0)
    rlayer.paste(refl_fig, (0, int(feet)))
    rlayer = rlayer.filter(ImageFilter.GaussianBlur(S*0.006)).point(lambda a: int(a * 0.45))
    img = Image.composite(Image.new("RGB", (S, S), (84, 48, 82)), img, rlayer)

    # 2) 周身柔和的夕阳光晕
    halo = fig.filter(ImageFilter.GaussianBlur(S*0.03)).point(lambda a: int(a * 0.28))
    img = Image.composite(Image.new("RGB", (S, S), (255, 196, 140)), img, halo)

    # 3) 朝向夕阳一侧（左侧）的轮廓光：剪影向左偏移后与原形相减
    shifted = Image.new("L", (S, S), 0)
    shifted.paste(fig, (-int(S*0.0045), -int(S*0.0015)))
    rim = Image.composite(Image.new("L", (S, S), 0), shifted, fig)       # shifted 减去 fig
    rim = rim.filter(ImageFilter.GaussianBlur(S*0.0015))
    img = Image.composite(Image.new("RGB", (S, S), (255, 214, 160)), img, rim)

    # 4) 剪影本体：自上而下由暖紫到深紫（与岸边、倒影同一色系）
    body = vgradient([(0, (118, 70, 96)), (0.55, (118, 70, 96)), (0.75, (92, 52, 82)), (1, (58, 34, 62))])
    img = Image.composite(body, img, fig)

    # 5) 小背包：同色系、略亮一点，并带一道轮廓光
    d = ImageDraw.Draw(img)
    bx0, by0, bx1, by1 = cx - h*0.088, feet - h*0.752, cx + h*0.088, feet - h*0.540
    d.rounded_rectangle((bx0, by0, bx1, by1), radius=h*0.036, fill=(134, 84, 106))
    d.rounded_rectangle((bx0, by0 + h*0.024, bx0 + h*0.007, by1 - h*0.024), radius=h*0.004, fill=(236, 176, 138))
    d.rounded_rectangle((bx0 + h*0.03, by0 + h*0.10, bx1 - h*0.03, by1 - h*0.03), radius=h*0.02, fill=(122, 74, 98))
    # 背包肩带
    d.line([(cx - h*0.070, by0 + h*0.005), (cx - h*0.095, feet - h*0.790)], fill=(134, 84, 106), width=int(h*0.014))
    d.line([(cx + h*0.070, by0 + h*0.005), (cx + h*0.095, feet - h*0.790)], fill=(134, 84, 106), width=int(h*0.014))
    return img

def concept_P5():
    """千本鸟居：一条朱红鸟居隧道延伸向光亮处，小人站在路中央"""
    img = Image.new("RGB", (S, S), (40, 18, 14))
    d = ImageDraw.Draw(img)
    cx, cy = S*0.5, S*0.46        # 消失点
    n = 14
    for i in range(n, -1, -1):    # 从远到近
        t = (i / n) ** 1.8
        w = S * (0.10 + 1.25 * (1 - t))
        h = w * 1.05
        top = cy - h * 0.48
        shade = lerp((255, 120, 60), (200, 40, 24), 1 - t)
        k = w / 1000
        d.rectangle((cx - w/2, top, cx + w/2, top + 60*k), fill=(30, 20, 20))           # 笠木
        d.rectangle((cx - w/2 + 30*k, top + 60*k, cx + w/2 - 30*k, top + 110*k), fill=shade)
        for sx in (-1, 1):
            x = cx + sx * (w/2 - 70*k)
            d.rectangle((x - 50*k, top + 110*k, x + 50*k, top + h), fill=shade)
    img = glow(img, (0.42, 0.36, 0.58, 0.56), (255, 236, 190), strength=230, blur=0.03)
    d = ImageDraw.Draw(img)
    d.polygon([(S*0.47, S*0.70), (S*0.53, S*0.70), (S*0.90, S), (S*0.10, S)], fill=(120, 96, 80))   # 石板路
    person(d, S*0.5, S*0.95, S*0.40, (24, 14, 14), pack=(70, 150, 230))
    return img

def concept_P6():
    """海边道口：江之电式的海边道口，蓝天大海，小人站在坡上"""
    img = vgradient([(0, (110, 190, 250)), (0.5, (200, 230, 255)), (0.51, (40, 140, 210)), (0.66, (60, 160, 220)), (0.67, (230, 220, 200)), (1, (200, 190, 170))])
    d = ImageDraw.Draw(img)
    d.ellipse((S*0.72, S*0.10, S*0.88, S*0.26), fill=(255, 246, 210))
    # 铁轨
    for y in (S*0.72, S*0.78):
        d.rectangle((0, y, S, y + S*0.012), fill=(110, 100, 100))
    for x in range(0, S, int(S*0.06)):
        d.rectangle((x, S*0.70, x + S*0.025, S*0.81), fill=(150, 120, 100))
    # 道口标志
    px = S*0.24
    d.rectangle((px - S*0.012, S*0.28, px + S*0.012, S*0.86), fill=(40, 40, 46))
    for ang in (35, -35):
        bar = Image.new("RGBA", (int(S*0.30), int(S*0.05)), (250, 204, 40, 255))
        bd = ImageDraw.Draw(bar)
        st = int(S*0.03)
        for x in range(-bar.height, bar.width, st * 2):
            bd.polygon([(x, bar.height), (x + bar.height, 0), (x + bar.height + st, 0), (x + st, bar.height)], fill=(30, 30, 36, 255))
        bar = bar.rotate(ang, expand=True, resample=Image.BICUBIC)
        img.paste(bar, (int(px - bar.width/2), int(S*0.30 - bar.height/2)), bar)
    d = ImageDraw.Draw(img)
    for x, c in ((px - S*0.06, (236, 50, 50)), (px + S*0.06, (110, 30, 30))):
        d.ellipse((x - S*0.035, S*0.42, x + S*0.035, S*0.49), fill=c)
    d.rectangle((px - S*0.06, S*0.448, px + S*0.06, S*0.462), fill=(40, 40, 46))
    person(d, S*0.66, S*0.98, S*0.44, (30, 40, 70), pack=(236, 90, 70))
    return img

def concept_P7():
    """大红灯笼：寺门下巨大的红灯笼，小人站在灯笼下"""
    img = vgradient([(0, (250, 236, 214)), (1, (236, 210, 180))])
    d = ImageDraw.Draw(img)
    gate = (150, 30, 26)
    d.rectangle((0, 0, S, S*0.10), fill=(50, 40, 40))                 # 屋檐
    d.rectangle((S*0.04, S*0.10, S*0.16, S), fill=gate)               # 左柱
    d.rectangle((S*0.84, S*0.10, S*0.96, S), fill=gate)               # 右柱
    d.rectangle((0, S*0.10, S, S*0.15), fill=gate)
    # 灯笼
    lx0, lx1, ly0, ly1 = S*0.26, S*0.74, S*0.20, S*0.66
    d.rounded_rectangle((lx0, ly0, lx1, ly1), radius=S*0.16, fill=(214, 40, 34))
    for i in range(1, 7):  # 竹骨横纹
        y = ly0 + (ly1 - ly0) * i / 7
        d.line([(lx0 + S*0.02, y), (lx1 - S*0.02, y)], fill=(180, 26, 24), width=6)
    d.rectangle((lx0 + S*0.04, ly0 - S*0.04, lx1 - S*0.04, ly0 + S*0.03), fill=(30, 26, 26))
    d.rectangle((lx0 + S*0.04, ly1 - S*0.03, lx1 - S*0.04, ly1 + S*0.04), fill=(30, 26, 26))
    d.rectangle((S*0.49, S*0.15, S*0.51, ly0 - S*0.04), fill=(30, 26, 26))
    d.rectangle((0, S*0.90, S, S), fill=(180, 160, 140))
    person(d, S*0.50, S*0.98, S*0.30, (30, 30, 50), pack=(70, 160, 230))
    return img

def castle(d, cx, base, w, h, wall=(250, 248, 244), roof=(60, 70, 90), stone=(150, 140, 130)):
    d.polygon([(cx - w*0.55, base), (cx + w*0.55, base), (cx + w*0.42, base - h*0.22), (cx - w*0.42, base - h*0.22)], fill=stone)
    y = base - h*0.22
    tiers = [(0.80, 0.20), (0.62, 0.18), (0.46, 0.17), (0.32, 0.16)]
    for tw, th in tiers:
        hh = h * th
        d.rectangle((cx - w*tw*0.40, y - hh*0.75, cx + w*tw*0.40, y), fill=wall)
        d.polygon([(cx - w*tw*0.55, y - hh*0.70), (cx + w*tw*0.55, y - hh*0.70), (cx + w*tw*0.30, y - hh*1.05), (cx - w*tw*0.30, y - hh*1.05)], fill=roof)
        y -= hh
    # 屋脊两端的鱼饰（金）
    d.ellipse((cx - w*0.12, y - h*0.04, cx - w*0.07, y + h*0.01), fill=(230, 190, 80))
    d.ellipse((cx + w*0.07, y - h*0.04, cx + w*0.12, y + h*0.01), fill=(230, 190, 80))

def concept_P8():
    """城与樱：白墙天守阁与盛开的樱花，小人站在护城河边"""
    img = vgradient([(0, (140, 200, 250)), (1, (230, 244, 255))])
    d = ImageDraw.Draw(img)
    castle(d, S*0.42, S*0.70, S*0.70, S*0.62)
    blossoms(d, [(S*x, S*y, S*r) for x, y, r in [(0.02, 0.66, .14), (0.18, 0.72, .12), (0.86, 0.64, .14), (0.98, 0.72, .12),
                 (0.70, 0.74, .10), (0.08, 0.80, .10), (0.92, 0.82, .10)]], [(255, 186, 208), (250, 166, 196), (255, 208, 224)])
    d.rectangle((0, S*0.80, S, S*0.88), fill=(80, 150, 180))   # 护城河
    d.rectangle((0, S*0.88, S, S), fill=(150, 130, 110))
    person(d, S*0.68, S*0.98, S*0.36, (40, 40, 60), pack=(236, 90, 90))
    return img

PEOPLE = {
    "1": ("富士山与樱", concept_P1), "2": ("五重塔与富士", concept_P2), "3": ("东京塔夜景", concept_P3),
    "4": ("海上大鸟居", concept_P4), "5": ("千本鸟居", concept_P5), "6": ("海边道口", concept_P6),
    "7": ("大红灯笼", concept_P7), "8": ("城与樱", concept_P8),
}

CONCEPTS = {
    "A": ("黄昏鸟居", concept_A), "B": ("樱花定位针", concept_B), "C": ("方位罗盘", concept_C),
    "D": ("胶片富士", concept_D), "E": ("彗星夜空", concept_E), "F": ("圣字朱印", concept_F),
    "G": ("玻璃层叠", concept_G), "H": ("海边道口", concept_H),
}

ALL = {**CONCEPTS, **PEOPLE}

def render(key):
    return ALL[key][1]().resize((1024, 1024), Image.LANCZOS).convert("RGB")

def squircle_mask(size, radius_ratio=0.2237):
    m = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=int(size * 4 * radius_ratio), fill=255)
    return m.resize((size, size), Image.LANCZOS)

def contact_sheet(path, concepts=None):
    concepts = concepts or CONCEPTS
    cell, pad, label_h = 360, 48, 70
    cols, rows = 4, 2
    W = cols * cell + (cols + 1) * pad
    H = rows * (cell + label_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (W, H), (242, 242, 247))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", 32)
    mask = squircle_mask(cell)
    for i, key in enumerate(concepts):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = pad + r * (cell + label_h + pad)
        icon = render(key).resize((cell, cell), Image.LANCZOS)
        shadow = Image.new("L", (cell + 40, cell + 40), 0)
        ImageDraw.Draw(shadow).rounded_rectangle((20, 28, cell + 20, cell + 28), radius=int(cell * 0.2237), fill=70)
        shadow = shadow.filter(ImageFilter.GaussianBlur(12))
        sheet.paste((200, 200, 210), (x - 20, y - 20), shadow)
        sheet.paste(icon, (x, y), mask)
        text = f"{key}  {concepts[key][0]}"
        tw = d.textlength(text, font=font)
        d.text((x + (cell - tw) / 2, y + cell + 18), text, font=font, fill=(40, 40, 50))
    sheet.save(path)
    print("wrote", path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet")
    ap.add_argument("--set", choices=["symbols", "people"], default="people", help="对比图使用哪一批方案")
    ap.add_argument("--concept", choices=list(ALL))
    a = ap.parse_args()
    if a.sheet:
        contact_sheet(a.sheet, PEOPLE if a.set == "people" else CONCEPTS)
    if a.concept:
        img = render(a.concept)
        os.makedirs(os.path.dirname(APPICON), exist_ok=True)
        img.save(APPICON, "PNG")
        print("wrote", APPICON, img.size, img.mode, "concept", a.concept)

if __name__ == "__main__":
    main()
