# 语音输入 Settings · 布局规范

更新时间：2026-07-11  
适用范围：Settings「语音输入」Tab（`VoiceInputWorkspacePane`）。

关联：

- [统一 UI 设计规范](./ahakey-ui-design-spec.md)
- 灵动岛三分段与折叠：`AhaKeyDynamicIslandSettingsPane` / `AhaKeySettingsDisclosureSection`

---

## 1. 信息架构

```text
语音输入
├ 历史记录（默认）  ← 全部本机转写列表（复制 / 删除 / 失败重试）
├ 词典              ← 词条增删改、启用开关
└ 通用设置          ← 试录、路由、历史保存时长；权限提示去偏好配置
```

系统权限与隐私说明在顶栏 **偏好配置 → 权限与隐私**。

顶部分段控件：`AhaKeyVoiceInputSectionPicker`（样式对齐灵动岛分段）。

---

## 2. 高频 / 低频

| 区域 | 常开 | 外置 |
|------|------|------|
| 历史 | 按日全部记录列表 | 保存时长 → 通用 |
| 词典 | 词条列表与编辑 | — |
| 通用 | 试录、语音路由、保存时长 | 系统权限 → 偏好配置 |
| 偏好配置 | — | 权限与隐私 |

原则：历史页只浏览记录；保存策略与权限放在设置侧。

---

## 3. 数据

- `VoiceInputStore`：Application Support `AhaKeyStudio/voice-input-store.json`
- 历史：转写 finalize 成功 / 失败 / 空结果写入；`retention` 裁剪
- 词典：finalize 前本地短语替换（长词优先）
- 「问任何问题」kind 预留，本版筛选多为空态

---

## 4. 实现入口

- `VoiceInputWorkspacePane`
- `AhaKeyVoiceHistoryPane` / `AhaKeyVoiceDictionaryPane` / `AhaKeyVoiceGeneralConfigPane`
- `VoiceInputStore` + `NativeSpeechTranscriptionService` finalize 挂钩
