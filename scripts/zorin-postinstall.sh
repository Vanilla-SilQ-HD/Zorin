#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/zorin-postinstall.log"
exec > >(tee -a "$LOG") 2>&1

need_root(){ [[ ${EUID:-0} -eq 0 ]] || { echo "Run: sudo bash $0"; exit 1; }; }

export DEBIAN_FRONTEND=noninteractive

apt_safe() {
  apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "$@"
}

need_root
echo "== Zorin post-install: performance + power (safe) =="

echo "[1/9] Update system"
apt-get update
apt_safe full-upgrade

echo "[2/9] Install essential packages (safe, useful)"
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

echo "[3/9] Enable TRIM for SSD"
systemctl enable --now fstrim.timer

echo "[4/9] Enable irqbalance"
systemctl enable --now irqbalance || true

echo "[5/9] ZRAM config (responsiveness boost)"
if [[ -f /etc/default/zramswap && ! -f /etc/default/zramswap.bak ]]; then
  cp -a /etc/default/zramswap /etc/default/zramswap.bak
fi

cat > /etc/default/zramswap <<'EOF'
ENABLED=true
PERCENT=50
ALGO=zstd
EOF

chmod 0644 /etc/default/zramswap

systemctl enable --now zramswap.service || true

echo "[6/9] earlyoom (prevents hard UI freezes)"
systemctl enable --now earlyoom || true

echo "[7/9] TLP: snappy profile via drop-in"
systemctl enable --now tlp || true
mkdir -p /etc/tlp.d

cat > /etc/tlp.d/99-zorin-snappy.conf <<'EOF'
# Zorin "snappy" profile (safe)
# Goal: smoother UI; modest battery tradeoff

CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_performance

CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=1

PLATFORM_PROFILE_ON_AC=performance
PLATFORM_PROFILE_ON_BAT=balanced

RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto

WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on
EOF

chmod 0644 /etc/tlp.d/99-zorin-snappy.conf

systemctl restart tlp || true

echo "[8/9] Network latency tweaks (safe): fq + BBR"
cat > /etc/sysctl.d/99-zorin-net.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

chmod 0644 /etc/sysctl.d/99-zorin-net.conf

echo "[9/9] VM tweaks (safe): less swap thrash"
cat > /etc/sysctl.d/99-zorin-vm.conf <<'EOF'
vm.swappiness=15
vm.vfs_cache_pressure=100
EOF

chmod 0644 /etc/sysctl.d/99-zorin-vm.conf

sysctl --system >/dev/null || true

echo
echo "DONE. Log: $LOG"
echo "Reboot recommended: sudo reboot"