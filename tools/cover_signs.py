"""生成插画前，把照片里带字的招牌 / 商标用旁边的背景颜色盖掉，避免 AI 重画出文字或商标。
用法：python3 tools/cover_signs.py 输入 输出 x0,y0,x1,y1 [...]（坐标按原图像素）"""
import sys
from statistics import median
from PIL import Image, ImageFilter

src, dst, boxes = sys.argv[1], sys.argv[2], sys.argv[3:]
im = Image.open(src).convert("RGB")
px = im.load()
W, H = im.size
for b in boxes:
    vertical = b.endswith(":v")          # “:v” 表示取方框上下的颜色（例如电线杆上的招牌）
    x0, y0, x1, y1 = map(int, b.rstrip(":v").split(","))
    samples = []
    if vertical:
        for x in range(x0, x1):
            for y in list(range(max(0, y0 - 4), y0 - 1)) + list(range(y1 + 1, min(H, y1 + 4))):
                samples.append(px[x, y])
    else:
        # 取方框左右两侧外面 3 像素的颜色中位数作为填充色
        for y in range(y0, y1):
            for x in list(range(max(0, x0 - 4), x0 - 1)) + list(range(x1 + 1, min(W, x1 + 4))):
                samples.append(px[x, y])
    fill = tuple(int(median(c[i] for c in samples)) for i in range(3)) if samples else (200, 200, 200)
    im.paste(fill, (x0, y0, x1, y1))
    # 边缘稍微柔化，不留硬边
    region = (max(0, x0 - 2), max(0, y0 - 2), min(W, x1 + 2), min(H, y1 + 2))
    im.paste(im.crop(region).filter(ImageFilter.GaussianBlur(1.2)), region[:2])
im.save(dst, quality=95)
print("covered", len(boxes), "areas")
