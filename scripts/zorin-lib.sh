#!/usr/bin/env bash

# Common helpers for Zorin scripts

ok()   { echo -e "✅ $*"; }
warn() { echo -e "⚠️  $*"; }
fail() { echo -e "❌ $*"; }

svc() {
  local unit="$1" pretty="$2"

  if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
    if systemctl is-enabled --quiet "$unit"; then
      ok "$pretty enabled"
    else
      warn "$pretty not enabled"
    fi

    if systemctl is-active --quiet "$unit"; then
      ok "$pretty active"
    else
      warn "$pretty not active"
    fi
  } else
    warn "$pretty not installed"
  fi
}

