#!/bin/sh
# Run by the watch target after Copy Bundle Resources. Use the same source
# illustrations as Android/Flutter, converted to watch-sized PNGs by macOS.
set -eu
source_dir="$SRCROOT/../assets/images/exercises"
target_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ExerciseArtwork"
mkdir -p "$target_dir"
for source in "$source_dir"/*.webp; do
    [ -f "$source" ] || continue
    name=$(basename "$source" .webp)
    target="$target_dir/$name.png"
    if [ ! -f "$target" ] || [ "$source" -nt "$target" ]; then
        /usr/bin/sips --resampleHeightWidthMax 220 -s format png "$source" --out "$target" >/dev/null
    fi
done
