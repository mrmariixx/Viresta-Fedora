#!/usr/bin/env bash

# pacman.sh
# Shared package operations for pacman and DNF systems.

# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------

PACMAN_CONF=""
SYSTEM_PACMAN_CONF="${SYSTEM_PACMAN_CONF:-/etc/pacman.conf}"
PKG_BACKEND="${PKG_BACKEND:-}"
# What was already on the system, so uninstall.sh keeps it.
PACKAGES_BEFORE_FILE="$VIRESTA_STATE_DIR/packages-before"
# What Viresta has offered, so update.sh only adds new ones and does not bring back
# an app the user removed.
KNOWN_PACKAGES_FILE="$VIRESTA_STATE_DIR/known-packages"
# Apps Viresta stopped including that the user chose to keep, so they are not asked again.
KEPT_APPS_FILE="$VIRESTA_STATE_DIR/kept-apps"

# ------------------------------------------------------------
# Pacman
# ------------------------------------------------------------

ensure_package_backend() {
    [ -n "$PKG_BACKEND" ] && return 0
    local os_release="${OS_RELEASE_FILE:-/etc/os-release}" id=""
    [ -r "$os_release" ] && id="$(. "$os_release"; printf '%s' "${ID:-}")"
    case "$id" in
        fedora)
            PKG_BACKEND="dnf"
            DNF_COMMAND="dnf"
            command -v dnf5 >/dev/null 2>&1 && DNF_COMMAND="dnf5"
            ;;
        arch|cachyos) PKG_BACKEND="pacman" ;;
        *) command -v pacman >/dev/null 2>&1 && PKG_BACKEND="pacman" ;;
    esac
}

package_list_path() {
    local list="$1"
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ] && [ -f "$SCRIPT_DIR/packages/fedora/$list.txt" ]; then
        printf '%s\n' "$SCRIPT_DIR/packages/fedora/$list.txt"
    else
        printf '%s\n' "$SCRIPT_DIR/packages/$list.txt"
    fi
}

run_logged() {
    if [ "${VERBOSE:-0}" -eq 0 ]; then
        sudo "$@" >>"$LOG_FILE" 2>&1 </dev/null
        return
    fi
    if command -v script >/dev/null 2>&1; then
        script -q -e -c "sudo $*" /dev/null | tee -a "$LOG_FILE"
    else
        sudo "$@" 2>&1 | tee -a "$LOG_FILE"
    fi
}

cleanup_pacman_conf() {
    [ -n "${PACMAN_CONF:-}" ] || return 0
    rm -f "$PACMAN_CONF" 2>/dev/null || true
    PACMAN_CONF=""
}

# Uses a temporary copy, so the faster downloads only last for the install.
prepare_package_manager() {
    ensure_package_backend
    [ "$PKG_BACKEND" = "pacman" ] || return 0
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "Would download 5 packages at a time"
        return 0
    fi

    # Made again each time, so a repository turned on since then is in the copy too.
    cleanup_pacman_conf
    PACMAN_CONF="$(mktemp /tmp/viresta-pacman.XXXXXX)"
    cp "$SYSTEM_PACMAN_CONF" "$PACMAN_CONF"

    if grep -qE '^[#[:space:]]*ParallelDownloads' "$PACMAN_CONF"; then
        sed -i -E 's|^[#[:space:]]*ParallelDownloads.*|ParallelDownloads = 5|' "$PACMAN_CONF"
    else
        printf '\nParallelDownloads = 5\n' >>"$PACMAN_CONF"
    fi

    register_cleanup cleanup_pacman_conf
    ok "Downloading 5 packages at a time"
}

prepare_pacman_conf() {
    prepare_package_manager
}

# Normally writes only to the log. With --verbose it runs inside a pseudo-terminal
# so progress streams live.
run_package_manager() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        local operation="$1"
        shift
        case "$operation" in
            -S)
                local -a packages=()
                while [ "$#" -gt 0 ]; do
                    case "$1" in --needed|--noconfirm) shift ;; *) packages+=("$1"); shift ;; esac
                done
                [ "${#packages[@]}" -gt 0 ] || return 0
                run_logged "$DNF_COMMAND" install -y "${packages[@]}"
                ;;
            -Syu|-Su)
                run_logged "$DNF_COMMAND" upgrade --refresh -y
                ;;
            -Sy)
                local -a packages=()
                while [ "$#" -gt 0 ]; do
                    case "$1" in --needed|--noconfirm) shift ;; *) packages+=("$1"); shift ;; esac
                done
                [ "${#packages[@]}" -eq 0 ] || run_logged "$DNF_COMMAND" install -y "${packages[@]}"
                ;;
            -Rdd|-Rs|-Rns)
                local -a packages=() flatpaks=()
                while [ "$#" -gt 0 ]; do
                    case "$1" in --noconfirm) shift ;; *) packages+=("$1"); shift ;; esac
                done
                local -a rpm_packages=()
                local pkg
                for pkg in "${packages[@]}"; do
                    if is_flatpak_installed "$pkg"; then
                        flatpaks+=("$pkg")
                    else
                        rpm_packages+=("$pkg")
                    fi
                done
                [ "${#rpm_packages[@]}" -eq 0 ] || run_logged "$DNF_COMMAND" remove -y "${rpm_packages[@]}" || return 1
                [ "${#flatpaks[@]}" -eq 0 ] || run_logged flatpak uninstall -y "${flatpaks[@]}"
                ;;
            *) return 2 ;;
        esac
        return $?
    fi

    local -a args=(pacman)
    if [ -n "${PACMAN_CONF:-}" ]; then
        args+=(--config "$PACMAN_CONF")
    fi
    args+=("$@")

    if [ "$VERBOSE" -eq 0 ]; then
        # The log belongs to the user, so it is written as the user on purpose.
        # shellcheck disable=SC2024
        sudo "${args[@]}" >>"$LOG_FILE" 2>&1 </dev/null
        return
    fi

    if command -v script >/dev/null 2>&1; then
        script -q -e -c "sudo ${args[*]}" /dev/null | tee -a "$LOG_FILE"
    else
        sudo "${args[@]}" 2>&1 | tee -a "$LOG_FILE"
    fi
}

