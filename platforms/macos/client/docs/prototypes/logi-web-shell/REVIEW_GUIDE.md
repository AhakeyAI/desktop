# AhaKey Logi Web Shell Review Guide

## Run

```bash
bun install
bun run build
bun run preview -- --host 127.0.0.1 --port 4173
```

Open `http://127.0.0.1:4173/`.

## Review Path

1. Home
   - default state is no-device
   - top-right actions stay light and icon-led
   - central object carries the page, not cards or borders
2. Add Device
   - click `添加设备`
   - click the Bluetooth row to start scanning
   - confirm a discovered device row appears
3. Studio
   - open the discovered device
   - click a hotspot to open the right-side inspector
   - confirm the left rail collapses to icons while the inspector is open
   - switch to `语音 / 后台服务 / 设备信息` and confirm the inspector hides
4. Settings
   - open `设置`
   - confirm General / Notifications / Feedback & Support / AhaKey 服务 / Privacy all switch cleanly
   - confirm the page relies on spacing and grouping, not nested cards

## Review Controls

- The bottom-right slider button opens the internal review panel.
- Use it to force device, control, sync, theme, and workspace states.
- The panel is a reviewer tool only and is intentionally visually subdued.

## Reference Screens

- `review-assets/home-light.png`
- `review-assets/studio-inspector-light.png`
- `review-assets/settings-light.png`
