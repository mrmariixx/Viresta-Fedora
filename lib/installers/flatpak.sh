#!/usr/bin/env bash

# flatpak.sh
# Installs optional Fedora applications distributed through Flathub.

flatpak_install_one() {
    local app="$1" log="$AUR_LOG_DIR/flatpak-${1//\//_}.log"

    if is_installed "$app"; then
        ok "$app already installed"
        return 0
    fi
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "Would install $app from Flathub"
        return 0
    fi

    mkdir -p "$AUR_LOG_DIR"
    info "$app: installing from Flathub"
    if {
        run_logged flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
            && run_logged flatpak install --system -y flathub "$app"
    } >"$log" 2>&1; then
        ok "$app installed"
        return 0
    fi

    failure "$app: install failed - see $log"
    return 1
}

install_flatpak_apps() {
    local app

    command -v flatpak >/dev/null 2>&1 || {
        warn "Flatpak is unavailable; skipping Flathub apps"
        return 0
    }
    while IFS= read -r app; do
        flatpak_install_one "$app" || true
    done < <(read_package_list "$(package_list_path apps/flatpak)")
}
