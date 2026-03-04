#!/usr/bin/env bash
#
# Zorin OS Core -> Pro conversion script.
# Intentionally does not use 'set -e': many failures are non-blocking (apt update,
# optional packages). We exit explicitly only where required.
#
set -o pipefail
set -u

# Base URL for raw repo files. When forking, change this or set ZORIN_PRO_REPO_RAW_BASE.
REPO_RAW_BASE="${ZORIN_PRO_REPO_RAW_BASE:-https://github.com/Vanilla-SilQ-HD/Zorin/raw/refs/heads/main}"

trap 'exit 1' HUP INT PIPE QUIT TERM
trap '
if [ -n "${TEMPD:-}" ]; then
  case "$TEMPD" in
    /tmp/*)
      if command rm -rf "$TEMPD"; then
        echo "Cleaned up temporary directory \"$TEMPD\" successfully!"
      else
        echo "Temp Directory \"$TEMPD\" was not deleted correctly; you need to manually remove it!"
      fi
      ;;
    *)
      echo "Warning: TEMPD=\"$TEMPD\" is outside /tmp/, refusing to delete for safety."
      ;;
  esac
fi
' EXIT

if ! grep -q "Zorin OS" /etc/os-release 2>/dev/null; then
  echo "Error: This script only supports Zorin OS."
  exit 1
fi

echo "███████╗ ██████╗ ██████╗ ██╗███╗   ██╗     ██████╗ ███████╗    ██████╗ ██████╗  ██████╗ "
echo "╚══███╔╝██╔═══██╗██╔══██╗██║████╗  ██║    ██╔═══██╗██╔════╝    ██╔══██╗██╔══██╗██╔═══██╗"
echo "  ███╔╝ ██║   ██║██████╔╝██║██╔██╗ ██║    ██║   ██║███████╗    ██████╔╝██████╔╝██║   ██║"
echo " ███╔╝  ██║   ██║██╔══██╗██║██║╚██╗██║    ██║   ██║╚════██║    ██╔═══╝ ██╔══██╗██║   ██║"
echo "███████╗╚██████╔╝██║  ██║██║██║ ╚████║    ╚██████╔╝███████║    ██║     ██║  ██║╚██████╔╝"
echo "╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝     ╚═════╝ ╚══════╝    ╚═╝     ╚═╝  ╚═╝ ╚═════╝ "
echo "|ZORIN-OS-PRO| |Script v10.0.1.1| |Overhauled & Maintained By NamashiTheNameless| |original idea by kauancvlcnt|"
echo ""
echo "(Please note this tool ONLY works on ZorinOS 18 Core, ZorinOS 17 Core, and ZorinOS 16 Core)"
echo ""
echo "To use this script on:"
echo "  ZorinOS 16 Core use the -6 flag"
echo "  ZorinOS 17 Core use the -7 flag"
echo "  ZorinOS 18 Core use the -8 flag"
echo ""
echo "If a version flag is not specified the script will try to guess."
echo "(add -X for a lot of extra content, recommended)"
echo "(add -U for unattended mode, not recommended)"
echo ""
echo "Original: https://github.com/NanashiTheNameless/Zorin-OS-Pro"
echo "If you got this code elsewhere, verify the source."
echo ""

sleep "${ZORIN_PRO_START_DELAY:-8}"

fail() {
  echo ""
  echo "Invalid usage. See: https://github.com/NanashiTheNameless/Zorin-OS-Pro/"
  echo "Usage: $0 [-6|-7|-8] [-X] [-U]"
  echo "  -6  Zorin OS 16 Core   -7  Zorin OS 17 Core   -8  Zorin OS 18 Core"
  echo "  -X  extra content (recommended)   -U  unattended (no prompts)"
  echo ""
  exit 1
}

no_confirm=""
extra="false"
auto_version="false"
version=""

while getopts "678XU" opt; do
  case "$opt" in
    6) version="16" ;;
    7) version="17" ;;
    8) version="18" ;;
    X) extra="true" ;;
    U) no_confirm="-y" ;;
    *) fail ;;
  esac
done
shift "$((OPTIND - 1))"
if [ $# -gt 0 ]; then
  echo "Warning: Ignoring extra arguments: $*"
fi

if [ -z "${version}" ]; then
  if ! grep -q "Zorin OS" /etc/os-release 2>/dev/null; then
    fail
  fi
  version_id=""
  if [ -r /etc/os-release ]; then
    version_id=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2 | cut -d '.' -f1 || true)
  fi
  case "${version_id}" in
    16) version="16" ;;
    17) version="17" ;;
    18) version="18" ;;
    *) fail ;;
  esac
  auto_version="true"
fi

if [ "${auto_version}" = "true" ]; then
  echo ""
  echo "ZorinOS $version automatically selected. If incorrect, stop with CTRL+C and re-run with -6, -7 or -8."
  echo ""
  sleep 5
fi

echo ""
echo "Preparing to install dependencies..."
echo ""

if ! sudo apt-get update; then
  echo "Non-Blocking Error: Failed to update apt repositories."
fi
if ! sudo apt-get install ${no_confirm} ca-certificates curl equivs; then
  echo "Non-Blocking Error: Failed to install dependencies."
fi

echo ""
echo "Done installing dependencies..."
echo ""
echo "Updating the default sources.list for Zorin's custom resources..."
echo ""

add_sources_for_version() {
  local codename="$1"
  sudo cp -f /etc/apt/sources.list.d/zorin.list /etc/apt/sources.list.d/zorin.list.bak 2>/dev/null || true
  sudo rm -f /etc/apt/sources.list.d/zorin.list
  sudo tee /etc/apt/sources.list.d/zorin.list > /dev/null << EOF
deb https://packages.zorinos.com/stable ${codename} main
deb-src https://packages.zorinos.com/stable ${codename} main

deb https://packages.zorinos.com/patches ${codename} main
deb-src https://packages.zorinos.com/patches ${codename} main

deb https://packages.zorinos.com/apps ${codename} main
deb-src https://packages.zorinos.com/apps ${codename} main

deb https://packages.zorinos.com/drivers ${codename} main restricted
deb-src https://packages.zorinos.com/drivers ${codename} main restricted

deb https://packages.zorinos.com/premium ${codename} main
deb-src https://packages.zorinos.com/premium ${codename} main
EOF
}

case "$version" in
  16) add_sources_for_version "focal" ;;
  17) add_sources_for_version "jammy" ;;
  18) add_sources_for_version "noble" ;;
  *) fail ;;
esac

echo ""
echo "Done updating the default sources.list for Zorin's custom resources..."
echo ""
sleep 2

TEMPD=$(mktemp -d)
if [ ! -e "$TEMPD" ]; then
  echo "Failed to create temp directory" >&2
  exit 1
fi
sudo chmod 755 "$TEMPD"

echo ""
echo "Adding Zorin's Package public GPG keys..."
echo ""

apt_update_with_retry() {
  local max_attempts=3 attempt=1 delay=5
  while [ "$attempt" -le "$max_attempts" ]; do
    echo "Attempting apt-get update (attempt $attempt/$max_attempts)..."
    if sudo apt-get update ${no_confirm}; then
      return 0
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "apt-get update failed, waiting ${delay}s before retry..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  echo "Warning: apt-get update failed after $max_attempts attempts. Continuing anyway..."
  return 1
}

if ! curl -L -H 'DNT: 1' -H 'Sec-GPC: 1' --output "$TEMPD/zorin-os.gpg" \
  "${REPO_RAW_BASE}/raw/zorin-os.gpg"; then
  echo "Error: Failed to download Zorin OS public GPG key."
  exit 1
fi
if [ ! -s "$TEMPD/zorin-os.gpg" ]; then
  echo "Error: Downloaded Zorin OS public GPG key file is empty or missing."
  exit 1
fi

if [ "$version" = "18" ]; then
  if ! curl -L -H 'DNT: 1' -H 'Sec-GPC: 1' --output "$TEMPD/zorin-os-premium-eighteen.gpg" \
    "${REPO_RAW_BASE}/raw/zorin-os-premium-eighteen.gpg"; then
    echo "Error: Failed to download premium public GPG key."
    exit 1
  fi
  if [ ! -s "$TEMPD/zorin-os-premium-eighteen.gpg" ]; then
    echo "Error: Downloaded premium public GPG key file is empty or missing."
    exit 1
  fi
else
  if ! curl -L -H 'DNT: 1' -H 'Sec-GPC: 1' --output "$TEMPD/zorin-os-premium.gpg" \
    "${REPO_RAW_BASE}/raw/zorin-os-premium.gpg"; then
    echo "Error: Failed to download premium public GPG key."
    exit 1
  fi
  if [ ! -s "$TEMPD/zorin-os-premium.gpg" ]; then
    echo "Error: Downloaded premium public GPG key file is empty or missing."
    exit 1
  fi
fi

sudo chmod 644 "$TEMPD/zorin-os.gpg"
if [ "$version" = "18" ]; then
  sudo chmod 644 "$TEMPD/zorin-os-premium-eighteen.gpg"
else
  sudo chmod 644 "$TEMPD/zorin-os-premium.gpg"
fi

sudo cp --no-clobber "$TEMPD/zorin-os.gpg" /etc/apt/trusted.gpg.d/zorin-os.gpg
if [ "$version" = "18" ]; then
  sudo cp --no-clobber "$TEMPD/zorin-os-premium-eighteen.gpg" /etc/apt/trusted.gpg.d/zorin-os-premium-eighteen.gpg
else
  sudo cp --no-clobber "$TEMPD/zorin-os-premium.gpg" /etc/apt/trusted.gpg.d/zorin-os-premium.gpg
fi

sudo chown root:root /etc/apt/trusted.gpg.d/zorin-os.gpg
if [ "$version" = "18" ]; then
  sudo chown root:root /etc/apt/trusted.gpg.d/zorin-os-premium-eighteen.gpg
else
  sudo chown root:root /etc/apt/trusted.gpg.d/zorin-os-premium.gpg
fi

echo ""
echo "Done adding ZorinOS public GPG keys..."
echo ""
echo "Adding premium flag..."
echo ""

sudo rm -f /etc/apt/apt.conf.d/99zorin-os-premium-user-agent
sudo tee /etc/apt/apt.conf.d/99zorin-os-premium-user-agent > /dev/null << 'EOF'
Acquire
{
  http::User-Agent "Zorin OS Premium";
};
EOF

echo ""
echo "Done adding premium flag..."
echo ""

if ! apt_update_with_retry; then
  echo "Error: Failed to update apt repositories after adding sources."
  echo "Waiting 10 seconds and trying once more..."
  sleep 10
  if ! apt_update_with_retry; then
    echo "Warning: apt-get update failed. Some packages may not be available."
  fi
fi

echo ""
echo "Refreshing apt cache with new GPG keys..."
echo ""
apt_update_with_retry || echo "Warning: Failed to refresh apt cache. Continuing anyway..."

echo ""
echo "Creating and installing dummy debs for keyring dependencies (if needed)..."
echo ""

# Prefer local make_dummy_deb.sh when script is run from repo (e.g. after fork/clone).
SCRIPT_DIR=""
if [[ "${BASH_SOURCE[0]:-}" == */* ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