run_pacman() {
    run_package_manager "$@"
}

# ------------------------------------------------------------
# Repositories
# ------------------------------------------------------------

# Steam, Wine and many games need Arch's 32-bit repository, which is off by default. It
# is turned on the Arch Wiki's way, by taking the # off its two lines, and added only if
# those lines are not there. uninstall.sh leaves it on, since anything installed from it
# would stop getting updates.
enable_package_repositories() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        enable_rpmfusion
        return
    fi

    [ -f "$SYSTEM_PACMAN_CONF" ] || return 0
    grep -q '^\[multilib\]' "$SYSTEM_PACMAN_CONF" && return 0

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "Would turn on the multilib repository, for 32-bit apps like Steam"
        return 0
    fi

    sudo sed -i '/^#\[multilib\]$/{N;s/^#\[multilib\]\n#Include/[multilib]\nInclude/}' "$SYSTEM_PACMAN_CONF"
    if ! grep -q '^\[multilib\]' "$SYSTEM_PACMAN_CONF"; then
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$SYSTEM_PACMAN_CONF" >/dev/null
    fi

    if grep -q '^\[multilib\]' "$SYSTEM_PACMAN_CONF"; then
        ok "multilib repository turned on"
    else
        failure "Could not turn on the multilib repository in $SYSTEM_PACMAN_CONF"
    fi
}

enable_multilib() {
    enable_package_repositories
}

enable_rpmfusion() {
    local release
    command -v rpm >/dev/null 2>&1 || { failure "rpm is required to enable RPM Fusion"; return 1; }
    release="$(rpm -E %fedora)"
    [[ "$release" =~ ^[0-9]+$ ]] || { failure "Could not determine the Fedora release for RPM Fusion"; return 1; }
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "Would enable the RPM Fusion free and nonfree repositories"
        return 0
    fi
    run_logged "$DNF_COMMAND" install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${release}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${release}.noarch.rpm" \
        || { failure "Could not enable RPM Fusion repositories"; return 1; }
    ok "RPM Fusion repositories enabled"
}

# ------------------------------------------------------------
# System update
# ------------------------------------------------------------

# multilib comes first, so the update below also downloads its package list.
update_system() {
    enable_package_repositories
    prepare_package_manager

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        if [ "$PKG_BACKEND" = "dnf" ]; then
            info "Would upgrade Fedora packages with $DNF_COMMAND"
        else
            info "Would refresh archlinux-keyring"
        fi
        info "Would run a full system upgrade"
        return 0
    fi

    if [ "$PKG_BACKEND" = "dnf" ]; then
        info "Upgrading Fedora packages"
        run_logged "$DNF_COMMAND" upgrade --refresh -y || die "System upgrade failed."
        ok "System up to date"
        return 0
    fi

    info "Refreshing archlinux-keyring"
    run_package_manager -Sy --needed --noconfirm archlinux-keyring || die "Failed to refresh the keyring."

    info "Upgrading the system"
    run_package_manager -Su --noconfirm || die "System upgrade failed."

    ok "System up to date"
}

# ------------------------------------------------------------
# Package lists
# ------------------------------------------------------------

install_array() {
    local label="$1"
    shift
    local -a pkgs=("$@")

    if [ "${#pkgs[@]}" -eq 0 ]; then
        info "$label: nothing to install"
        return 0
    fi

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "$label: would install ${pkgs[*]}"
        return 0
    fi

    info "$label: ${pkgs[*]}"
    run_package_manager -S --needed --noconfirm "${pkgs[@]}" || die "Failed to install $label."
    ok "$label installed"
}

