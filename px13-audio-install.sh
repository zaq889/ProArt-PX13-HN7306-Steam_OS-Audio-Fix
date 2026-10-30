#!/usr/bin/env bash
# ASUS ProArt PX13 (HN7306) SteamOS audio fix - consolidated installer.
# Re-applies every local change after a SteamOS OS update wipes /usr.
# Idempotent; safe to run repeatedly. Run as root (or with sudo).
set -euo pipefail

LONG="ASUSTeKCOMPUTERINC.-ProArtPX13HN7306EA-1.0-HN7306EA"
CONFD="/usr/share/alsa/ucm2/conf.d/amd-soundwire"
UCMDIR="/usr/share/alsa/ucm2/sof-soundwire"
SBIN="/usr/local/sbin/px13-audio-fix.sh"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

# ---------- 1. UCM card-longname override ----------
mkdir -p "$CONFD"
if [ -f "$UCMDIR/sof-soundwire.conf" ]; then
  cp "$UCMDIR/sof-soundwire.conf" "$CONFD/$LONG.conf"
else
  echo "WARNING: $UCMDIR/sof-soundwire.conf missing, skipping override copy" >&2
fi
cat >> "$CONFD/$LONG.conf" <<'OVERRIDE'
# --- ASUS ProArt PX13 HN7306EA (SteamOS) local override ---
# CardComponents is empty on this machine, so DefineRegex derives nothing and
# HiFi.conf never loads any codec profile (PipeWire falls back to Dummy Output).
Define.SpeakerCodec1 "tas2783"
Define.HeadsetCodec1 "rt721"
Define.MicCodec1 "rt721"
Define.SpeakerCodecFile "tas2783"
Define.HeadsetCodecFile "rt721"
Define.MicCodecFile "rt721"
OVERRIDE

# ---------- 2. tas2783 Speaker profile ----------
cat > "$UCMDIR/tas2783.conf" <<'TAS'
# Use case Configuration for sof-soundwire card
# ASUS ProArt PX13 (HN7306EA) TAS2783 SoundWire smart-amp speaker profile.
SectionDevice."Speaker" {
        Comment "Speaker"

        EnableSequence [
                cset "name='Left Spk Switch' on"
                cset "name='Left Spk2 Switch' on"
                cset "name='Right Spk Switch' on"
                cset "name='Right Spk2 Switch' on"
                cset "name='tas2783-1 Speaker Volume' 200"
                cset "name='tas2783-2 Speaker Volume' 200"
        ]

        DisableSequence [
        ]

        Value {
                PlaybackPriority 100
                PlaybackPCM "hw:${CardId},2"
                PlaybackChannels 2
        }
}
TAS

# ---------- 3. ACP PCI rebind helper ----------
cat > "$SBIN" <<'FIX'
#!/usr/bin/env bash
set -uo pipefail
PCI_DEV="0000:c4:00.5"
PCI_DRV="/sys/bus/pci/drivers/snd_pci_ps"
CARD_MATCH="amd-soundwire"
log() { echo "px13-audio-fix: $*"; }
pci_write() { timeout 30 sh -c "echo '$1' > '$2'" 2>/dev/null; }

if [ ! -d "$PCI_DRV" ]; then
  log "snd_pci_ps driver not present - skipping"
elif [ ! -e "$PCI_DRV/$PCI_DEV" ]; then
  pci_write "$PCI_DEV" "$PCI_DRV/bind" || log "bind failed/timed out"
else
  log "unbinding PCI $PCI_DEV"
  pci_write "$PCI_DEV" "$PCI_DRV/unbind" || log "unbind failed/timed out"
  sleep 2
  log "binding PCI $PCI_DEV"
  pci_write "$PCI_DEV" "$PCI_DRV/bind" || log "bind failed/timed out"
fi

for _ in $(seq 1 40); do
  grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null && { log "amd-soundwire card present"; break; }
  sleep 0.25
done
grep -q "$CARD_MATCH" /proc/asound/cards 2>/dev/null || log "WARNING: amd-soundwire card did not reappear"
sleep 2

for uid in $(loginctl list-users --no-legend 2>/dev/null | awk '{print $1}'); do
  runtime_dir="/run/user/$uid"
  user_name="$(id -nu "$uid" 2>/dev/null)" || continue
  [ -d "$runtime_dir" ] || continue
  events="/sys/fs/cgroup/user.slice/user-${uid}.slice/cgroup.events"
  if [ -r "$events" ] && grep -q "^frozen 1$" "$events" 2>/dev/null; then
    log "uid $uid ($user_name) frozen - skip pipewire restart"
    continue
  fi
  log "restarting pipewire for uid $uid ($user_name)"
  sudo -u "$user_name" XDG_RUNTIME_DIR="$runtime_dir" \
    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null \
    || log "pipewire restart for uid $uid failed"
done
FIX
chmod 755 "$SBIN"

# ---------- 4. systemd units ----------
cat > /etc/systemd/system/px13-audio-rebind.service <<'UNIT1'
[Unit]
Description=PX13 TAS2783 SoundWire amp rebind + PipeWire refresh (boot)
After=sound.target
Wants=sound.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/px13-audio-fix.sh

