#!/usr/bin/env bash
# ProArt PX13 (HN7306) SteamOS fix - double-click entry point.
# Requires root. Via the .desktop launcher it runs under pkexec.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 运行： sudo bash \"$0\"" >&2
  echo "Please run as root:  sudo bash \"$0\"" >&2
  exit 1
fi

# SteamOS: make /usr writable so the installer can place UCM files.
if command -v steamos-readonly >/dev/null 2>&1; then
  if steamos-readonly status 2>/dev/null | grep -qi enabled; then
    echo "[px13] disabling steamos-readonly ..."
    steamos-readonly disable
  fi
else
  echo "[px13] warning: steamos-readonly not found (not SteamOS?)" >&2
fi

"$SELF_DIR/px13-audio-install.sh"
echo
echo "[px13] 完成。建议重启使声音服务完全生效。"
echo "[px13] Done. A reboot is recommended."