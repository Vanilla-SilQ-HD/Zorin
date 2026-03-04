#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/zorin-systemdboot.log"
exec > >(tee -a "$LOG") 2>&1

need_root(){ [[ ${EUID:-0} -eq 0 ]] || { echo "Run: sudo bash $0"; exit 1; }; }
has(){ command -v "$1" >/dev/null 2>&1; }

export DEBIAN_FRONTEND=noninteractive

apt_safe() {
  apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$@"
}

need_root
echo "== systemd-boot + UKI (Windows default, firmware hidden) =="

echo "[1/11] Check UEFI mode"
[[ -d /sys/firmware/efi ]] || { echo "ERROR: Not booted in UEFI mode."; exit 1; }

echo "[2/11] Ensure ESP is mounted at /boot/efi"
mountpoint -q /boot/efi || { echo "ERROR: /boot/efi is not mounted."; exit 1; }

echo "[3/11] Basic sanity: ESP should be vfat"
ESP_FSTYPE="$(findmnt -no FSTYPE /boot/efi || true)"
if [[ "${ESP_FSTYPE:-}" != "vfat" ]]; then
  echo "WARNING: /boot/efi FSTYPE is '${ESP_FSTYPE:-unknown}', expected 'vfat'."
  echo "Continue, but make sure /boot/efi is your EFI System Partition."
fi

WIN_EFI="/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi"
if [[ ! -f "$WIN_EFI" ]]; then
  echo "WARNING: Windows EFI loader not found at: $WIN_EFI"
  echo "Windows entry may not boot if this path is different."
fi

echo "[4/11] Install dependencies"
apt-get update
apt_safe install efibootmgr || true
has bootctl || { echo "ERROR: bootctl not found."; exit 1; }

if ! has ukify; then
  apt_safe install systemd-ukify || true
fi
has ukify || { echo "ERROR: ukify not available. Can't build UKI."; exit 1; }

echo "[5/11] Detect root UUID"
ROOT_SRC="$(findmnt -no SOURCE /)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_SRC" || true)"
[[ -n "${ROOT_UUID:-}" ]] || { echo "ERROR: Could not detect root UUID."; exit 1; }
echo "Root: $ROOT_SRC (UUID=$ROOT_UUID)"

echo "[6/11] Backup ESP + boot entries"
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "/boot/efi/EFI/_backup_$TS"
cp -a /boot/efi/EFI/* "/boot/efi/EFI/_backup_$TS/" 2>/dev/null || true
efibootmgr -v > "/boot/efi/EFI/_backup_$TS/efibootmgr-$TS.txt" || true

echo "[7/11] Install systemd-boot"
bootctl --path=/boot/efi install

echo "[8/11] Create systemd-boot config (Windows default, firmware hidden)"
mkdir -p /boot/efi/loader/entries

cat > /boot/efi/loader/loader.conf <<'EOF'
default windows.conf
timeout 5
console-mode keep
editor no
auto-firmware no
EOF

chmod 0644 /boot/efi/loader/loader.conf

cat > /boot/efi/loader/entries/windows.conf <<'EOF'
title   Windows
efi     /EFI/Microsoft/Boot/bootmgfw.efi
EOF

chmod 0644 /boot/efi/loader/entries/windows.conf

cat > /boot/efi/loader/entries/zorin.conf <<'EOF'
title   Zorin
efi     /EFI/Linux/zorin.efi
EOF

chmod 0644 /boot/efi/loader/entries/zorin.conf

echo "[9/11] Build UKI for current kernel"
KVER="$(uname -r)"
VMLINUX="/boot/vmlinuz-$KVER"
INITRD="/boot/initrd.img-$KVER"
[[ -f "$VMLINUX" ]] || { echo "ERROR: $VMLINUX not found"; exit 1; }
[[ -f "$INITRD" ]] || { echo "ERROR: $INITRD not found"; exit 1; }

UKI_DIR="/boot/efi/EFI/Linux"
mkdir -p "$UKI_DIR"

CMDLINE="root=UUID=$ROOT_UUID ro quiet splash mem_sleep_default=deep"

ukify build \
  --linux "$VMLINUX" \
  --initrd "$INITRD" \
  --cmdline "$CMDLINE" \
  --output "$UKI_DIR/zorin.efi"

echo "[10/11] Install kernel hook: rebuild UKI on every kernel update (SAFE)"
HOOK="/etc/kernel/postinst.d/90-zorin-ukify"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# SAFE UKI rebuild hook: never fail kernel installation
set -u

KVER="${1:-}"
[[ -n "${KVER:-}" ]] || exit 0

command -v ukify >/dev/null 2>&1 || exit 0
mountpoint -q /boot/efi || exit 0

ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null || true)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_SRC" 2>/dev/null || true)"
[[ -n "${ROOT_UUID:-}" ]] || exit 0

VMLINUX="/boot/vmlinuz-${KVER}"
INITRD="/boot/initrd.img-${KVER}"
[[ -f "$VMLINUX" ]] || exit 0
[[ -f "$INITRD" ]] || exit 0

UKI_DIR="/boot/efi/EFI/Linux"
mkdir -p "$UKI_DIR" || exit 0

CMDLINE="root=UUID=${ROOT_UUID} ro quiet splash mem_sleep_default=deep"

TMP="${UKI_DIR}/zorin.efi.tmp"
if ukify build --linux "$VMLINUX" --initrd "$INITRD" --cmdline "$CMDLINE" --output "$TMP" >/dev/null 2>&1; then
  mv -f "$TMP" "${UKI_DIR}/zorin.efi" >/dev/null 2>&1 || true
else
  rm -f "$TMP" >/dev/null 2>&1 || true
fi

exit 0
EOF
chmod +x "$HOOK"

echo "[11/11] Put 'Linux Boot Manager' first in UEFI BootOrder (menu control)"
LBM="$(efibootmgr | awk -F'[* ]' '/Linux Boot Manager/ {print $1}' | sed 's/Boot//' | head -n1)"
if [[ -n "${LBM:-}" ]]; then
  CUR="$(efibootmgr | awk -F'Order: ' '/BootOrder/ {print $2}' | tr -d '[:space:]' || true)"
  if [[ -n "${CUR:-}" ]]; then
    NEW="$(echo "$CUR" | awk -v lbm="$LBM" -F',' '{
      out=lbm;
      for(i=1;i<=NF;i++) if($i!=lbm) out=out "," $i;
      print out
    }')"
    efibootmgr -o "$NEW" || true
  fi
else
  echo "NOTE: Linux Boot Manager entry not found. Select it once in BIOS, then rerun."
fi

echo
echo "DONE. Log: $LOG"
echo "systemd-boot menu should show ONLY:"
echo "  1) Windows (default)"
echo "  2) Zorin"
echo "Firmware entry: hidden (auto-firmware no)"
echo "Reboot: sudo reboot"