[Install]
WantedBy=multi-user.target
UNIT1

cat > /etc/systemd/system/px13-audio-resume.service <<'UNIT2'
[Unit]
Description=PX13 audio fix after resume (reset AMD ACP/SoundWire, refresh PipeWire)
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/sbin/px13-audio-fix.sh

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
UNIT2

systemctl daemon-reload
systemctl enable px13-audio-rebind.service px13-audio-resume.service

# ---------- 5. iwd: stop idle Wi-Fi scan log spam ----------
cat > /etc/iwd/main.conf <<'IWD'
[Scan]
DisablePeriodicScan=true
IWD
systemctl restart iwd



# ---------- 6. Mono downmix for mirrored TAS2783 stereo pair ----------
# Kernel bug: both TAS2783 amps sit in SoundWire mirror mode (both render the
# same left slot), so right-channel audio is inaudible. Workaround: present a
# mono virtual sink; PipeWire downmixes stereo and the loopback duplicates the
# mono to both amps, so no content is lost.
PW_CONF_DIR="/home/deck/.config/pipewire/pipewire.conf.d"
mkdir -p "$PW_CONF_DIR"
cat > "$PW_CONF_DIR/50-px13-mono.conf" <<'PW'
## ProArt PX13 (HN7306): the two TAS2783 speaker amps are in SoundWire mirror
## mode (kernel bug), so both play the same (left) slot. Present a mono virtual
## sink: PipeWire downmixes stereo to mono, and the loopback forwards the mono
## to the 2ch ALSA speaker sink where it is duplicated to both amps.
context.modules = [
  { name = libpipewire-module-loopback
    args = {
      capture.props = {
        node.name = "px13_speaker_mono"
        node.description = "ProArt PX13 Speakers (mono)"
        media.class = "Audio/Sink"
        audio.position = "[ MONO ]"
        audio.channels = 1
      }
      playback.props = {
        node.name = "px13_speaker_mono_out"
        node.target = "alsa_output.pci-0000_c4_00.5-platform-amd_sdw.HiFi__Speaker__sink"
        audio.position = "[ FL FR ]"
      }
    }
  }
]
PW
chown -R deck:deck /home/deck/.config/pipewire

# Persist default-sink choice (WirePlumber state file survives reboot/resume)
STATE_DIR="/home/deck/.local/state/wireplumber"
mkdir -p "$STATE_DIR"
if ! grep -qs '^default.configured.audio.sink=px13_speaker_mono$' "$STATE_DIR/default-nodes"; then
  grep -qs '^\[default-nodes\]$' "$STATE_DIR/default-nodes" || echo '[default-nodes]' >> "$STATE_DIR/default-nodes"
  echo 'default.configured.audio.sink=px13_speaker_mono' >> "$STATE_DIR/default-nodes"
fi
chown -R deck:deck "$STATE_DIR"





