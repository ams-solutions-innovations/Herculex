"""
Generates all Android, Wear OS, and app icons from assets/images/app_icon_master.png.

Usage:
  python scripts/generate_icons.py
"""
import os
import shutil
from PIL import Image

MASTER_PATH = "assets/images/app_icon_master.png"

SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

def extract_foreground(master: Image.Image) -> Image.Image:
    """Extract bright cyan/blue H-mark onto transparent background."""
    img = master.convert("RGBA")
    data = img.getdata()
    new_data = []
    for r, g, b, a in data:
        # Match mark: bright blue/cyan; navy background is excluded
        if b > 82 and g > 52 and b > r * 1.8:
            new_data.append((r, g, b, 255))
        else:
            new_data.append((0, 0, 0, 0))
    fg = Image.new("RGBA", img.size)
    fg.putdata(new_data)
    return fg

def extract_monochrome(fg: Image.Image) -> Image.Image:
    """White silhouette with same alpha."""
    data = fg.getdata()
    new_data = []
    for r, g, b, a in data:
        if a > 0:
            new_data.append((255, 255, 255, a))
        else:
            new_data.append((0, 0, 0, 0))
    mono = Image.new("RGBA", fg.size)
    mono.putdata(new_data)
    return mono

def generate():
    if not os.path.exists(MASTER_PATH):
        print(f"Error: Master icon not found at {MASTER_PATH}")
        return

    master = Image.open(MASTER_PATH).convert("RGBA")
    print(f"Loaded master icon: {master.size}")

    foreground = extract_foreground(master)
    monochrome = extract_monochrome(foreground)

    # Save assets/images artifacts
    master.save("assets/images/logo.png", "PNG")
    master.save("assets/images/app_icon_ios.png", "PNG")
    foreground.save("assets/images/app_icon_foreground.png", "PNG")
    monochrome.save("assets/images/app_icon_monochrome.png", "PNG")
    monochrome.save("assets/images/app_icon_ios_dark.png", "PNG")
    monochrome.save("assets/images/app_icon_ios_tinted.png", "PNG")
    print("Updated assets/images icons.")

    res_dirs = [
        "android/app/src/main/res",
        "android/wear/src/main/res",
    ]

    adaptive_xml_content = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="16%" />
  </foreground>
  <monochrome>
      <inset
          android:drawable="@drawable/ic_launcher_monochrome"
          android:inset="16%" />
  </monochrome>
</adaptive-icon>
"""

    for res_dir in res_dirs:
        if not os.path.exists(res_dir):
            continue
        print(f"\nProcessing {res_dir}...")

        # Mipmaps (full master image scaled)
        for density, size in SIZES.items():
            mipmap_dir = os.path.join(res_dir, f"mipmap-{density}")
            os.makedirs(mipmap_dir, exist_ok=True)
            resized = master.resize((size, size), Image.LANCZOS)
            for name in ["ic_launcher.png", "ic_launcher_round.png", "launcher_icon.png", "launcher_icon_round.png"]:
                dest = os.path.join(mipmap_dir, name)
                resized.save(dest, "PNG")
            print(f"  Saved mipmap-{density} ({size}x{size})")

        # Adaptive drawables (foreground & monochrome)
        for density, size in ADAPTIVE_SIZES.items():
            drawable_dir = os.path.join(res_dir, f"drawable-{density}")
            os.makedirs(drawable_dir, exist_ok=True)
            fg_resized = foreground.resize((size, size), Image.LANCZOS)
            mono_resized = monochrome.resize((size, size), Image.LANCZOS)

            for name in ["ic_launcher_foreground.png", "launcher_icon_foreground.png"]:
                fg_resized.save(os.path.join(drawable_dir, name), "PNG")
            for name in ["ic_launcher_monochrome.png", "launcher_icon_monochrome.png"]:
                mono_resized.save(os.path.join(drawable_dir, name), "PNG")
            print(f"  Saved drawable-{density} ({size}x{size})")

        # Adaptive XML in mipmap-anydpi-v26
        anydpi_dir = os.path.join(res_dir, "mipmap-anydpi-v26")
        os.makedirs(anydpi_dir, exist_ok=True)
        for xml_name in ["ic_launcher.xml", "ic_launcher_round.xml", "launcher_icon.xml", "launcher_icon_round.xml"]:
            xml_path = os.path.join(anydpi_dir, xml_name)
            with open(xml_path, "w", encoding="utf-8") as f:
                f.write(adaptive_xml_content)
        print(f"  Updated adaptive XMLs in {anydpi_dir}")

    print("\nAll icons generated successfully without any legacy Flutter logos!")

if __name__ == "__main__":
    generate()
