#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=zorin-lib.sh
. "${SCRIPT_DIR}/zorin-lib.sh"

echo "== Zorin verify =="

# UEFI
[[ -d /sys/firmware/efi ]] && ok "UEFI mode: yes" || fail "UEFI mode: no"

# systemd-boot basics
if command -v bootctl >/dev/null 2>&1; then
  ok "bootctl present"
  bootctl status 2>/dev/null || warn "bootctl status: run with sudo for full details"
else
  warn "bootctl not found (ignore if using GRUB)"
fi

# loader.conf
LOADER="/boot/efi/loader/loader.conf"
if [[ -f "$LOADER" ]]; then
  ok "loader.conf exists"
  DEF="$(grep -E '^\s*default\s+' "$LOADER" | awk '{print $2}' | tail -n1 || true)"
  AFW="$(grep -E '^\s*auto-firmware\s+' "$LOADER" | awk '{print $2}' | tail -n1 || true)"
  [[ "${DEF:-}" == "windows.conf" ]] && ok "default = windows.conf" || warn "default = '${DEF:-<missing>}'"
  [[ -z "${AFW:-}" || "${AFW}" == "no" ]] && ok "firmware hidden" || warn "firmware visible (auto-firmware=${AFW})"
else
  warn "loader.conf not found (ESP not mounted?)"
fi

# entries + UKI
[[ -f /boot/efi/loader/entries/windows.conf ]] && ok "windows.conf exists" || warn "windows.conf missing"
[[ -f /boot/efi/loader/entries/zorin.conf ]] && ok "zorin.conf exists" || warn "zorin.conf missing"
[[ -f /boot/efi/EFI/Linux/zorin.efi ]] && ok "UKI exists" || warn "UKI missing"

# hook
[[ -x /etc/kernel/postinst.d/90-zorin-ukify ]] && ok "UKI hook installed" || warn "UKI hook missing"

svc "tlp.service" "TLP"
svc "zramswap.service" "ZRAM"
svc "fstrim.timer" "TRIM timer"
svc "irqbalance.service" "irqbalance"
svc "earlyoom.service" "earlyoom"

ok "Verify complete."