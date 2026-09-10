# `@ahakey/plugin-sdk`

[English](../../sdks/typescript/README.md) · [简体中文](typescript-sdk.md) · [SDK 总览](sdk.md)

使用 TypeScript 编写 AhaKey 插件。宿主将插件作为子进程启动；SDK 负责通过 stdin/stdout 传输逐行 JSON-RPC 2.0 消息，并处理生命周期回调、宿主调用和插件自定义方法。

## 目录

- [快速开始](#快速开始)
- [创建自己的插件](#创建自己的插件)
- [清单与插件发现](#清单与插件发现)
- [生命周期](#生命周期)
- [宿主 API](#宿主-api)
- [插件方法与通知](#插件方法与通知)
- [服务选项与错误处理](#服务选项与错误处理)
- [内置示例](#内置示例)
- [常见问题](#常见问题)

## 快速开始

需要 Node.js 18+ 和 npm。SDK 使用 ES module 格式。CI 使用 Node.js 20；随仓库提供的 Swift 演示程序需要 macOS 13+、Swift 5.9+ 及兼容的 Xcode 工具链。只有真实拨杆读数需要连接键盘。

从仓库根目录运行：

```bash
cd sdks/typescript
npm ci
npm run typecheck
npm test
npm run demo
```

`npm test` 会编译 SDK 和两个示例，然后运行 Node.js 测试。`npm run demo` 再次构建后打开 macOS 展示窗口，显示插件元信息、宿主信息、拨杆状态和问候操作。两个示例都会被发现和加载。拨杆计数器可能写入 `~/.ahakey-flow-stats.json`，详见[内置示例](#内置示例)。

示例从本地 package 解析 `@ahakey/plugin-sdk`。如果要在独立项目中使用 SDK，请按照下面的本地安装包流程操作。

## 创建自己的插件

### 1. 构建并打包 SDK

在 `sdks/typescript/` 执行 `npm ci` 后运行：

```bash
npm run build:sdk
npm pack
```

当前版本会生成 `ahakey-plugin-sdk-0.1.0.tgz`。版本变化时，以 `npm pack` 输出的文件名为准。本教程直接安装本地压缩包，无需依赖已发布到 npm 的包。

### 2. 创建独立插件项目

在一个名为 `plugins/` 的父目录中创建 `greeter/`，然后进入 `greeter/`。添加 `package.json`：

```json
{
  "name": "ahakey-greeter",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json"
  }
}
```

将下面的压缩包路径替换为实际绝对路径，安装 SDK 和构建工具：

```bash
npm install /absolute/path/to/desktop/sdks/typescript/ahakey-plugin-sdk-0.1.0.tgz
npm install --save-dev typescript @types/node
```

添加 `tsconfig.json`：

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "rootDir": "src",
    "outDir": "dist",
    "strict": true,
    "types": ["node"]
  },
  "include": ["src/**/*.ts"]
}
```

创建 `src/main.ts`：

```ts
import {
  definePlugin,
  servePlugin,
  JsonRpcError,
  JSON_RPC_ERROR,
} from "@ahakey/plugin-sdk";

servePlugin(definePlugin({
  name: "AhaKey Greeter",
  version: "0.1.0",
  methods: {
    "greeter/greet": (params) => {
      if (typeof params !== "object"
        || params === null
        || !("name" in params)
        || typeof params.name !== "string") {
        throw new JsonRpcError(
          JSON_RPC_ERROR.invalidParams,
          "Expected { name: string }",
        );
      }
      return { message: `Hello, ${params.name}!` };
    },
  },
  async onInitialized({ host }) {
    const info = await host.getInfo();
    await host.log(`Greeter connected to ${info.bundleID}`);
  },
}));
```

### 3. 添加清单并构建

在 `package.json` 同级目录创建 `plugin.json`：

```json
{
  "id": "com.example.greeter",
  "name": "AhaKey Greeter",
  "version": "0.1.0",
  "entrypoint": {
    "command": "node",
    "args": ["${pluginDir}/dist/main.js"]
  },
  "permissions": ["host/getInfo", "host/log"]
}
```

在 `greeter/` 运行 `npm run build`。构建后的目录如下：

```text
plugins/
└── greeter/
    ├── plugin.json
    ├── package.json
    ├── package-lock.json
    ├── tsconfig.json
    ├── src/main.ts
    ├── dist/main.js
    └── node_modules/
```

### 4. 使用开发宿主加载

回到 AhaKey 仓库根目录，将下面的路径替换为父目录 `plugins/` 的绝对路径：

```bash
AHAKEY_PLUGINS_DIR="/absolute/path/to/plugins" swift run --package-path ahakeyconfig-mac Plugin
```

命令行宿主发现并初始化插件，等待约一秒后将其关闭。它不会调用 `greeter/greet`；可使用 [Swift 宿主示例](sdk.md#swift-宿主集成)发送该请求。单独执行 `node dist/main.js` 只会等待 JSON-RPC 输入，不会模拟宿主。

加载自定义目录时，请使用上面的直接 Swift 命令。`npm run demo` 和 `npm run demo:cli` 会显式将 `AHAKEY_PLUGINS_DIR` 设置为 SDK 的内置示例目录。展示窗口的操作针对 `demo/getStatus` 和 `demo/greet`，不会自动为任意自定义方法生成按钮。

## 清单与插件发现

| 字段 | 必填 | 含义 |
|---|---|---|
| `id` | 是 | 稳定的插件标识，请使用唯一值，如 `com.example.greeter` |
| `name`、`version` | 是 | 展示用的元信息字符串，请与 `definePlugin` 保持一致 |
| `entrypoint.command` | 是 | 通过 `/usr/bin/env` 查找的可执行文件名，或可执行文件的绝对路径 |
| `entrypoint.args` | 是 | 参数数组，没有参数时使用 `[]` |
| `entrypoint.env` | 否 | 子进程环境变量，键和值均为字符串 |
| `permissions` | 否 | 允许调用的宿主方法名，默认为 `[]` |

宿主将参数字符串和环境变量**值**中的 `${pluginDir}` 替换为清单所在目录的绝对路径，不会替换 `entrypoint.command` 中的占位符。子进程工作目录为插件目录。命令直接执行，不经过 shell 展开，也不支持 shell 操作符。

省略 `entrypoint.env` 时，进程继承宿主环境。提供该字段时，当前 Swift 实现会将它作为整个进程环境，不会与宿主环境合并。请提供命令所需的 `PATH` 等变量，或使用可执行文件绝对路径。

`PluginManager` 扫描以下目录下非隐藏的直接子目录：

```text
~/Library/Application Support/AhaKeyConfig/plugins/
```

`AHAKEY_PLUGINS_DIR` 可替换该根目录。每个子目录都需要清单；直接放在扫描根目录中的 `plugin.json` 不会被发现。当前可运行宿主是 `Plugin` 和 `PluginShowcase`，将插件复制到此目录暂时不会使其在主桌面应用中启用。

交付插件时，需要将编译后的 JavaScript 和运行时依赖与清单一起提供，也可自行打包运行时导入。宿主负责启动入口，不会编译 TypeScript 或安装 npm 依赖。

## 生命周期

`definePlugin(definition)` 提供 TypeScript 类型约束，并返回原定义；`servePlugin(definition, options?)` 创建并启动 `AhaKeyPluginServer`。

| 宿主消息 | SDK 行为 | 插件回调 |
|---|---|---|
| 请求 `plugin/initialize` | 保存 `{ host, hostMethods }`，返回插件名称、版本和方法列表 | `onInitialize(params, host)` |
| 通知 `plugin/initialized` | 表示初始化已完成 | `onInitialized({ host, initializeParams })` |
| 请求 `plugin/shutdown` | 等待清理完成，然后返回 `null` | `onShutdown(context)` |
| 通知 `plugin/exit` | 执行回调并关闭 RPC 通信 | `onExit(context)` |

所有回调都支持同步或异步实现。`onInitialize` 可返回部分 `{ name, version, methods }` 字段以覆盖声明值；修改声明的方法列表不会注册新的处理器。如果自定义方法需要宿主引用，可在 `onInitialize` 中保存。后台任务在 `onInitialized` 中启动，定时器、文件监听及其他资源在 `onShutdown` / `onExit` 中清理。

退出相关回调接收 `PluginContext | undefined`，需要处理尚未初始化就收到调用的情况。`server.close()` 关闭通信并拒绝待完成的宿主请求，不会执行清理回调或强制退出 Node.js 进程。清理操作应及时完成：Swift 生命周期辅助方法的初始化默认超时为五秒，关闭默认超时为三秒。

## 宿主 API

`host` 是生命周期回调中提供的 `AhaKeyHost`，也可以通过 `server.host` 访问。

| SDK 方法 | 宿主权限 | 返回结果 |
|---|---|---|
| `getInfo()` | `host/getInfo` | `Promise<HostAppInfo>`，包含字符串字段 `bundleID`、`version`、`build`、`platform` |
| `log(message, level = "info")` | `host/log` | `Promise<void>`，写入宿主 stderr；级别可为 `debug`、`info`、`warn`、`error` 或自定义字符串 |
| `getSwitchState()` | `host/getSwitchState` | `Promise<SwitchStateResult>`，包含 `switchState: number \| null` 和 `agentReachable: boolean` |
| `supports(method)` | 无 | 初始化数据是否声明了该方法；初始化前返回 `false` |
| `call<TResult, TParams>(method, params?, timeoutMs?)` | 对应的已注册宿主方法 | 带类型参数的请求，默认超时 30,000 毫秒 |
| `notify(method, params?)` | 取决于宿主的通知处理器 | 发送后不等待响应，返回 `void` |

**能力发现与调用权限是两回事。** 当前宿主会声明全部三个内置方法，即使插件清单只允许其中一部分。`supports()` 不会授予或验证权限。未声明权限的内置宿主请求会收到 JSON-RPC 错误 `-32601`。请将实际调用的每个宿主方法加入 `permissions`。

内置方法是请求处理器：请使用 `host.log()` 或 `host.call()`，不要使用 `host.notify("host/log", ...)`。当前默认宿主没有注册自定义通知处理器。宿主集成方注册对应处理器后，通用 `call` / `notify` 才能用于这些扩展；TypeScript 泛型不会在运行时校验远端 JSON。

读取拨杆的插件可以使用以下回调，同时在清单中声明 `host/log` 和 `host/getSwitchState`：

```ts
import { definePlugin, servePlugin } from "@ahakey/plugin-sdk";

servePlugin(definePlugin({
  name: "Lever Reader",
  version: "0.1.0",
  async onInitialized({ host }) {
    if (!host.supports("host/getSwitchState")) {
      await host.log("Lever readings are unavailable in this host", "warn");
      return;
    }
    const state = await host.getSwitchState();
    const mode = !state.agentReachable || state.switchState === null
      ? "unavailable"
      : state.switchState === 0 ? "automatic approval" : "manual approval";
    await host.log(`Lever: ${mode}`);
  },
}));
```

Swift 桥接通过 `/tmp/ahakey.sock` 向本地 Agent 查询。拿到数值型拨杆状态时才返回 `agentReachable: true`，这个字段不是独立的 Agent 健康探测结果。`0` 表示自动审批，非零值表示手动审批；`null` 表示未获得可用状态，不能视为自动审批。该 API 只读取状态，不会改变拨杆位置或批准工具调用。

## 插件方法与通知

在 `methods` 中注册宿主到插件的请求处理器。参数默认是 `unknown`，应像 Greeter 教程一样先验证再使用。返回值可以是可 JSON 序列化的数据，或对应的 promise；返回 `undefined` 会转换为 JSON `null`。方法名会在初始化时自动声明。

宿主发送不带 `id` 的消息时，由 `notifications` 中的处理器处理：

```ts
import { definePlugin, servePlugin } from "@ahakey/plugin-sdk";

servePlugin(definePlugin({
  name: "Refresh Listener",
  version: "0.1.0",
  notifications: {
    "greeter/refresh": () => {
      console.error("Refresh requested by host");
    },
  },
}));
```

宿主必须显式发送 `greeter/refresh`，它不是内置事件。通知没有响应；未知通知会被忽略，处理器失败会写入 stderr。请保留 `plugin/*` 生命周期名称，注册同名处理器可能覆盖 SDK 的生命周期处理。

## 服务选项与错误处理

| `PluginServerOptions` 字段 | 默认值 |
|---|---|
| `input` | `process.stdin` |
| `output` | `process.stdout` |
| `errorOutput` | `process.stderr` |
| `defaultCallTimeoutMs` | `30_000` |

将选项作为 `servePlugin` 的第二个参数传入，或使用 `new AhaKeyPluginServer(definition, options)` 后调用 `.start()`。自定义流适合测试，参考[已有测试辅助代码](../../sdks/typescript/test/sdk.test.mjs)。`server.context` 在初始化前为 undefined，服务关闭后不可重新启动。

单次调用可通过 `host.call` 的第三个参数指定毫秒超时。传入 `0` 或负数会禁用该请求的超时计时器。超时和通信关闭会以普通 `Error` 拒绝 promise；JSON-RPC 错误响应会以 `JsonRpcError` 拒绝，包含 `code`、`message` 和可选的 `data`。

| `JSON_RPC_ERROR` 键 | 错误码 | 含义 |
|---|---|---|
| `parseError` | `-32700` | JSON 无法解析 |
| `invalidRequest` | `-32600` | JSON-RPC 消息结构或请求 ID 无效 |
| `methodNotFound` | `-32601` | 方法不存在，或宿主方法被清单权限拒绝 |
| `invalidParams` | `-32602` | 初始化参数无效，或插件主动进行的参数验证失败 |
| `internalError` | `-32603` | 请求处理器抛出普通错误 |

可用 `throw new JsonRpcError(JSON_RPC_ERROR.invalidParams, "Expected { name: string }")` 返回结构化错误。通过 RPC 传输的值（包括错误数据）必须可 JSON 序列化。

**stdout 专用于 RPC。** 诊断日志请使用 `await host.log(...)`、`console.error(...)` 或 `process.stderr.write(...)`。`console.log()` 和第三方库输出到 stdout 的启动信息可能破坏协议。消息格式为每行一个 UTF-8 JSON 对象，不使用 `Content-Length` 头或 JSON-RPC 批量数组。

## 内置示例

| 示例 | 方法 | 行为 |
|---|---|---|
| [hello-plugin](../../sdks/typescript/examples/hello-plugin/src/main.ts) | `demo/greet`、`demo/getStatus` | 演示宿主元信息、拨杆读数和宿主到插件的调用 |
| [lever-counter](../../sdks/typescript/examples/lever-counter/src/main.ts) | `demo/flowStats` | 每秒轮询，统计模式变化和停留时间，退出时清理资源 |

在 `sdks/typescript/` 执行以下命令：

| 命令 | 用途 |
|---|---|
| `npm run build:sdk` | 只编译 SDK，包含类型声明文件 |
| `npm run build` | 编译 SDK 和两个示例 |
| `npm run typecheck` | 构建 SDK 类型声明，并检查示例源码类型 |
| `npm test` | 构建全部内容并运行 SDK 的 Node.js 测试 |
| `npm run demo` | 构建并启动 macOS 展示窗口，每两秒刷新状态 |
| `npm run demo:agent` | 在前台运行 Agent，读取真实 BLE / 拨杆状态 |
| `npm run demo:cli` | 构建并加载两个示例，执行简短的生命周期检查 |

使用真实键盘时，先在第二个终端运行 `npm run demo:agent`，再在第一个终端运行 `npm run demo`。这个开发命令不会安装 LaunchAgent 或修改 IDE hook。Agent 需要占用 BLE 连接；打开完整应用配置键盘前，请先按 `Ctrl-C` 停止它。

没有真实拨杆读数时，计数器可以读取模拟文件。保持展示窗口运行，在另一个终端修改文件：

```bash
printf '0\n' > "$HOME/.ahakey-fake-lever"
# 至少等待一个轮询周期，再切换为手动模式。
printf '1\n' > "$HOME/.ahakey-fake-lever"
cat "$HOME/.ahakey-flow-stats.json"
```

这些命令会覆盖模拟输入，真实读数始终优先。计数器在首次获得模式、模式变化和退出时保存快照，文件不会持续刷新。每次启动进程时重新计数。`demo/flowStats` 会计算当前快照，但展示窗口没有为该方法提供专用按钮。模拟文件仅供这个示例使用，不会改变真实拨杆。

## 常见问题

| 现象 | 检查方法 |
|---|---|
| 没有加载任何插件 | 将 `AHAKEY_PLUGINS_DIR` 指向父目录，每个直接子目录都需要有效的 `plugin.json`；在宿主 stderr 查看加载失败原因 |
| `env: node: No such file or directory` | 宿主环境可能与终端不同。将 `entrypoint.command` 设为 Node.js 的实际绝对路径，或提供合适的 `PATH` |
| 缺少 `dist/main.js` 或无法导入包 | 编译插件并安装运行时依赖；打包 SDK 前先构建 |
| 宿主调用返回 `-32601` | 检查方法名和清单中的 `permissions`，仅检查 `supports()` 不足以确定权限 |
| 拨杆显示离线或 `null` | 启动开发 Agent、连接键盘，并避免多个程序竞争 BLE；将该读数视为不可用 |
| RPC 超时或无法识别消息 | 确保 stdout 没有日志，生命周期回调及时完成，并确认请求的处理器存在 |
| 退出后进程仍在运行 | 在生命周期清理中停止定时器、关闭监听和 socket，并释放其他活跃的 Node.js 资源 |

为 Swift 演示命令设置 `AHAKEY_PLUGIN_DEBUG=1`，可将宿主发出的请求和收到的消息打印到 stderr，例如 `AHAKEY_PLUGIN_DEBUG=1 npm run demo:cli`。API 细节以 [SDK 源码](../../sdks/typescript/src/index.ts)和 [Swift 宿主实现](../../ahakeyconfig-mac/Sources/AhaKeyPluginKit/PluginHost.swift)为准。