run_make_dummy_deb() {
  local name="$1" ver="$2" out="$3"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/make_dummy_deb.sh" ]; then
    if ! bash "$SCRIPT_DIR/make_dummy_deb.sh" -w "$TEMPD/Dummy/" -n "$name" -v "$ver" -o "$out"; then
      echo "Warning: Failed to create dummy deb for $name. Continuing anyway..."
    fi
  else
    if ! bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL "${REPO_RAW_BASE}/make_dummy_deb.sh") \
      -w "$TEMPD/Dummy/" -n "$name" -v "$ver" -o "$out"; then
      echo "Warning: Failed to create dummy deb for $name. Continuing anyway..."
    fi
  fi
}

if ! dpkg -s "zorin-os-premium-keyring" >/dev/null 2>&1; then
  if [ "$version" = "18" ]; then
    run_make_dummy_deb "zorin-os-premium-keyring" "1.1" "$TEMPD/zorin-os-premium-keyring.deb"
  else
    run_make_dummy_deb "zorin-os-premium-keyring" "1.0" "$TEMPD/zorin-os-premium-keyring.deb"
  fi
else
  echo "zorin-os-premium-keyring is already installed, skipping."
fi

if ! dpkg -s "zorin-os-keyring" >/dev/null 2>&1; then
  run_make_dummy_deb "zorin-os-keyring" "1.1" "$TEMPD/zorin-os-keyring.deb"
