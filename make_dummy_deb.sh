#!/usr/bin/env bash
#
# Build a dummy .deb that satisfies a dependency without installing files.
# Requires: equivs (equivs-build).
# Only use -n and -v with trusted values; when called from zorin.sh they are fixed.
#
set -euo pipefail

usage() {
  echo "Usage: $0 -n package_name -v version -o output_path [-w work_dir]" >&2
  echo "  -n  Package name (required; only [a-z0-9.+-] allowed)" >&2
  echo "  -v  Version (required; only [0-9.] allowed)" >&2
  echo "  -o  Output path for .deb — directory or full .deb path (required)" >&2
  echo "  -w  Working directory for build (optional, defaults to mktemp)" >&2
}

# Debian package name: lowercase letters, digits, plus, minus, period.
PKG_NAME_RE='^[a-z0-9][a-z0-9.+-]*$'
# Version: digits and periods.
PKG_VERSION_RE='^[0-9][0-9.]*$'

PKG_NAME=""
PKG_VERSION=""
OUT_PATH=""
WORK_DIR=""

while getopts ":n:v:o:w:h" opt; do
  case "$opt" in
    n) PKG_NAME="$OPTARG" ;;
    v) PKG_VERSION="$OPTARG" ;;
    o) OUT_PATH="$OPTARG" ;;
    w) WORK_DIR="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      usage
      exit 2
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$PKG_NAME" || -z "$PKG_VERSION" || -z "$OUT_PATH" ]]; then
  echo "Error: options -n, -v, and -o are required." >&2
  usage
  exit 2
fi

if [[ ! "$PKG_NAME" =~ $PKG_NAME_RE ]]; then
  echo "Error: package name must match [a-z0-9][a-z0-9.+-]*" >&2
  exit 2
fi
if [[ ! "$PKG_VERSION" =~ $PKG_VERSION_RE ]]; then
  echo "Error: version must match [0-9][0-9.]*" >&2
  exit 2
fi

if ! command -v equivs-build >/dev/null 2>&1; then
  echo "Installing 'equivs' (requires sudo)..."
  sudo apt-get update -y
  sudo apt-get install -y equivs
fi

if [[ "$OUT_PATH" == */ ]]; then
  OUT_DIR="$OUT_PATH"
  OUT_FILE="${PKG_NAME}_${PKG_VERSION}_all.deb"
elif [[ "$OUT_PATH" == *.deb ]]; then
  OUT_DIR="$(dirname "$OUT_PATH")"
  OUT_FILE="$(basename "$OUT_PATH")"
else
  OUT_DIR="$OUT_PATH"
  OUT_FILE="${PKG_NAME}_${PKG_VERSION}_all.deb"
fi

mkdir -p "$OUT_DIR"

if [[ -z "$WORK_DIR" ]]; then
  BUILD_DIR="$(mktemp -d)"
  CLEANUP_BUILD_DIR=true
else
  BUILD_DIR="$WORK_DIR"
  CLEANUP_BUILD_DIR=false
  mkdir -p "$BUILD_DIR"
fi

CONTROL="$BUILD_DIR/control"
ARCH="all"
MAINTAINER="Dummy <dummy@dummy.invalid>"
DESCRIPTION="Dummy package to satisfy dependency for $PKG_NAME."

cat >"$CONTROL" << EOF
Section: misc
Priority: optional
Standards-Version: 3.9.2

Package: $PKG_NAME
Version: $PKG_VERSION
Maintainer: $MAINTAINER
Architecture: $ARCH
Provides: $PKG_NAME
Description: $DESCRIPTION
 This package intentionally contains no files. It only exists
 to satisfy dependencies on $PKG_NAME.
EOF

if ! (cd "$BUILD_DIR" && equivs-build control); then
  [[ "$CLEANUP_BUILD_DIR" == true ]] && rm -rf "$BUILD_DIR"
  echo "Error: equivs-build failed, no package created." >&2
  exit 1
fi

mapfile -t DEB_FILES < <(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.deb" | sort)
if [[ ${#DEB_FILES[@]} -eq 0 ]]; then
  [[ "$CLEANUP_BUILD_DIR" == true ]] && rm -rf "$BUILD_DIR"
  echo "Error: No .deb file produced in $BUILD_DIR." >&2
  exit 1
fi
if [[ ${#DEB_FILES[@]} -gt 1 ]]; then
  echo "Warning: Multiple .deb files found; using ${DEB_FILES[0]}." >&2
fi
mv "${DEB_FILES[0]}" "$OUT_DIR/$OUT_FILE"

if [[ "$CLEANUP_BUILD_DIR" == true ]]; then
  rm -rf "$BUILD_DIR"
fi

echo "Built dummy package: $OUT_DIR/$OUT_FILE"
echo "Install with: sudo apt install $OUT_DIR/$OUT_FILE"
