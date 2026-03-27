#!/bin/sh
# Create legacy compatibility symlinks after a Make build.
# Make produces the old Harbour names (harbour, hbmk2, etc.).
# This script renames them to Drydock names and creates legacy symlinks.
#
# After running:
#   drydock   (real binary, renamed from harbour)
#   harbour   (legacy symlink → drydock)
#   ddmake    (real binary, renamed from hbmk2)
#   hbmk2     (legacy symlink → ddmake)
#   ...
#
# The zig build already produces Drydock names directly.
# This script is only needed for the legacy Make build.
#
# Usage: bin/create-symlinks.sh [bin_dir]

BIN_DIR="${1:-bin/linux/gcc}"

if [ ! -d "$BIN_DIR" ]; then
    echo "Directory not found: $BIN_DIR" >&2
    exit 1
fi

# Rename real binary to new name, create legacy symlink with old name
rename_binary() {
    local old="$1" new="$2"
    if [ -f "$BIN_DIR/$old" ] && [ ! -L "$BIN_DIR/$old" ]; then
        mv "$BIN_DIR/$old" "$BIN_DIR/$new"
        ln -sf "$new" "$BIN_DIR/$old"
        echo "  $old -> $new (renamed + legacy symlink)"
    elif [ -L "$BIN_DIR/$old" ] && [ -f "$BIN_DIR/$new" ]; then
        echo "  $new (already renamed)"
    fi
}

echo "Renaming Make binaries to Drydock names in $BIN_DIR:"
rename_binary harbour    drydock
rename_binary hbmk2      ddmake
rename_binary hbtest     ddtest
rename_binary hbrun      ddrun
rename_binary hbpp       ddpp
rename_binary hbi18n     ddi18n
rename_binary hbformat   ddformat