# ---------- 7. Headphone jack auto-switch ----------
# Prefer the real stereo Headphones sink when its jack route is available,
# otherwise keep the mono speaker sink as default.
WP_SCRIPTS="/home/deck/.config/wireplumber/scripts"
WP_CONF_D="/home/deck/.config/wireplumber/wireplumber.conf.d"
mkdir -p "$WP_SCRIPTS" "$WP_CONF_D"
base64 -d > "$WP_SCRIPTS/px13-jack-switch.lua" <<'LUA_B64'
LS0gUHJvQXJ0IFBYMTMgKEhONzMwNikgaGVhZHBob25lIGphY2sgYXV0by1zd2l0Y2guCi0tIFRoZSBzcGVha2VyIHBhdGggaXMgYSBtb25vIHZpcnR1YWwgc2luayAoa2VybmVsIG1pcnJvci1tb2RlIHdvcmthcm91bmQpIGFuZCBpcwotLSB0aGUgZGVmYXVsdCB3aGVuIG5vdGhpbmcgaXMgcGx1Z2dlZCBpbi4gV2hlbiB0aGUgaGVhZHBob25lIGphY2sgcm91dGUgYmVjb21lcwotLSBhdmFpbGFibGUsIHByZWZlciB0aGUgcmVhbCBzdGVyZW8gaGVhZHBob25lIHNpbms7IGZhbGwgYmFjayB0byBtb25vIG90aGVyd2lzZS4KbG9nID0gTG9nLm9wZW5fdG9waWMgKCJzLXB4MTMtamFjayIpCgpsb2NhbCBIRUFEUEhPTkVfTk9ERSA9ICJhbHNhX291dHB1dC5wY2ktMDAwMF9jNF8wMC41LXBsYXRmb3JtLWFtZF9zZHcuSGlGaV9fSGVhZHBob25lc19fc2luayIKbG9jYWwgTU9OT19OT0RFID0gInB4MTNfc3BlYWtlcl9tb25vIgoKU2ltcGxlRXZlbnRIb29rIHsKICBuYW1lID0gInB4MTMtamFjay9kZWZhdWx0LW5vZGUiLAogIGFmdGVyID0geyAiZGVmYXVsdC1ub2Rlcy9maW5kLXNlbGVjdGVkLWRlZmF1bHQtbm9kZSIsCiAgICAgICAgICAgICJkZWZhdWx0LW5vZGVzL2ZpbmQtc3RvcmVkLWRlZmF1bHQtbm9kZSIgfSwKICBiZWZvcmUgPSB7ICJkZWZhdWx0LW5vZGVzL2ZpbmQtYmVzdC1kZWZhdWx0LW5vZGUiIH0sCiAgaW50ZXJlc3RzID0gewogICAgRXZlbnRJbnRlcmVzdCB7CiAgICAgIENvbnN0cmFpbnQgeyAiZXZlbnQudHlwZSIsICI9IiwgInNlbGVjdC1kZWZhdWx0LW5vZGUiIH0sCiAgICB9LAogIH0sCiAgZXhlY3V0ZSA9IGZ1bmN0aW9uIChldmVudCkKICAgIGxvY2FsIHByb3BzID0gZXZlbnQ6Z2V0X3Byb3BlcnRpZXMgKCkKICAgIGlmIHByb3BzWyJkZWZhdWx0LW5vZGUudHlwZSJdIH49ICJhdWRpby5zaW5rIiB0aGVuCiAgICAgIHJldHVybgogICAgZW5kCgogICAgbG9jYWwgYXZhaWxhYmxlX25vZGVzID0gZXZlbnQ6Z2V0X2RhdGEgKCJhdmFpbGFibGUtbm9kZXMiKQogICAgYXZhaWxhYmxlX25vZGVzID0gYXZhaWxhYmxlX25vZGVzIGFuZCBhdmFpbGFibGVfbm9kZXM6cGFyc2UgKCkKICAgIGlmIG5vdCBhdmFpbGFibGVfbm9kZXMgdGhlbgogICAgICByZXR1cm4KICAgIGVuZAoKICAgIGxvY2FsIGhhc19oZWFkcGhvbmUgPSBmYWxzZQogICAgbG9jYWwgaGFzX21vbm8gPSBmYWxzZQogICAgZm9yIF8sIG5vZGVfcHJvcHMgaW4gaXBhaXJzIChhdmFpbGFibGVfbm9kZXMpIGRvCiAgICAgIGxvY2FsIG5hbWUgPSBub2RlX3Byb3BzWyJub2RlLm5hbWUiXQogICAgICBpZiBuYW1lID09IEhFQURQSE9ORV9OT0RFIHRoZW4gaGFzX2hlYWRwaG9uZSA9IHRydWUgZW5kCiAgICAgIGlmIG5hbWUgPT0gTU9OT19OT0RFIHRoZW4gaGFzX21vbm8gPSB0cnVlIGVuZAogICAgZW5kCgogICAgaWYgaGFzX2hlYWRwaG9uZSB0aGVuCiAgICAgIGxvZzppbmZvICgiaGVhZHBob25lcyBhY3RpdmUgLSBzZWxlY3RpbmcgaGVhZHBob25lIHNpbmsiKQogICAgICBldmVudDpzZXRfZGF0YSAoInNlbGVjdGVkLW5vZGUiLCBIRUFEUEhPTkVfTk9ERSkKICAgICAgZXZlbnQ6c2V0X2RhdGEgKCJzZWxlY3RlZC1ub2RlLXByaW9yaXR5IiwgNDAwMDApCiAgICAgIGV2ZW50OnNldF9kYXRhICgic2VsZWN0ZWQtcm91dGUtcHJpb3JpdHkiLCAwKQogICAgZWxzZWlmIGhhc19tb25vIHRoZW4KICAgICAgbG9nOmluZm8gKCJubyBoZWFkcGhvbmVzIC0gc2VsZWN0aW5nIG1vbm8gc3BlYWtlciBzaW5rIikKICAgICAgZXZlbnQ6c2V0X2RhdGEgKCJzZWxlY3RlZC1ub2RlIiwgTU9OT19OT0RFKQogICAgICBldmVudDpzZXRfZGF0YSAoInNlbGVjdGVkLW5vZGUtcHJpb3JpdHkiLCAzNTAwMCkKICAgICAgZXZlbnQ6c2V0X2RhdGEgKCJzZWxlY3RlZC1yb3V0ZS1wcmlvcml0eSIsIDApCiAgICBlbmQKICBlbmQKfTpyZWdpc3RlciAoKQ==
LUA_B64
base64 -d > "$WP_CONF_D/60-px13-jack-switch.conf" <<'CONF_B64'
d2lyZXBsdW1iZXIuY29tcG9uZW50cyA9IFsKICB7IG5hbWUgPSAvaG9tZS9kZWNrLy5jb25maWcvd2lyZXBsdW1iZXIvc2NyaXB0cy9weDEzLWphY2stc3dpdGNoLmx1YSwgdHlwZSA9IHNjcmlwdC9sdWEgfQpd
CONF_B64
chown -R deck:deck /home/deck/.config/wireplumber

echo "PX13 audio fix re-applied successfully."