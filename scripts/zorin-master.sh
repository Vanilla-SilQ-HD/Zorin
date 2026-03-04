#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Zorin Master Script
# =============================================================================
#
# Запуск: локально (./zorin-master.sh) или через curl (см. readme в репо).
#
# 0) Как поставить и запустить
#
#   Локально:
#     chmod +x zorin-master.sh
#     sudo ./zorin-master.sh --all   # или --postinstall, --systemdboot и т.д.
#
#   Через curl (без клонирования):
#     curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | sudo bash -s -- --all
#
# Режимы:
#   --postinstall   Пакеты, питание, ускорение (безопасно). Идемпотентный, с бэкапами.
#   --systemdboot   systemd-boot + UKI, Windows по умолчанию, Firmware скрыт.
#   --verify        Быстрая проверка (можно без sudo).
#   --verify-plus   Расширенная проверка (NVIDIA, батарея, NVMe, sleep).
#   --all           postinstall → systemdboot → verify.
#
# Важно:
#   --systemdboot меняет загрузчик. Безопасно при UEFI, но запускай, когда
#   Windows грузится нормально и ESP смонтирован. Firmware Settings не
#   переименовываем (это ломучая часть), а скрываем через auto-firmware no.
#
# =============================================================================

SCRIPT_NAME="zorin-master"
LOG_DIR="/var/log"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"

export DEBIAN_FRONTEND=noninteractive

apt_safe() {
  apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$@"
}

# -------- Output helpers
ts() { date +"%Y-%m-%d %H:%M:%S"; }
info() { echo -e "ℹ️  $*"; }
ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
fail() { echo -e "❌ $*"; }

svc() {
  local unit="$1" pretty="$2"
  if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
    systemctl is-enabled --quiet "$unit" && ok "$pretty enabled" || warn "$pretty not enabled"
    systemctl is-active --quiet "$unit" && ok "$pretty active" || warn "$pretty not active"
  else
    warn "$pretty not installed"
  fi
}

need_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    fail "Run as root: sudo $0 $*"
    exit 1
  fi
}

has() { command -v "$1" >/dev/null 2>&1; }

ensure_log() {
  if [[ ${EUID:-0} -eq 0 ]]; then
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE" || true
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Logging to: $LOG_FILE"
  else
    warn "Not root: logging to $LOG_FILE disabled"
  fi
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  [[ -f "${f}.bak" ]] && return 0
  cp -a "$f" "${f}.bak"
  ok "Backup created: ${f}.bak"
}

# -------- System sanity
require_uefi() {
  [[ -d /sys/firmware/efi ]] || { fail "Not booted in UEFI mode."; exit 1; }
  ok "UEFI mode: yes"
}

require_esp_mounted() {
  mountpoint -q /boot/efi || { fail "/boot/efi is not mounted (ESP)."; exit 1; }
  local fstype
  fstype="$(findmnt -no FSTYPE /boot/efi 2>/dev/null || true)"
  if [[ "${fstype:-}" != "vfat" ]]; then
    warn "/boot/efi FSTYPE is '${fstype:-unknown}', expected 'vfat'. Continue carefully."
  else
    ok "ESP mount OK: /boot/efi (vfat)"
  fi
}

# =========================
# CHECK (pre-flight for --systemdboot)
# =========================
do_check() {
  info "== CHECK: pre-flight for systemd-boot =="

  [[ -d /sys/firmware/efi ]] && ok "UEFI mode: yes" || { fail "UEFI mode: no"; exit 1; }

  if mountpoint -q /boot/efi 2>/dev/null; then
    ok "ESP mounted: /boot/efi"
    local fstype
    fstype="$(findmnt -no FSTYPE /boot/efi 2>/dev/null || true)"
    if [[ "${fstype:-}" == "vfat" ]]; then
      ok "ESP fstype: vfat"
    else
      warn "ESP fstype: ${fstype:-unknown} (expected vfat)"
    fi
    local free_mb
    free_mb="$(df -m /boot/efi 2>/dev/null | awk 'NR==2 {print $4}' || true)"
    if [[ -n "${free_mb:-}" ]]; then
      [[ "${free_mb:-0}" -ge 100 ]] && ok "ESP free space: ${free_mb} MB" || warn "ESP free space: ${free_mb} MB (recommend >= 100 MB)"
    fi
  else
    fail "/boot/efi is not mounted (ESP)"
    exit 1
  fi

  local win_efi="/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi"
  [[ -f "$win_efi" ]] && ok "Windows EFI: $win_efi" || warn "Windows EFI not found: $win_efi"

  has bootctl && ok "bootctl present" || warn "bootctl not found (install systemd)"
  has ukify && ok "ukify present" || warn "ukify not found (install systemd-ukify)"

  ok "CHECK done. Fix warnings before --systemdboot."
}

