#!/usr/bin/env bash

# list.sh
# Reads what each kind of hardware needs from drivers.txt.

# ------------------------------------------------------------
# Settings
# ------------------------------------------------------------

DRIVERS_FILE=""

driver_list_file() {
    ensure_package_backend
    if [ "$PKG_BACKEND" = "dnf" ]; then
        printf '%s\n' "$SCRIPT_DIR/packages/drivers/fedora.txt"
    else
        printf '%s\n' "$SCRIPT_DIR/packages/drivers/drivers.txt"
    fi
}

# ------------------------------------------------------------
# drivers.txt
# ------------------------------------------------------------

driver_pkgs_for() {
    local hardware="$1" v pkg rest
    local file
    file="$(driver_list_file)"
    [ -f "$file" ] || return 0
    while read -r v pkg rest; do
        case "$v" in ''|\#*) continue ;; esac
        if [ "$v" = "$hardware" ] && [ -n "$pkg" ]; then
            printf '%s\n' "$pkg"
        fi
    done <"$file"
}

driver_services_for() {
    local hardware="$1" v pkg svc rest
    local file
    file="$(driver_list_file)"
    [ -f "$file" ] || return 0
    while read -r v pkg svc rest; do
        case "$v" in ''|\#*) continue ;; esac
        if [ "$v" = "$hardware" ] && [ -n "$svc" ] && [ "$svc" != "-" ]; then
            printf '%s\n' "$svc"
        fi
    done <"$file"
}

driver_replaces_for() {
    local hardware="$1" wanted="$2" v pkg svc replaces rest
    local file
    file="$(driver_list_file)"
    [ -f "$file" ] || return 0
    while read -r v pkg svc replaces rest; do
        case "$v" in ''|\#*) continue ;; esac
        if [ "$v" = "$hardware" ] && [ "$pkg" = "$wanted" ] && [ -n "$replaces" ] && [ "$replaces" != "-" ]; then
            printf '%s\n' "$replaces"
            return 0
        fi
    done <"$file"
}

driver_flags_for() {
    local hardware="$1" wanted="$2" v pkg svc replaces flags
    local file
    file="$(driver_list_file)"
    [ -f "$file" ] || return 0
    while read -r v pkg svc replaces flags; do
        case "$v" in ''|\#*) continue ;; esac
        if [ "$v" = "$hardware" ] && [ "$pkg" = "$wanted" ] && [ -n "$flags" ]; then
            printf '%s\n' "$flags"
            return 0
        fi
    done <"$file"
}
