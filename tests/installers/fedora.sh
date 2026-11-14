#!/usr/bin/env bash

# fedora.sh
# Checks the Fedora DNF/RPM package backend without touching the host system.

source "$(dirname "$0")/../shared/helpers.sh"

copy_viresta
SCRIPT_DIR="$VIRESTA"
VIRESTA_STATE_DIR="$HOME/.local/state/viresta"
LOG_FILE="$TEST_DIR/install.log"
CALLS="$TEST_DIR/calls"
export FAKE_DB="$TEST_DIR/packages" FAKE_FLATPAK="$TEST_DIR/flatpaks"
: >"$FAKE_DB"
: >"$FAKE_FLATPAK"
: >"$CALLS"
printf 'ID=fedora\nVERSION_ID=42\n' >"$OS_RELEASE_FILE"

cat >"$BIN/dnf" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = repoquery ]; then
    package="${!#}"
    case "$package" in com.*|org.*) exit 1 ;; esac
    printf '%s\n' "$package"
fi
EOF
cp "$BIN/dnf" "$BIN/dnf5"
cat >"$BIN/rpm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -E) printf '42\n' ;;
    -q) grep -qxF "$2" "$FAKE_DB" ;;
    -qa) cat "$FAKE_DB" ;;
esac
EOF
cat >"$BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = list ]; then cat "$FAKE_FLATPAK"; fi
EOF
chmod +x "$BIN/dnf" "$BIN/dnf5" "$BIN/rpm" "$BIN/flatpak"

source "$VIRESTA/lib/system/checks.sh"
source "$VIRESTA/lib/installers/pacman.sh"
source "$VIRESTA/lib/drivers/hardware/list.sh"
info() { printf 'info: %s\n' "$1"; }
ok() { printf 'ok: %s\n' "$1"; }
failure() { printf 'FAILURE: %s\n' "$1"; }
sudo() { printf '%s %s\n' "$1" "${*:2}" >>"$CALLS"; }

detect_distribution
is "Fedora is detected" "$PKG_BACKEND" "dnf"
is "dnf5 is selected when present" "$DNF_COMMAND" "dnf5"
PKG_BACKEND=""
DNF_COMMAND=""
ensure_package_backend
is "package fallback also selects DNF5" "$PKG_BACKEND:$DNF_COMMAND" "dnf:dnf5"
is "Fedora RPM manifest is selected" "$(package_list_path apps/rpm)" "$VIRESTA/packages/fedora/apps/rpm.txt"
is "Fedora system manifest is selected" "$(package_list_path system/base)" "$VIRESTA/packages/fedora/system/base.txt"
is "Fedora KDE manifest is selected" "$(package_list_path system/kde)" "$VIRESTA/packages/fedora/system/kde.txt"
has "Fedora installs the Plasma Wayland session" "plasma-workspace-wayland" "$(cat "$VIRESTA/packages/fedora/system/kde.txt")"
is "RPM source is identified" "$(pkg_source kitty)" "repo"
is "Flathub source is identified" "$(pkg_source com.vscodium.codium)" "flatpak"

printf 'kitty\n' >"$FAKE_DB"
printf 'com.vscodium.codium\n' >"$FAKE_FLATPAK"
is "RPM installs are detected" "$(is_installed kitty && echo yes)" "yes"
is "Flatpak installs are detected" "$(is_installed com.vscodium.codium && echo yes)" "yes"

run_package_manager -S --needed --noconfirm kitty
is "package install maps to DNF" "$(cat "$CALLS")" "dnf5 install -y kitty"
is "i686 RPM sources are detected" "$(pkg_source mesa-vulkan-drivers.i686)" "repo"
 : >"$CALLS"
run_package_manager -Rs --noconfirm kitty
is "package removal maps to DNF" "$(cat "$CALLS")" "dnf5 remove -y kitty"
: >"$CALLS"
run_package_manager -Rs --noconfirm com.vscodium.codium
is "Flatpak removal maps to flatpak" "$(cat "$CALLS")" "flatpak uninstall -y com.vscodium.codium"
: >"$CALLS"

calls="$(update_system 2>&1)"
has "RPM Fusion repositories are enabled" "rpmfusion-free-release-42.noarch.rpm" "$(cat "$CALLS")"
has "system upgrade uses DNF" "dnf5 upgrade --refresh -y" "$(cat "$CALLS")"
hasnt "no Arch keyring operation" "archlinux-keyring" "$calls"

is "AMD uses Fedora's Vulkan package" "$(driver_pkgs_for amd | grep -c '^mesa-vulkan-drivers$')" "1"
is "32-bit drivers use i686 package names" "$(driver_pkgs_for amd | grep -c '\.i686$')" "2"
is "NVIDIA uses Fedora akmods" "$(driver_pkgs_for nvidia | grep -c '^akmod-nvidia$')" "1"

finish
