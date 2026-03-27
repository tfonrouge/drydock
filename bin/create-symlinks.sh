#!/bin/sh
# Create Drydock-named aliases for Make-built Harbour binaries.
#
# Some tools (hbmk2, hbrun) check argv[0] to determine their operating mode,
# so they cannot be renamed. For those we create wrapper scripts that exec
# the original binary. For tools that don't check argv[0] (harbour, hbtest,
# hbpp, hbi18n, hbformat) we can use simple symlinks.
#
# After running:
#   drydock   (symlink → harbour)         — compiler doesn't check argv[0]
#   ddmake    (wrapper → hbmk2)           — hbmk2 checks argv[0]
#   ddtest    (symlink → hbtest)          — doesn't check argv[0]
#   ddrun     (wrapper → hbrun)           — hbrun checks argv[0]
#   ddpp      (symlink → hbpp)            — doesn't check argv[0]
#   ddi18n    (symlink → hbi18n)          — doesn't check argv[0]
#   ddformat  (symlink → hbformat)        — doesn't check argv[0]
#
# Usage: bin/create-symlinks.sh [bin_dir]

BIN_DIR="${1:-bin/linux/gcc}"

if [ ! -d "$BIN_DIR" ]; then
    echo "Directory not found: $BIN_DIR" >&2
    exit 1
fi

# Create a symlink (for tools that don't check argv[0])
create_symlink() {
    local old="$1" new="$2"
    if [ -f "$BIN_DIR/$old" ] || [ -L "$BIN_DIR/$old" ]; then
        ln -sf "$old" "$BIN_DIR/$new"
        echo "  $new -> $old (symlink)"
    fi
}

# Create a wrapper script (for tools that check argv[0])
create_wrapper() {
    local old="$1" new="$2"
    if [ -f "$BIN_DIR/$old" ] || [ -L "$BIN_DIR/$old" ]; then
        cat > "$BIN_DIR/$new" << WRAPPER
#!/bin/sh
exec "\$(dirname "\$0")/$old" "\$@"
WRAPPER
        chmod +x "$BIN_DIR/$new"
        echo "  $new -> $old (wrapper)"
    fi
}

echo "Creating Drydock aliases in $BIN_DIR:"
create_symlink harbour    drydock
create_wrapper hbmk2      ddmake
create_symlink hbtest     ddtest
create_wrapper hbrun      ddrun
create_symlink hbpp       ddpp
create_symlink hbi18n     ddi18n
create_symlink hbformat   ddformat
