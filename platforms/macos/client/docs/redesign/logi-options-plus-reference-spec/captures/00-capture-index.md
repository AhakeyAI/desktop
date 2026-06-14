# Capture Index

更新时间：2026-05-03
状态：capture 落库方案已建结构，待填充实际素材

---

## 1. 文档目的

本文档是 `captures/` 目录的工作索引，用于回答：

- capture 资产现在分为哪些页面
- 哪些组件已经进入跟踪区
- 哪些只是预留目录
- 首批试运行样本有哪些

---

## 2. 目录角色

### `tracked/`

进 git，保留：

- 精选默认态图
- 标注图
- 状态矩阵拼图
- 组件说明
- 页面 manifest

### `raw-local/`

不进 git，保留：

- 原始整页截图
- 临时裁片
- 重复版本
- 实验图

---

## 3. 页面分组

| 页面 | tracked | raw-local | 说明 |
|------|---------|-----------|------|
| `home` | 已建 | 已建 | 首页设备总览相关 capture |
| `device-studio` | 已建 | 已建 | 设备工作区相关 capture |
| `settings` | 已建 | 已建 | Settings 相关 capture |
| `agent` | 已建 | 已建 | 后台服务页相关 capture |
| `voice` | 已建 | 已建 | 语音页相关 capture |

---

## 4. 首批试运行组件

### home

- `hero`
- `topbar`
- `quick-actions`

### device-studio

- `platform-switcher`
- `sidebar`
- `canvas-hotspot`
- `inspector`
- `sync-banner`
- `status-pills`

### settings

- `nav`
- `form-group`

### agent

- `status-card`

### voice

- `permission-card`

---

## 5. 当前推荐工作顺序

1. `home/hero`
2. `device-studio/platform-switcher`
3. `device-studio/inspector`

完成这三项后，再决定是否扩展到其余组件。

---

## 6. 单组件最低交付物

一个组件进入 `tracked/` 的最低标准是：

1. `*-default.png`
2. `*-annotated.png`
3. `*-states-contact-sheet.png`
4. `*-notes.md`
5. 对应页面 `00-page-manifest.yaml` 已记录

若只存在原始图或临时裁片，则应停留在 `raw-local/`，不进入 git。
