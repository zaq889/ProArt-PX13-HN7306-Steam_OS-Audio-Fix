#!/usr/bin/env bash
# PX13 (HN7306) audio fix: reset AMD ACP/SoundWire controller and refresh PipeWire.
# Runs at boot and after resume. See /etc/systemd/system/px13-audio-*.service.
set -uo pipefail

PCI_DEV="0000:c4:00.5"
PCI_DRV="/sys/bus/pci/drivers/snd_pci_ps"
CARD_MATCH="amd-soundwire"

log() { echo "px13-audio-fix: $*"; }

pci_write() { timeout 30 sh -c "echo '$1' > '$2'" 2>/dev/null; }

if [ ! -d "$PCI_DRV" ]; then
  log "snd_pci_ps driver not present, cannot reset - skipping"
elif [ ! -e "$PCI_DRV/$PCI_DEV" ]; then
  log "PCI $PCI_DEV not bound - attempting bind only"
  pci_write "$PCI_DEV" "$PCI_DRV/bind" || log "bind failed/timed out"
else
  log "unbinding PCI $PCI_DEV"
  pci_write "$PCI_DEV" "$PCI_DRV/unbind" || log "unbind failed/timed out"
  sleep 2
  log "binding PCI $PCI_DEV"
  pci_write "$PCI_DEV" "$PCI_DRV/bind" || log "bind failed/timed out"
fi

for _ in $(seq 1 40); do
  if grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null; then
    log "amd-soundwire card is present"
    break
  fi
  sleep 0.25
done
grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null \
  || log "WARNING: amd-soundwire card did not reappear"

sleep 2

for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
  runtime_dir="/run/user/$uid"
  user_name="$(id -nu "$uid" 2>/dev/null)" || continue
  [ -d "$runtime_dir" ] || continue

  events="/sys/fs/cgroup/user.slice/user-${uid}.slice/cgroup.events"
  if [ -r "$events" ] && grep -q "^frozen 1$" "$events" 2>/dev/null; then
    log "uid $uid ($user_name) session frozen - skipping pipewire restart"
    continue
  fi

  log "restarting pipewire for uid $uid ($user_name)"
  sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null \
    || log "pipewire restart for uid $uid failed"
done