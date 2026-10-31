ProArt PX13 音频修复包 — 使用说明
ASUS ProArt PX13 Audio Fix Pack — Quick Guide
===============================================

【目标 / Purpose】
重装 SteamOS 后，一键恢复喇叭 / 无线日志修复（3.5mm 耳机口受当前内核 bug 限制）。
One-click restore of speaker / Wi-Fi log fixes after reinstalling SteamOS
(the 3.5mm headphone jack is blocked by a current-kernel bug).

【图形方式 / GUI method】
1. 把整个文件夹复制到 U 盘，再复制到 SteamOS 桌面。
   Copy the whole folder to a USB drive, then to the SteamOS desktop.
2. 右键 install-px13-fix.desktop → 选「允许启动」(Allow Launching)。
   Right-click install-px13-fix.desktop → choose "Allow Launching".
3. 双击它 → 输入 deck 密码 → 等待完成 → 重启。
   Double-click it → enter the deck password → wait → reboot.

【终端方式 / Terminal method (recommended)】
1. 打开 Konsole，进入本文件夹：
   Open Konsole and enter this folder:
   cd ~/Desktop/ProArt-PX13-Audio-Fix
2. 依次执行 / Run in order:
   sudo steamos-readonly disable
   sudo bash px13-audio-install.sh
3. 重启 / Reboot.

【注意事项 / Notes】
- 必须保留 firmware 文件夹（内含 4 个 TAS2783 校准固件）。安装脚本会把它们复制到
  /lib/firmware/；少了它们，声卡会只剩 off 配置，喇叭和耳机都会消失。
  Keep the firmware folder (4 TAS2783 calibration blobs). The installer copies them to
  /lib/firmware/. Without them the card drops to the "off" profile and both the speaker
  and headphone sinks disappear.
- 安装后建议执行 sudo systemctl restart px13-audio-rebind.service（或重启）让功放重新加载。
  After installing, run sudo systemctl restart px13-audio-rebind.service (or reboot) so
  the amps reload the firmware.
- 检查是否正常：pactl list cards 里声卡应显示 Active Profile: HiFi。
  Check: the card in `pactl list cards` should show "Active Profile: HiFi".
- 音量请只调「ProArt PX13 Speakers (mono)」，并把「Audio Coprocessor Speaker」保持在 100%；
  两个都调低会叠加衰减，听起来会像没声音。
  Adjust volume only on "ProArt PX13 Speakers (mono)" and keep "Audio Coprocessor Speaker"
  at 100%; lowering both applies the attenuation twice and can sound almost silent.
- 右声道只能 mono 下混（硬件/内核 bug），无法真正分左右。
  Right channel can only be mono-downmixed (hardware/kernel bug); true stereo split is impossible.
- 当前 SteamOS 内核 (7.2.7) 的 RT721 驱动无法检测 3.5mm 耳机，插入后不会切换也不会出声；
  这是内核 bug，脚本无法修复。请先用蓝牙或 USB-C 耳机，等 Valve 更新内核。
  耳机自动切换脚本已装好，内核修复后会自动生效。
  On the current SteamOS kernel (7.2.7) the RT721 driver does not detect the 3.5mm jack:
  plugging headphones neither switches nor plays. This is a kernel bug with no userspace
  fix; use Bluetooth/USB-C headphones until Valve ships a newer kernel. The auto-switch
  hook is already installed and will work automatically once the kernel detects the jack.
- 不要为了耳机口安装第三方内核或 DKMS 模块，可能破坏 SteamOS 的 A/B 更新。
  Do not install a third-party kernel or DKMS module just for the jack; it can break
  SteamOS A/B updates.
- 详细技术说明见 PX13.md。
  See PX13.md for technical details.