# =========================
# POSTINSTALL (safe)
# =========================
do_postinstall() {
  need_root
  info "== POSTINSTALL: safe performance + power =="

  info "[1/8] Update system"
  apt-get update
  apt_safe full-upgrade

  info "[2/8] Install essential packages"
  apt_safe install \
    curl wget ca-certificates gnupg \
    git openssh-client \
    build-essential pkg-config \
    htop nvme-cli lm-sensors \
    tlp tlp-rdw \
    powertop \
    zram-tools \
    irqbalance \
    earlyoom

  info "[3/8] Enable TRIM timer"
  systemctl enable --now fstrim.timer || true

  info "[4/8] Enable irqbalance"
  systemctl enable --now irqbalance.service || true

  info "[5/8] Configure ZRAM (50% RAM, zstd)"
  backup_file /etc/default/zramswap
  cat > /etc/default/zramswap <<'EOF'
ENABLED=true
PERCENT=50
ALGO=zstd
EOF
  chmod 0644 /etc/default/zramswap
  systemctl enable --now zramswap.service || true

  info "[6/8] Enable earlyoom (avoid UI freezes)"
  systemctl enable --now earlyoom.service || true

  info "[7/8] Configure TLP via drop-in (snappy, safe)"
  systemctl enable --now tlp.service || true
  mkdir -p /etc/tlp.d
  cat > /etc/tlp.d/99-zorin-snappy.conf <<'EOF'
# Zorin "snappy" profile (safe)
# Goal: smoother UI; modest battery tradeoff

CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_performance

CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=1

# ASUS platform profiles usually: quiet balanced performance
PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=balanced

RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
EOF
  chmod 0644 /etc/tlp.d/99-zorin-snappy.conf
  systemctl restart tlp.service || true

  info "[8/8] sysctl tweaks (safe): BBR + fq, lower swap thrash"
  cat > /etc/sysctl.d/99-zorin-net.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  chmod 0644 /etc/sysctl.d/99-zorin-net.conf
  cat > /etc/sysctl.d/99-zorin-vm.conf <<'EOF'
vm.swappiness=15
vm.vfs_cache_pressure=100
EOF
  chmod 0644 /etc/sysctl.d/99-zorin-vm.conf
  sysctl --system >/dev/null 2>&1 || true

  ok "POSTINSTALL done. Reboot recommended."
}

