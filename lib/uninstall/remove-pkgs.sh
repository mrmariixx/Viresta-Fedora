#!/usr/bin/env bash

# remove-pkgs.sh
# Removes packages and brings back KDE's themes, for uninstall.sh.

# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------

# Exist only for Viresta, so they go whatever the answer about apps is.
VIRESTA_PACKAGES=(vicinae-bin plasma6-applets-panel-colorizer starship blesh-git bash-completion)

# ------------------------------------------------------------
# Removing
# ------------------------------------------------------------

# Leaves out what stays, like what was there before Viresta. Plain KDE needs a file
# manager, and the package lists have no other than Dolphin. A listed name can be an
# alias, like outfit-font for otf-outfit, and pacman only removes by the real name.
packages_to_remove() {
    local pkg real

    {
        if [ "$PKG_BACKEND" = "dnf" ]; then
            printf '%s\n' starship bash-completion
        else
            printf '%s\n' "${VIRESTA_PACKAGES[@]}"
        fi
        if [ "$REMOVE_APPS" -eq 1 ]; then
            if [ "$PKG_BACKEND" = "dnf" ]; then
                read_package_list "$(package_list_path apps/rpm)"
                read_package_list "$(package_list_path apps/flatpak)"
                read_package_list "$(package_list_path apps/gaming)"
                read_package_list "$(package_list_path apps/gaming-flatpak)"
            else
                read_package_list "$SCRIPT_DIR/packages/apps/pacman.txt"
                read_package_list "$SCRIPT_DIR/packages/apps/aur.txt"
                read_package_list "$SCRIPT_DIR/packages/apps/gaming.txt"
            fi
            # Apps Viresta stopped including that the user kept, which are still its own.
            [ ! -f "$KEPT_APPS_FILE" ] || cat "$KEPT_APPS_FILE"
        fi
    } | sort -u | while IFS= read -r pkg; do
        real="$(package_installed_name "$pkg")" || continue
        if [ "$real" != "dolphin" ] && ! grep -qxF "$real" "$PACKAGES_BEFORE_FILE" 2>/dev/null; then
            printf '%s\n' "$real"
        fi
    done
}

# One at a time, since one package that something else needs would stop the rest. If
# Konsole cannot be installed, Kitty stays so there is still a terminal.
remove_packages() {
    local -a pkgs=()
    local pkg

    mapfile -t pkgs < <(packages_to_remove)

    for pkg in "${pkgs[@]}"; do
        if [ "$pkg" = "kitty" ] && ! run_package_manager -S --needed --noconfirm konsole; then
            failure "Could not install Konsole, so Kitty was kept as your terminal"
            continue
        fi
        run_package_manager -Rs --noconfirm "$pkg" || failure "$pkg was kept - other packages may need it"
    done
}

# ------------------------------------------------------------
# KDE's themes
# ------------------------------------------------------------

# Reinstalling brings back the themes Viresta removed and the default cursor file.
restore_removed_themes() {
    local -a pkgs=()
    local pkg

    prepare_package_manager

    for pkg in "${REMOVED_THEMES_PACKAGES[@]}" default-cursors; do
        if is_installed "$pkg"; then
            pkgs+=("$pkg")
        fi
    done
    [ "${#pkgs[@]}" -gt 0 ] || return 0

    if run_package_manager -S --noconfirm "${pkgs[@]}"; then
        return 0
    fi
    if [ "$PKG_BACKEND" = "dnf" ]; then
        failure "Could not bring back KDE's themes. To try again: sudo dnf install ${pkgs[*]}"
    else
        failure "Could not bring back KDE's themes. To try again: sudo pacman -S ${pkgs[*]}"
    fi
}
