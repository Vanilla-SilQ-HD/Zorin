#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=zorin-lib.sh
. "${SCRIPT_DIR}/zorin-lib.sh"

echo "== Zorin verify PLUS =="

if [[ ${EUID:-0} -ne 0 ]]; then
  warn "Run with sudo for full results: sudo bash $0"
fi

# UEFI
[[ -d /sys/firmware/efi ]] && ok "UEFI mode: yes" || fail "UEFI mode: no"

# systemd-boot
if command -v bootctl >/dev/null 2>&1; then
  ok "bootctl present"
  bootctl status 2>/dev/null || warn "bootctl status: needs sudo or not configured"
else
  warn "bootctl not found (ignore if using GRUB)"
fi

# loader.conf
LOADER="/boot/efi/loader/loader.conf"
if [[ -f "$LOADER" ]]; then
  ok "loader.conf exists"
  DEF="$(grep -E '^\s*default\s+' "$LOADER" | awk '{print $2}' | tail -n1 || true)"
  TMO="$(grep -E '^\s*timeout\s+' "$LOADER" | awk '{print $2}' | tail -n1 || true)"
  AFW="$(grep -E '^\s*auto-firmware\s+' "$LOADER" | awk '{print $2}' | tail -n1 || true)"
  [[ "${DEF:-}" == "windows.conf" ]] && ok "default = windows.conf" || warn "default = '${DEF:-<missing>}'"
  [[ -n "${TMO:-}" ]] && ok "timeout = ${TMO}" || warn "timeout missing"
  [[ -z "${AFW:-}" || "${AFW}" == "no" ]] && ok "firmware hidden" || warn "firmware visible (auto-firmware=${AFW})"
else
  warn "loader.conf not found (ESP not mounted?)"
fi

# entries + UKI + hook
[[ -f /boot/efi/loader/entries/windows.conf ]] && ok "windows.conf exists" || warn "windows.conf missing"
[[ -f /boot/efi/loader/entries/zorin.conf ]] && ok "zorin.conf exists" || warn "zorin.conf missing"
[[ -f /boot/efi/EFI/Linux/zorin.efi ]] && ok "UKI exists" || warn "UKI missing"
[[ -x /etc/kernel/postinst.d/90-zorin-ukify ]] && ok "UKI hook installed" || warn "UKI hook missing"

# BootOrder (needs sudo)
if command -v efibootmgr >/dev/null 2>&1; then
  if [[ ${EUID:-0} -eq 0 ]]; then
    BOOTORDER="$(efibootmgr | awk -F': ' '/BootOrder/ {print $2}' | tr -d '[:space:]' || true)"
    LBM="$(efibootmgr | awk -F'[* ]' '/Linux Boot Manager/ {print $1}' | sed 's/Boot//' | head -n1 || true)"
    if [[ -n "${BOOTORDER:-}" && -n "${LBM:-}" ]]; then
      [[ "${BOOTORDER%%,*}" == "$LBM" ]] && ok "BootOrder starts with Linux Boot Manager" || warn "Linux Boot Manager not first (BootOrder=$BOOTORDER)"
    else
      warn "Could not parse BootOrder/Linux Boot Manager"
    fi
  else
    warn "efibootmgr skipped (need sudo)"
  fi
fi

svc "tlp.service" "TLP"
svc "zramswap.service" "ZRAM"
svc "fstrim.timer" "TRIM timer"
svc "irqbalance.service" "irqbalance"
svc "earlyoom.service" "earlyoom"

# sleep mode
if [[ -f /sys/power/mem_sleep ]]; then
  ok "mem_sleep: $(cat /sys/power/mem_sleep)"
else
  warn "mem_sleep not found"
fi

# swap/zram actual
if command -v swapon >/dev/null 2>&1; then
  echo "--- swapon --show ---"
  swapon --show || true
  swapon --show | grep -qi zram && ok "zram swap detected" || warn "zram swap not detected"
fi

# sysctl network
QDISC="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
CC="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
[[ "${QDISC:-}" == "fq" ]] && ok "default_qdisc = fq" || warn "default_qdisc = '${QDISC:-<unknown>}'"
[[ "${CC:-}" == "bbr" ]] && ok "tcp_congestion_control = bbr" || warn "tcp_congestion_control = '${CC:-<unknown>}'"

# platform profile
if [[ -f /sys/firmware/acpi/platform_profile ]]; then
  ok "platform_profile: $(cat /sys/firmware/acpi/platform_profile)"
  ok "platform_profile choices: $(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || true)"
else
  warn "platform_profile not exposed"
fi

# NVIDIA
if command -v nvidia-smi >/dev/null 2>&1; then
  ok "nvidia-smi present"
  echo "--- nvidia-smi (summary) ---"
  nvidia-smi --query-gpu=name,driver_version,pstate,power.draw,power.limit,temperature.gpu,utilization.gpu,memory.used,memory.total \
    --format=csv,noheader,nounits 2>/dev/null | sed 's/^/GPU: /' || nvidia-smi || true
else
  warn "nvidia-smi not found"
fi

# battery via upower
if command -v upower >/dev/null 2>&1; then
  BAT="$(upower -e | grep -E 'battery|BAT' | head -n1 || true)"
  if [[ -n "${BAT:-}" ]]; then
    ok "Battery device: $BAT"
    upower -i "$BAT" | grep -E "state|time to empty|time to full|percentage|energy-rate" || true
  else
    warn "Battery not found via upower"
  fi
else
  warn "upower not installed"
fi

# NVMe SMART
if command -v nvme >/dev/null 2>&1; then
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

ok "Verify PLUS complete."