else
  echo "zorin-os-keyring is already installed, skipping."
fi

for deb in "$TEMPD/zorin-os-premium-keyring.deb" "$TEMPD/zorin-os-keyring.deb"; do
  if [ -e "$deb" ]; then
    sudo chmod 644 "$deb"
  fi
done

for deb in "$TEMPD/zorin-os-premium-keyring.deb" "$TEMPD/zorin-os-keyring.deb"; do
  if [ -e "$deb" ]; then
    sudo dpkg -i "$deb" || echo "Warning: Failed to install $(basename "$deb")."
  fi
done

echo ""
echo "Done installing dummy debs if needed..."
echo ""
echo "Adding premium content from the official apt repo..."
echo ""

# Base APT packages (minimal Pro set) — same structure for all versions, suffix differs
base_apt=(
  zorin-appearance
  zorin-appearance-layouts-shell-core
  zorin-appearance-layouts-shell-premium
  zorin-appearance-layouts-support
  zorin-auto-theme
  zorin-icon-themes
  zorin-os-artwork
  zorin-os-keyring
  zorin-os-premium-keyring
  zorin-os-pro
  zorin-os-pro-wallpapers
  zorin-os-wallpapers
)

# Version-specific wallpaper packages
case "$version" in
  16)
    base_apt+=(zorin-os-pro-wallpapers-16 zorin-os-wallpapers-16)
    ;;
  17)
    base_apt+=(zorin-os-pro-wallpapers-17 zorin-os-wallpapers-17)
    ;;
  18)
    base_apt+=(zorin-os-wallpapers-18)
    ;;
