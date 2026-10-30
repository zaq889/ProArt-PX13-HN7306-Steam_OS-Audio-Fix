ProArt PX13 音频修复包 — 使用说明
ASUS ProArt PX13 Audio Fix Pack — Quick Guide
===============================================

【目标 / Purpose】
重装 SteamOS 后，一键恢复喇叭 / 耳机 / 无线日志修复。
One-click restore of speaker / headphone / Wi-Fi log fixes after reinstalling SteamOS.

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
- 右声道只能 mono 下混（硬件/内核 bug），无法真正分左右。
  Right channel can only be mono-downmixed (hardware/kernel bug); true stereo split is impossible.
- 插入耳机会自动切到耳机立体声，拔出后回到喇叭。
  Plugging in headphones auto-switches to headphone stereo; unplugging returns to speakers.
- 详细技术说明见 PX13修复说明.md。
  See PX13修复说明.md for technical details.