# Captures

本目录用于存放 Logi Options+ 的内部参考 capture 资料。

它不是正式产品资源目录，而是专题 spec 的配套分析资产目录。

---

## 1. 目录目标

本目录承载两类内容：

1. **可跟随源码保留的精选 capture**
2. **只保留在本地、不进入 git 的原始截图与临时素材**

本目录只服务于以下用途：

- 页面结构分析
- 原组件视觉拆解
- 状态矩阵对照
- AhaKey 映射讨论

不服务于：

- 正式产品资源打包
- 营销素材管理
- 运行时静态资源引用

---

## 2. 目录结构

```text
captures/
├── README.md
├── 00-capture-index.md
├── tracked/
│   ├── home/
│   ├── device-studio/
│   ├── settings/
│   ├── agent/
│   └── voice/
└── raw-local/
    ├── home/
    ├── device-studio/
    ├── settings/
    ├── agent/
    └── voice/
```

规则：

- `tracked/`：进 git，只放精选导出图、标注图、状态矩阵拼图、说明与 manifest
- `raw-local/`：不进 git，放原始整页截图、临时裁片、重复版本、实验图

---

## 3. 组织方式

一级目录按页面：

- `home`
- `device-studio`
- `settings`
- `agent`
- `voice`

二级目录按组件。

每个组件目录只跟踪以下 4 类主文件：

- `*-default.png`
- `*-annotated.png`
- `*-states-contact-sheet.png`
- `*-notes.md`

如果某个组件状态非常多，允许额外拆多个 contact sheet，但文件名前缀必须一致。

---

## 4. 命名规则

### 4.1 tracked 精选文件

- 全小写
- kebab-case
- 不带日期

示例：

- `hero-default.png`
- `hero-annotated.png`
- `hero-states-contact-sheet.png`
- `hero-notes.md`

### 4.2 raw-local 原始文件

- 文件名必须带日期
- 可以带状态、倍率、批次等局部说明

示例：

- `2026-05-03-home-hero-default@2x.png`
- `2026-05-03-platform-switcher-hover@2x.png`
- `2026-05-03-inspector-selected-pass-02.png`

---

## 5. 使用规则

1. 仅作为内部分析素材使用。
2. 不将 Logitech 原始品牌资源纳入正式产品资源链。
3. 原始大图默认先进入 `raw-local/`，筛选后再生成 `tracked/` 内容。
4. 每个页面必须有 `00-page-manifest.yaml` 记录覆盖情况。
5. 每个已跟踪组件必须有 `*-notes.md` 说明职责、状态、映射建议和 capture 缺口。

---

## 6. 首批试运行样本

当前首批建议优先落这 3 个组件：

- `home/hero`
- `device-studio/platform-switcher`
- `device-studio/inspector`

这 3 个样本足以验证：

- 页面 -> 组件 的组织方式
- 完整状态矩阵是否可操作
- manifest 是否足够表达覆盖率

具体索引见 [00-capture-index.md](./00-capture-index.md)。