# One unavailable package can reject the whole transaction, so retry one at a time.
install_array_optional() {
    local label="$1" pkg
    shift

    if [ "$#" -eq 0 ] || [ "${DRY_RUN:-0}" -eq 1 ]; then
        install_array "$label" "$@"
        return 0
    fi

    info "$label: $*"
    if run_package_manager -S --needed --noconfirm "$@"; then
        ok "$label installed"
        return 0
    fi

    for pkg in "$@"; do
        run_package_manager -S --needed --noconfirm "$pkg" || failure "$pkg: install failed - see $LOG_FILE"
    done
}

read_package_list() {
    [ -f "$1" ] || return 0
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# For packages the desktop can work without: failures are listed, not fatal.
install_group_optional() {
    local -a pkgs=()
    mapfile -t pkgs < <(read_package_list "$2")
    install_array_optional "$1" "${pkgs[@]}"
}

# For packages the desktop needs: a failure stops the install.
install_group() {
    local label="$1" file="$2"
    local -a pkgs=()

    mapfile -t pkgs < <(read_package_list "$file")
    install_array "$label" "${pkgs[@]}"
}

# ------------------------------------------------------------
# Package records
# ------------------------------------------------------------

save_packages_before() {
    [ "${DRY_RUN:-0}" -eq 0 ] || return 0
    [ ! -e "$PACKAGES_BEFORE_FILE" ] || return 0
    mkdir -p "$(dirname "$PACKAGES_BEFORE_FILE")"
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        rpm -qa --qf '%{NAME}\n' >"$PACKAGES_BEFORE_FILE" 2>/dev/null || true
    else
        pacman -Qq >"$PACKAGES_BEFORE_FILE" 2>/dev/null || true
    fi
}

# The 32-bit drivers count too, so an update does not bring back one that was removed.
# The Gaming row does not, since updates never add it.
listed_packages() {
    local list
    local drivers_file="$SCRIPT_DIR/packages/drivers/drivers.txt"

    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        for list in system/base system/kde apps/rpm apps/flatpak; do
            read_package_list "$(package_list_path "$list")"
        done
        read_package_list "$(package_list_path system/shell)" | awk 'NF == 2 { print $2 }'
        drivers_file="$SCRIPT_DIR/packages/drivers/fedora.txt"
    else
        for list in system/base system/kde apps/pacman apps/aur; do
            read_package_list "$SCRIPT_DIR/packages/$list.txt"
        done
    fi
    read_package_list "$drivers_file" | awk '$2 ~ /^lib32-/ || $2 ~ /\.i686$/ { print $2 }'
}

# Added to, never started over, so running install.sh again does not forget an app
# Viresta stopped including, which update.sh then offers to remove.
save_known_packages() {
    [ "${DRY_RUN:-0}" -eq 0 ] || return 0
    mkdir -p "$(dirname "$KNOWN_PACKAGES_FILE")"
    {
        [ ! -f "$KNOWN_PACKAGES_FILE" ] || cat "$KNOWN_PACKAGES_FILE"
        listed_packages
    } | sort -u >"$KNOWN_PACKAGES_FILE.new"
    mv "$KNOWN_PACKAGES_FILE.new" "$KNOWN_PACKAGES_FILE"
}

# ------------------------------------------------------------
# Package lookups
# ------------------------------------------------------------

is_installed() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        if is_flatpak_installed "$1"; then
            return 0
        fi
        rpm -q "$1" >/dev/null 2>&1
    else
        pacman -Qq "$1" >/dev/null 2>&1
    fi
}

is_flatpak_installed() {
    flatpak list --app --columns=application 2>/dev/null | grep -qxF "$1"
}

package_installed_name() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        if is_flatpak_installed "$1"; then
            printf '%s\n' "$1"
        else
            rpm -q --qf '%{NAME}\n' "$1" 2>/dev/null | head -n 1
        fi
    else
        pacman -Qq "$1" 2>/dev/null
    fi
}

package_files() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        rpm -ql "$1" 2>/dev/null
    else
        pacman -Qlq "$1" 2>/dev/null
    fi
}

pkg_source() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        if [[ "$1" == *.i686 ]]; then
            if "$DNF_COMMAND" repoquery --available --qf '%{name}.%{arch}' "$1" 2>/dev/null | grep -qxF "$1"; then
                printf 'repo\n'
            elif grep -qxF "$1" "$(package_list_path apps/flatpak)" 2>/dev/null; then
                printf 'flatpak\n'
            else
                printf 'unsupported\n'
            fi
        elif "$DNF_COMMAND" repoquery --available --qf '%{name}' "$1" 2>/dev/null | grep -qxF "$1"; then
            printf 'repo\n'
        elif grep -qxF "$1" "$(package_list_path apps/flatpak)" 2>/dev/null \
            || grep -qxF "$1" "$(package_list_path apps/gaming-flatpak)" 2>/dev/null; then
            printf 'flatpak\n'
        else
            printf 'unsupported\n'
        fi
    elif pacman -Si "$1" >/dev/null 2>&1; then
        printf 'repo\n'
    else
        printf 'aur\n'
    fi
}