esac

extra_apt=(
  zorin-additional-drivers-checker
  zorin-appearance
  zorin-appearance-layouts-shell-core
  zorin-appearance-layouts-shell-premium
  zorin-appearance-layouts-support
  zorin-auto-theme
  zorin-connect
  zorin-desktop-session
  zorin-desktop-themes
  zorin-exec-guard
  zorin-exec-guard-app-db
  zorin-gnome-tour-autostart
  zorin-icon-themes
  zorin-os-artwork
  zorin-os-default-settings
  zorin-os-docs
  zorin-os-file-templates
  zorin-os-keyring
  zorin-os-minimal
  zorin-os-overlay
  zorin-os-premium-keyring
  zorin-os-printer-test-page
  zorin-os-pro
  zorin-os-pro-creative-suite
  zorin-os-pro-productivity-apps
  zorin-os-pro-wallpapers
  zorin-os-restricted-addons
  zorin-os-standard
  zorin-os-tour-video
  zorin-os-upgrader
  zorin-os-wallpapers
  zorin-sound-theme
  zorin-windows-app-support-installation-shortcut
)

flatpak_extra=(
  org.nickvision.money
  com.usebottles.bottles
  io.github.seadve.Kooha
  com.rafaelmardojai.Blanket
  nl.hjdskes.gcolor3
  org.ardour.Ardour
  org.darktable.Darktable
  org.audacityteam.Audacity
  org.kde.krita
  org.gnome.BreakTimer
  org.gabmus.gfeeds
  fr.handbrake.ghb
  com.github.johnfactotum.Foliate
  org.inkscape.Inkscape
  com.obsproject.Studio
  org.mixxx.Mixxx
  io.github.OpenToonz
  org.videolan.VLC
  com.github.xournalpp.xournalpp
  net.scribus.Scribus
  org.blender.Blender
)

case "$version" in
  16)
    extra_apt+=(zorin-os-pro-wallpapers-16 zorin-os-wallpapers-12 zorin-os-wallpapers-15 zorin-os-wallpapers-16)
    flatpak_extra+=(org.pitivi.Pitivi)
    ;;
  17)
    extra_apt+=(zorin-os-pro-wallpapers-16 zorin-os-pro-wallpapers-17 zorin-os-wallpapers-12 zorin-os-wallpapers-15 zorin-os-wallpapers-16 zorin-os-wallpapers-17)
    flatpak_extra+=(org.kde.kdenlive)
    ;;
  18)
    extra_apt+=(zorin-os-pro-wallpapers-16 zorin-os-pro-wallpapers-17 zorin-os-wallpapers-12 zorin-os-wallpapers-15 zorin-os-wallpapers-16 zorin-os-wallpapers-17 zorin-os-wallpapers-18)
    flatpak_extra+=(org.kde.kdenlive)
    ;;
esac

install_pro_packages() {
  if [ "$extra" = "true" ]; then
    if ! sudo apt-get install ${no_confirm} "${extra_apt[@]}"; then
      echo "Error: Failed to install APT packages (version $version extra)."
      exit 1
    fi
    if command -v flatpak >/dev/null 2>&1; then
      for pkg in "${flatpak_extra[@]}"; do
        if ! flatpak install flathub ${no_confirm} "$pkg"; then
          echo "Warning: Failed to install Flatpak package $pkg. Continuing..."
        fi
      done
    else
      echo "Flatpak not found; skipping extra Flatpak packages."
    fi
  else
    if ! sudo apt-get --no-install-recommends install ${no_confirm} "${base_apt[@]}"; then
      echo "Error: Failed to install APT packages (version $version)."
      exit 1
    fi
  fi
}

install_pro_packages

echo ""
echo "Removing ZorinOS Census (if enrolled)..."
echo ""

if dpkg -s zorin-os-census >/dev/null 2>&1; then
  sudo apt purge -y zorin-os-census || echo "Non-Blocking Error: APT failed to uninstall zorin-os-census"
else
  echo "zorin-os-census is not installed; skipping removal."
fi

for cron_path in /etc/cron.daily/zorin-os-census /etc/cron.hourly/zorin-os-census; do
  if [ -e "$cron_path" ]; then
    sudo rm -f "$cron_path" || echo "Non-Blocking Error: Failed to delete $cron_path"
  else
    echo "Cron task $cron_path not found; skipping."
  fi
done

echo ""
echo "All done!"
echo "Questions: https://github.com/NanashiTheNameless/Zorin-OS-Pro/discussions/29"
echo "Bug reports: https://github.com/NanashiTheNameless/Zorin-OS-Pro/issues/new?template=bug_report.yml"
echo ""
echo 'Please reboot your Zorin instance: "sudo reboot" or use the Zorin menu.'
echo ""
