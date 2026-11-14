#!/usr/bin/env bash

# checks.sh
# Checks the system can run the install.

# ------------------------------------------------------------
# Requirements
# ------------------------------------------------------------

require_non_root() {
    [ "$(id -u)" -ne 0 ] || die "Do not run this installer as root. Run it as your normal user."
}

require_sudo() {
    command -v sudo >/dev/null 2>&1 || die "sudo is required but not installed."
}

detect_distribution() {
    local os_release="${OS_RELEASE_FILE:-/etc/os-release}"

    [ -r "$os_release" ] || die "Could not identify this Linux distribution."
    DISTRO_ID="$(. "$os_release"; printf '%s' "${ID:-}")"
    case "$DISTRO_ID" in
        fedora)
            PKG_BACKEND="dnf"
            DNF_COMMAND="dnf"
            DISTRO_NAME="Fedora Linux"
            command -v dnf5 >/dev/null 2>&1 && DNF_COMMAND="dnf5"
            command -v dnf >/dev/null 2>&1 || command -v dnf5 >/dev/null 2>&1 \
                || die "DNF is required to install packages on Fedora."
            ;;
        arch|cachyos)
            PKG_BACKEND="pacman"
            DISTRO_NAME="Arch Linux"
            command -v pacman >/dev/null 2>&1 || die "pacman is required to install packages."
            ;;
        *) die "This installer supports Fedora Linux, Arch Linux and CachyOS (detected: ${DISTRO_ID:-unknown})." ;;
    esac
}

require_x86_64() {
    [ "$(uname -m)" = "x86_64" ] || die "Only x86_64 is supported (detected: $(uname -m))."
}

# Every install puts this file there, and nothing else does.
viresta_is_installed() {
    [ -e "$HOME/.local/bin/viresta-theme-sync" ] || [ -e "$VIRESTA_STATE_DIR/installed-files" ]
}

# ------------------------------------------------------------
# Internet
# ------------------------------------------------------------

has_internet() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 6 bash -c 'exec 3<>/dev/tcp/example.com/443' 2>/dev/null && return 0
    fi
    command -v ping >/dev/null 2>&1 && ping -c1 -W2 example.com >/dev/null 2>&1 && return 0
    return 1
}

require_internet() {
    has_internet || die "No internet connection detected."
}

# ------------------------------------------------------------
# All checks
# ------------------------------------------------------------

preflight() {
    require_non_root
    require_sudo
    detect_distribution
    require_x86_64
    require_internet
    detect_virt

    ok "$DISTRO_NAME x86_64"
    ok "Internet reachable"
    if [ "$VIRT" = "none" ]; then
        info "Running on bare metal"
    else
        info "Virtual machine detected: $VIRT"
    fi
}
