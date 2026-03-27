#!/bin/sh
# Create drydock binary name symlinks alongside the harbour-named originals.
# Run after `make` to add the new names.
# Usage: bin/create-symlinks.sh [bin_dir]

BIN_DIR="${1:-bin/linux/gcc}"

if [ ! -d "$BIN_DIR" ]; then
    echo "Directory not found: $BIN_DIR" >&2
    exit 1
fi

# Create symlinks: new name → old name
create_link() {
    local old="$1" new="$2"
    if [ -f "$BIN_DIR/$old" ] && [ ! -e "$BIN_DIR/$new" ]; then
        ln -s "$old" "$BIN_DIR/$new"
        echo "  $new -> $old"
    fi
}

echo "Creating Drydock symlinks in $BIN_DIR:"
create_link harbour    drydock
create_link hbmk2      ddmake
create_link hbtest     ddtest
create_link hbrun      ddrun
create_link hbpp       ddpp
create_link hbi18n     ddi18n
create_link hbformat   ddformat
