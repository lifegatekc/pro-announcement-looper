#!/usr/bin/env python3
"""Generate simple original app artwork and mock slides, with no image dependencies."""
import struct
import zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

def png(width, height, rectangles, background=(16, 25, 35)):
    rows = []
    for y in range(height):
        row = bytearray(bytes(background) * width)
        for x1, y1, x2, y2, color in rectangles:
            if y1 <= y < y2:
                a, b = max(0, x1), min(width, x2)
                row[a * 3:b * 3] = bytes(color) * max(0, b - a)
        rows.append(b'\0' + row)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')

def artwork(w, h):
    cx, cy = w // 2, h // 2
    sw, sh = min(w * 3 // 5, 440), min(h * 3 // 5, 260)
    x, y = cx - sw // 2, cy - sh // 2
    return png(w, h, [(x-16,y-16,x+sw-16,y+sh-16,(38,75,87)), (x,y,x+sw,y+sh,(76,199,183)), (x+sw//8,y+sh//5,x+sw*4//5,y+sh//3,(16,25,35)), (x+sw//8,y+sh//2,x+sw*3//5,y+sh*3//5,(16,25,35)), (x+sw//8,y+sh*3//4,x+sw*4//5,y+sh*4//5,(16,25,35))])

FONT = {
 'A':['01110','10001','10001','11111','10001','10001','10001'],
 'C':['01111','10000','10000','10000','10000','10000','01111'],
 'E':['11111','10000','10000','11110','10000','10000','11111'],
 'H':['10001','10001','10001','11111','10001','10001','10001'],
 'I':['11111','00100','00100','00100','00100','00100','11111'],
 'L':['10000','10000','10000','10000','10000','10000','11111'],
 'M':['10001','11011','10101','10101','10001','10001','10001'],
 'N':['10001','11001','11001','10101','10011','10011','10001'],
 'O':['01110','10001','10001','10001','10001','10001','01110'],
 'R':['11110','10001','10001','11110','10100','10010','10001'],
 'S':['01111','10000','10000','01110','00001','00001','11110'],
 'T':['11111','00100','00100','00100','00100','00100','00100'],
 'U':['10001','10001','10001','10001','10001','10001','01110'],
 'V':['10001','10001','10001','10001','10001','01010','00100'],
 'W':['10001','10001','10001','10101','10101','10101','01010'],
 'Y':['10001','10001','01010','00100','00100','00100','00100'],
 '1':['00100','01100','00100','00100','00100','00100','01110'],
 '2':['01110','10001','00001','00010','00100','01000','11111'],
 '3':['11110','00001','00001','01110','00001','00001','11110'],
}
def text_rects(text, y, scale, color):
    x = (1920 - len(text)*6*scale) // 2
    result = []
    for char in text:
        for row, bits in enumerate(FONT.get(char, [])):
            for col, bit in enumerate(bits):
                if bit == '1': result.append((x+col*scale,y+row*scale,x+(col+1)*scale,y+(row+1)*scale,color))
        x += 6*scale
    return result

def slide(profile, index):
    color = (76,199,183) if profile == 'main' else (194,154,238)
    rects = [(100,100,1820,112,color), (100,968,1820,980,color)]
    rects += text_rects('MAIN SERVICE' if profile == 'main' else 'YOUTH SERVICE', 300, 16, color)
    rects += text_rects('ANNOUNCEMENTS', 500, 12, (240,244,248))
    rects += text_rects(str(index+1), 700, 20, color)
    return png(1920, 1080, rects)

def release_artwork():
    """Export approved artwork. Requires scripts/requirements-artwork.txt only when regenerating."""
    from PIL import Image, ImageDraw, ImageFont
    import os
    source = Image.open(ROOT / 'branding' / 'icon-master.png').convert('RGB')
    (ROOT / 'images').mkdir(exist_ok=True)
    (ROOT / 'images' / 'demo').mkdir(exist_ok=True)
    (ROOT / 'store' / 'artwork').mkdir(parents=True, exist_ok=True)
    for name, size in [('icon-hd',(290,218)),('icon-fhd',(540,405))]:
        source.resize(size, Image.Resampling.LANCZOS).save(ROOT / 'images' / (name+'.png'))
    source.resize((540,405), Image.Resampling.LANCZOS).save(ROOT / 'store/artwork/player-poster-540x405.png')
    source.resize((540,405), Image.Resampling.LANCZOS).save(ROOT / 'store/artwork/screensaver-poster-540x405.png')
    for name, size in [('splash-hd',(1280,720)),('splash-fhd',(1920,1080))]:
        canvas = Image.new('RGB',size,(16,25,35))
        tile = source.copy()
        tile.thumbnail((int(size[0]*0.8),int(size[1]*0.88)),Image.Resampling.LANCZOS)
        canvas.paste(tile,((size[0]-tile.width)//2,(size[1]-tile.height)//2))
        canvas.save(ROOT / 'images' / (name+'.png'))
    regular = os.environ.get('PAL_FONT_REGULAR','/System/Library/Fonts/Supplemental/Arial.ttf')
    bold = os.environ.get('PAL_FONT_BOLD','/System/Library/Fonts/Supplemental/Arial Bold.ttf')
    font = lambda size, heavy=False: ImageFont.truetype(bold if heavy else regular,size)
    slides = [('WELCOME','A place for every announcement','Loop your slides on the TVs throughout your building.'),
              ('COMING UP','Keep everyone in the loop','Connect ProPresenter, choose a presentation, and press Show now.'),
              ('RIGHT ON TIME','The right message at the right time','Schedule announcements, welcome screens, and check-in notices.')]
    for i,(eyebrow,title,body) in enumerate(slides):
        canvas = Image.new('RGB',(1920,1080),(16,25,35))
        draw = ImageDraw.Draw(canvas)
        draw.rounded_rectangle((110,130,120,870),radius=5,fill=(76,199,183))
        draw.text((180,165),eyebrow,font=font(32,True),fill=(76,199,183))
        draw.text((180,330),title,font=font(75,True),fill='white')
        draw.text((180,475),body,font=font(34),fill=(192,202,212))
        draw.text((180,860),'PRO ANNOUNCEMENT LOOPER  /  OFFLINE DEMO',font=font(26,True),fill=(156,217,208))
        draw.text((180,925),'Sample content bundled with the app. No ProPresenter connection required.',font=font(24),fill=(160,177,192))
        canvas.save(ROOT / 'images/demo' / (str(i)+'.png'))

if __name__ == '__main__':
    release_artwork()