# =========================
# SYSTEMD-BOOT + UKI
# Windows default; Firmware скрыт через auto-firmware no (не переименовываем).
# Меняет загрузчик — запускай, когда Windows грузится и ESP на месте.
# =========================
do_systemdboot() {
  need_root
  info "== SYSTEMD-BOOT: Windows default + UKI + firmware hidden =="

  require_uefi
  require_esp_mounted

  info "[1/10] Install dependencies"
  apt-get update
  apt_safe install efibootmgr || true
  has bootctl || { fail "bootctl not found (systemd)."; exit 1; }

  if ! has ukify; then
    apt_safe install systemd-ukify || true
  fi
  has ukify || { fail "ukify not available. Can't build UKI."; exit 1; }

  info "[2/10] Detect root UUID"
  local root_src root_uuid
  root_src="$(findmnt -no SOURCE /)"
  root_uuid="$(blkid -s UUID -o value "$root_src" || true)"
  [[ -n "${root_uuid:-}" ]] || { fail "Could not detect root UUID."; exit 1; }
  ok "Root: $root_src (UUID=$root_uuid)"

  info "[3/10] Backup ESP and efibootmgr listing"
  local tsdir ts
  ts="$(date +%Y%m%d-%H%M%S)"
  tsdir="/boot/efi/EFI/_backup_${ts}"
  mkdir -p "$tsdir"
  cp -a /boot/efi/EFI/* "$tsdir/" 2>/dev/null || true
  efibootmgr -v > "$tsdir/efibootmgr-${ts}.txt" || true
  ok "ESP backup: $tsdir"

  info "[4/10] Install systemd-boot"
  bootctl --path=/boot/efi install

  info "[5/10] Write loader config (Windows default, Firmware hidden)"
  mkdir -p /boot/efi/loader/entries
  cat > /boot/efi/loader/loader.conf <<'EOF'
default windows.conf
timeout 5
console-mode keep
editor no
auto-firmware no
EOF
  chmod 0644 /boot/efi/loader/loader.conf

  info "[6/10] Write boot entries (Windows + Zorin)"
  local win_efi="/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi"
  if [[ ! -f "$win_efi" ]]; then
    warn "Windows EFI loader not found at $win_efi. Entry will still be created."
  fi

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

  info "[7/10] Build UKI for current kernel"
  local kver vmlinuz initrd uki_dir cmdline
  kver="$(uname -r)"
  vmlinuz="/boot/vmlinuz-${kver}"
  initrd="/boot/initrd.img-${kver}"
  [[ -f "$vmlinuz" ]] || { fail "Missing: $vmlinuz"; exit 1; }
  [[ -f "$initrd" ]] || { fail "Missing: $initrd"; exit 1; }

  uki_dir="/boot/efi/EFI/Linux"
  mkdir -p "$uki_dir"
  cmdline="root=UUID=${root_uuid} ro quiet splash mem_sleep_default=deep"

  ukify build \
    --linux "$vmlinuz" \
    --initrd "$initrd" \
    --cmdline "$cmdline" \
    --output "${uki_dir}/zorin.efi"

  ok "UKI built: ${uki_dir}/zorin.efi"

  info "[8/10] Install SAFE kernel hook: rebuild UKI on kernel updates"
  local hook="/etc/kernel/postinst.d/90-zorin-ukify"
  cat > "$hook" <<'EOF'
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
  chmod +x "$hook"
  ok "Hook installed: $hook"

  info "[9/10] Set UEFI BootOrder to put Linux Boot Manager first"
  if has efibootmgr; then
    local lbm cur new
    lbm="$(efibootmgr | awk -F'[* ]' '/Linux Boot Manager/ {print $1}' | sed 's/Boot//' | head -n1 || true)"
    cur="$(efibootmgr | awk -F'Order: ' '/BootOrder/ {print $2}' | tr -d '[:space:]' || true)"
    if [[ -n "${lbm:-}" && -n "${cur:-}" ]]; then
      new="$(echo "$cur" | awk -v lbm="$lbm" -F',' '{
        out=lbm;
        for(i=1;i<=NF;i++) if($i!=lbm) out=out "," $i;
        print out
      }')"
      efibootmgr -o "$new" || true
      ok "BootOrder updated (Linux Boot Manager first)"
    else
      warn "Could not parse Linux Boot Manager / BootOrder (may require BIOS selection once)"
    fi
  else
    warn "efibootmgr not installed"
  fi

  info "[10/10] Show bootctl summary"
  bootctl status 2>/dev/null || true

  ok "SYSTEMD-BOOT done. Reboot recommended."
}

# =========================
# VERIFY (quick)
# =========================
do_verify() {
  info "== VERIFY (quick) =="

  [[ -d /sys/firmware/efi ]] && ok "UEFI mode: yes" || fail "UEFI mode: no"

  if has bootctl; then
    ok "bootctl present"
    bootctl status 2>/dev/null || warn "bootctl status: run with sudo for full output"
  else
    warn "bootctl not found (ignore if using GRUB)"
  fi

  local loader="/boot/efi/loader/loader.conf"
  if [[ -f "$loader" ]]; then
    ok "loader.conf exists"
    local def afw
    def="$(grep -E '^\s*default\s+' "$loader" | awk '{print $2}' | tail -n1 || true)"
    afw="$(grep -E '^\s*auto-firmware\s+' "$loader" | awk '{print $2}' | tail -n1 || true)"
    [[ "${def:-}" == "windows.conf" ]] && ok "default = windows.conf" || warn "default = '${def:-<missing>}'"
    [[ -z "${afw:-}" || "${afw}" == "no" ]] && ok "firmware hidden" || warn "firmware visible (auto-firmware=${afw})"
  else
    warn "loader.conf not found (ESP not mounted?)"
  fi

  [[ -f /boot/efi/loader/entries/windows.conf ]] && ok "windows.conf exists" || warn "windows.conf missing"
  [[ -f /boot/efi/loader/entries/zorin.conf ]] && ok "zorin.conf exists" || warn "zorin.conf missing"
  [[ -f /boot/efi/EFI/Linux/zorin.efi ]] && ok "UKI exists" || warn "UKI missing"
  [[ -x /etc/kernel/postinst.d/90-zorin-ukify ]] && ok "UKI hook installed" || warn "UKI hook missing"

  ok "VERIFY complete."
}

# =========================
# VERIFY PLUS
# =========================
do_verify_plus() {
  info "== VERIFY PLUS =="

  do_verify

  # Services check (safe)
  svc "tlp.service" "TLP"
  svc "zramswap.service" "ZRAM"
  svc "fstrim.timer" "TRIM timer"
  svc "irqbalance.service" "irqbalance"
  svc "earlyoom.service" "earlyoom"

  # Sleep mode
  if [[ -f /sys/power/mem_sleep ]]; then
    ok "mem_sleep: $(cat /sys/power/mem_sleep)"
  else
    warn "mem_sleep not found"
  fi

  # Swap actual
  if has swapon; then
    echo "--- swapon --show ---"
    swapon --show || true
    swapon --show | grep -qi zram && ok "zram swap detected" || warn "zram swap not detected"
  fi

  # sysctl
  local qdisc cc
  qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  [[ "${qdisc:-}" == "fq" ]] && ok "default_qdisc = fq" || warn "default_qdisc = '${qdisc:-<unknown>}'"
  [[ "${cc:-}" == "bbr" ]] && ok "tcp_congestion_control = bbr" || warn "tcp_congestion_control = '${cc:-<unknown>}'"

  # Platform profile
  if [[ -f /sys/firmware/acpi/platform_profile ]]; then
    ok "platform_profile: $(cat /sys/firmware/acpi/platform_profile)"
    ok "choices: $(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || true)"
  else
    warn "platform_profile not exposed"
  fi

  # NVIDIA
  if has nvidia-smi; then
    ok "nvidia-smi present"
    echo "--- nvidia-smi (summary) ---"
    nvidia-smi --query-gpu=name,driver_version,pstate,power.draw,power.limit,temperature.gpu,utilization.gpu,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | sed 's/^/GPU: /' || nvidia-smi || true
  else
    warn "nvidia-smi not found"
  fi

  # Battery (upower)
  if has upower; then
    local bat
    bat="$(upower -e | grep -E 'battery|BAT' | head -n1 || true)"
    if [[ -n "${bat:-}" ]]; then
      ok "Battery device: $bat"
      upower -i "$bat" | grep -E "state|time to empty|time to full|percentage|energy-rate" || true
    else
      warn "Battery not found via upower"
    fi
  else
    warn "upower not installed"
  fi

  # NVMe SMART (root needed)
  if has nvme; then
    if [[ ${EUID:-0} -eq 0 ]]; then
      echo "--- NVMe SMART (best-effort) ---"
      for dev in /dev/nvme*n1; do
        [[ -b "$dev" ]] || continue
        echo "Device: $dev"
        nvme id-ctrl "$dev" 2>/dev/null | grep -E "mn|fr" || true
        nvme smart-log "$dev" 2>/dev/null | grep -E "temperature|available_spare|percentage_used|power_cycles|power_on_hours|media_errors|num_err_log_entries" || true
        echo
      done
    else
      warn "NVMe SMART skipped (need sudo)"
    fi
  else
    warn "nvme-cli not installed"
  fi

  ok "VERIFY PLUS complete."
}

# =========================
# Usage
# =========================
usage() {
  cat <<EOF
Usage:
  sudo ./${SCRIPT_NAME}.sh --postinstall   # пакеты, питание, ускорение (безопасно)
  sudo ./${SCRIPT_NAME}.sh --systemdboot   # systemd-boot + UKI, Windows default, Firmware скрыт
       ./${SCRIPT_NAME}.sh --verify        # быстрая проверка
  sudo ./${SCRIPT_NAME}.sh --verify-plus   # расширенная проверка (NVIDIA, батарея, NVMe, sleep)
  sudo ./${SCRIPT_NAME}.sh --all          # postinstall → systemdboot → verify
       ./${SCRIPT_NAME}.sh --check        # предполётная проверка перед --systemdboot

Важно: --systemdboot меняет загрузчик. Запускай, когда Windows грузится и ESP на месте.
        Firmware скрыт через auto-firmware no (не переименовываем).
Логи (при запуске с sudo): $LOG_FILE
EOF
}

# =========================
# Main
# =========================
main() {
  if [[ $# -lt 1 ]]; then usage; exit 1; fi

  # Enable logging if root
  ensure_log

  case "$1" in
    --check)
      do_check
      ;;
    --postinstall)
      do_postinstall
      ;;
    --systemdboot)
      do_systemdboot
      ;;
    --verify)
      do_verify
      ;;
    --verify-plus)
      do_verify_plus
      ;;
    --all)
      do_postinstall
      do_systemdboot
      do_verify
      ok "ALL done. Reboot recommended."
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"