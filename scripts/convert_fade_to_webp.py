#!/usr/bin/env python3
# Converts assets/images/fade-*.jpg to WebP using Pillow
import os
from PIL import Image

src_dir = 'assets/images'
pattern_prefix = 'fade-'

os.makedirs('assets/backup_fade_images', exist_ok=True)

for fname in os.listdir(src_dir):
    if fname.lower().startswith(pattern_prefix) and fname.lower().endswith(('.jpg', '.jpeg', '.png')):
        src = os.path.join(src_dir, fname)
        dst = os.path.join(src_dir, os.path.splitext(fname)[0] + '.webp')
        backup = os.path.join('assets/backup_fade_images', fname)
        print(f'Converting {src} -> {dst}')
        try:
            # backup
            if not os.path.exists(backup):
                from shutil import copyfile
                copyfile(src, backup)
            img = Image.open(src)
            img.save(dst, 'WEBP', quality=80)
            print('Saved', dst)
        except Exception as e:
            print('Failed', src, e)

print('Done')

