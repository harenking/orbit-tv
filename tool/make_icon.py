"""Ritar Orbit-ikonen och TV-bannern och lägger dem i den genererade Android-mappen (körs i bygget)."""
from PIL import Image, ImageDraw, ImageFilter
import math, os

def icon(size=1024):
    S = size
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # bakgrund: mörk gradient i rundad ruta
    bg = Image.new('RGBA', (S, S))
    px = bg.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S)
            px[x, y] = (int(18 + 40 * t), int(14 + 10 * t), int(46 + 90 * t), 255)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
    img.paste(bg, (0, 0), mask)
    # glöd bakom planeten
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S*0.30, S*0.30, S*0.70, S*0.70], fill=(140, 110, 255, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.07))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    c = S / 2
    # planet
    r = S * 0.17
    d.ellipse([c - r, c - r, c + r, c + r], fill=(236, 230, 255, 255))
    # omloppsbana (lutad ellips) – ritas som lager så att den går bakom/framför planeten
    def ring(front):
        layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        a, b, ang = S * 0.40, S * 0.15, math.radians(-28)
        pts = []
        for i in range(0, 361):
            t = math.radians(i)
            x, y = a * math.cos(t), b * math.sin(t)
            pts.append((c + x * math.cos(ang) - y * math.sin(ang), c + x * math.sin(ang) + y * math.cos(ang), math.sin(t)))
        for p, q in zip(pts, pts[1:]):
            if (p[2] >= 0) == front:
                w = int(S * 0.035)
                ld.line([p[:2], q[:2]], fill=(124, 92, 255, 255), width=w)
                ld.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(124, 92, 255, 255))
        return layer
    img = Image.alpha_composite(img, ring(False))
    d = ImageDraw.Draw(img)
    d.ellipse([c - r, c - r, c + r, c + r], fill=(236, 230, 255, 255))
    img = Image.alpha_composite(img, ring(True))
    # måne på banan
    a, b, ang, t = S * 0.40, S * 0.15, math.radians(-28), math.radians(35)
    x, y = a * math.cos(t), b * math.sin(t)
    mx, my = c + x * math.cos(ang) - y * math.sin(ang), c + x * math.sin(ang) + y * math.cos(ang)
    m = S * 0.05
    ImageDraw.Draw(img).ellipse([mx - m, my - m, mx + m, my + m], fill=(255, 214, 102, 255))
    return img

base = icon(1024)
res = 'android/app/src/main/res'
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    d = f'{res}/mipmap-{name}'
    os.makedirs(d, exist_ok=True)
    base.resize((px, px), Image.LANCZOS).save(f'{d}/ic_launcher.png')

# TV-banner (320x180 dp → 640x360 i xhdpi)
W, H = 640, 360
ban = Image.new('RGBA', (W, H))
bp = ban.load()
for y in range(H):
    for x in range(W):
        t = (x / W * 0.7 + y / H * 0.3)
        bp[x, y] = (int(14 + 30 * t), int(12 + 10 * t), int(38 + 80 * t), 255)
ic = base.resize((200, 200), Image.LANCZOS)
ban.alpha_composite(ic, (60, 80))
from PIL import ImageFont
try:
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 78)
    small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 28)
except Exception:
    font = small = ImageFont.load_default()
dd = ImageDraw.Draw(ban)
dd.text((290, 112), 'Orbit', font=font, fill=(255, 255, 255, 255))
dd.text((294, 205), 'IPTV', font=small, fill=(190, 175, 255, 255))
d = f'{res}/drawable-xhdpi'
os.makedirs(d, exist_ok=True)
ban.convert('RGB').save(f'{d}/banner.png')
print('Ikon och banner skapade')
