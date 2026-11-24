"""Ritar Orbit-ikonen och TV-bannern och lägger dem i den genererade Android-mappen (körs i bygget)."""
from PIL import Image, ImageDraw, ImageFilter
import math, os

A, B, C = (91, 124, 255), (180, 92, 255), (255, 111, 177)

def grad(S, t0=(0, 1), t1=(1, 0)):
    """Diagonal gradient A->B->C (nere till vänster -> uppe till höger)."""
    g = Image.new('RGBA', (S, S))
    px = g.load()
    for y in range(S):
        for x in range(S):
            t = (x / S + (1 - y / S)) / 2
            if t < 0.5:
                u = t / 0.5; a, b = A, B
            else:
                u = (t - 0.5) / 0.5; a, b = B, C
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,)
    return g

def mark(S):
    """Omloppsbana + satellit + play-symbol (samma som OrbitMark i appen). Ritas 4x och skalas ner."""
    Z = S * 4
    img = Image.new('RGBA', (Z, Z), (0, 0, 0, 0))
    c = Z / 2; r = Z * 0.39; w = Z * 0.115
    sat = -45; gap = math.degrees(0.95)
    m = Image.new('L', (Z, Z), 0)
    md = ImageDraw.Draw(m)
    box = [c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2]
    md.arc(box, sat + gap / 2, sat + 360 - gap / 2, fill=255, width=int(w))
    for ang in (sat + gap / 2, sat - gap / 2):
        x, y = c + r * math.cos(math.radians(ang)), c + r * math.sin(math.radians(ang))
        md.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
    img.paste(grad(Z), (0, 0), m)
    d = ImageDraw.Draw(img)
    h = r * 0.95; cx = c + r * 0.08
    tri = [(cx - h * 0.38, c - h * 0.5), (cx + h * 0.52, c), (cx - h * 0.38, c + h * 0.5)]
    d.polygon(tri, fill=(255, 255, 255, 255))
    lw = int(Z * 0.05)
    d.line(tri + [tri[0]], fill=(255, 255, 255, 255), width=lw, joint='curve')
    for x, y in tri:
        d.ellipse([x - lw / 2, y - lw / 2, x + lw / 2, y + lw / 2], fill=(255, 255, 255, 255))
    sx, sy = c + r * math.cos(math.radians(sat)), c + r * math.sin(math.radians(sat))
    glow = Image.new('RGBA', (Z, Z), (0, 0, 0, 0))
    gr = w * 1.1
    ImageDraw.Draw(glow).ellipse([sx - gr, sy - gr, sx + gr, sy + gr], fill=C + (130,))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.5))
    img = Image.alpha_composite(glow, img)
    sr = w * 0.62
    ImageDraw.Draw(img).ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=(255, 255, 255, 255))
    return img.resize((S, S), Image.LANCZOS)

def icon(size=1024):
    S = size
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    bg = Image.new('RGBA', (S, S))
    px = bg.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S)
            px[x, y] = (int(11 + 22 * t), int(13 + 6 * t), int(23 + 45 * t), 255)
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
    img.paste(bg, (0, 0), mask)
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([S * 0.22, S * 0.22, S * 0.78, S * 0.78], fill=(124, 92, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.09))
    glow.putalpha(Image.composite(glow.getchannel('A'), Image.new('L', (S, S), 0), mask))
    img = Image.alpha_composite(img, glow)
    mk = mark(int(S * 0.74))
    img.alpha_composite(mk, (int(S * 0.13), int(S * 0.13)))
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
        bp[x, y] = (int(11 + 20 * t), int(13 + 6 * t), int(23 + 42 * t), 255)
g = Image.new('RGBA', (W, H), (0, 0, 0, 0))
ImageDraw.Draw(g).ellipse([40, 60, 280, 300], fill=(124, 92, 255, 80))
ban.alpha_composite(g.filter(ImageFilter.GaussianBlur(40)))
ban.alpha_composite(mark(190), (56, 85))
from PIL import ImageFont
def font(bold, size):
    for f in (['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 'C:/Windows/Fonts/segoeuib.ttf'] if bold else ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 'C:/Windows/Fonts/segoeui.ttf']):
        try:
            return ImageFont.truetype(f, size)
        except Exception:
            pass
    return ImageFont.load_default()
big, small = font(True, 92), font(True, 34)
dd = ImageDraw.Draw(ban)
x0, y0 = 272, 120
dd.text((x0, y0), 'Orbit', font=big, fill=(255, 255, 255, 255))
tw = dd.textbbox((x0, y0), 'Orbit', font=big)
px0, py0 = tw[2] + 14, tw[1] + 8
pill = Image.new('L', (W, H), 0)
pw = dd.textbbox((0, 0), 'TV', font=small)
bw, bh = pw[2] - pw[0] + 24, 48
ImageDraw.Draw(pill).rounded_rectangle([px0, py0, px0 + bw, py0 + bh], radius=10, fill=255)
gp = grad(W).crop((0, 0, W, H))
ban.paste(gp, (0, 0), pill)
dd = ImageDraw.Draw(ban)
dd.text((px0 + 12 - pw[0], py0 + (bh - (pw[3] - pw[1])) / 2 - pw[1]), 'TV', font=small, fill=(255, 255, 255, 255))
d = f'{res}/drawable-xhdpi'
os.makedirs(d, exist_ok=True)
ban.convert('RGB').save(f'{d}/banner.png')
print('Ikon och banner skapade')
