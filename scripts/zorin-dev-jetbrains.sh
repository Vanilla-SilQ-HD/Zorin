#!/usr/bin/env bash
set -euo pipefail

# Download and extract the latest JetBrains Toolbox App (Linux) into ~/Downloads.
# Ничего не устанавливает в систему и не трогает /usr — только ваш $HOME.

LOG="${HOME}/zorin-dev-jetbrains.log"
exec > >(tee -a "${LOG}") 2>&1

echo "== Zorin dev: JetBrains Toolbox (download to ~/Downloads) =="

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found. Install: sudo apt-get install curl"
  exit 1
fi

downloads_dir="${HOME}/Downloads"
target_root="${downloads_dir}/jetbrains-toolbox"

mkdir -p "${downloads_dir}" "${target_root}"

echo "[1/3] Fetch latest JetBrains Toolbox download URL (Linux)…"

json_url="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
toolbox_url="$(
  curl -fsSL "${json_url}" \
    | grep -o 'https://download.jetbrains.com/toolbox/jetbrains-toolbox-[^"]*tar.gz' \
    | head -n1 || true
)"

if [ -z "${toolbox_url:-}" ]; then
  echo "ERROR: Could not detect JetBrains Toolbox download URL from ${json_url}"
  exit 1
fi

echo "Will download: ${toolbox_url}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}" >/dev/null 2>&1 || true' EXIT

echo "[2/3] Downloading archive…"
archive="${tmpdir}/toolbox.tar.gz"
curl -fsSL "${toolbox_url}" -o "${archive}"

echo "[3/3] Extracting into ${target_root}…"
tar -xzf "${archive}" -C "${target_root}"

extracted_dir="$(find "${target_root}" -maxdepth 1 -type d -name 'jetbrains-toolbox-*' | head -n1 || true)"

if [ -z "${extracted_dir:-}" ]; then
  echo "WARNING: Archive extracted, but Toolbox directory not found in ${target_root}."
  echo "Check contents of: ${target_root}"
else
  echo
  echo "JetBrains Toolbox extracted to:"
  echo "  ${extracted_dir}"
  echo
  echo "To run it:"
  echo "  cd \"${extracted_dir}\""
  echo "  ./jetbrains-toolbox &"
fi

echo
echo "DONE. Log: ${LOG}"

