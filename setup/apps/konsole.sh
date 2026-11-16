#!/usr/bin/env bash

# konsole.sh
# Installs Viresta's translucent Konsole profile and enables KWin blur.

install_konsole_appearance() {
    local source_dir="$CONFIG_SOURCE_DIR/konsole"
    local profile_dir="$DATA_DIR/konsole"
    local target relative backup

    for target in "$CONFIG_DIR/konsolerc" "$profile_dir/Viresta.profile" "$profile_dir/Viresta Dark.colorscheme"; do
        [ -e "$target" ] || continue
        relative="${target#"$HOME"/}"
        backup="$BACKUP_DIR/$relative"
        [ -e "$backup" ] && continue
        mkdir -p "$(dirname "$backup")"
        cp -a "$target" "$backup"
    done

    install_file "$source_dir/Viresta.profile" "$profile_dir/Viresta.profile"
    install_file "$source_dir/Viresta Dark.colorscheme" "$profile_dir/Viresta Dark.colorscheme"
    kwriteconfig6 --file "$CONFIG_DIR/konsolerc" --group "Desktop Entry" \
        --key DefaultProfile Viresta.profile
    kwriteconfig6 --file "$CONFIG_DIR/kwinrc" --group Plugins --key blurEnabled true
    kwriteconfig6 --file "$CONFIG_DIR/kwinrc" --group Effect-blur --key BlurStrength 6
}
