# `@ahakey/plugin-sdk`

[English](README.md) · [简体中文](../../docs/zh/typescript-sdk.md) · [SDK overview](../README.md)

Write AhaKey plugins in TypeScript. The host starts your plugin as a child process; the SDK handles newline-delimited JSON-RPC 2.0 over stdin/stdout, lifecycle callbacks, host calls, and custom plugin methods.

## Contents

- [Quick start](#quick-start)
- [Create your own plugin](#create-your-own-plugin)
- [Manifest and discovery](#manifest-and-discovery)
- [Lifecycle](#lifecycle)
- [Host API](#host-api)
- [Plugin methods and notifications](#plugin-methods-and-notifications)
- [Server options and errors](#server-options-and-errors)
- [Included examples](#included-examples)
- [Troubleshooting](#troubleshooting)

## Quick start

Requirements: Node.js 18+ and npm. The SDK is an ES module package. CI uses Node.js 20; the supplied Swift demos require macOS 13+ and Swift 5.9+ with a compatible Xcode toolchain. A keyboard is only needed for real lever readings.

From the repository root:

```bash
cd sdks/typescript
npm ci
npm run typecheck
npm test
npm run demo
```

`npm test` builds the SDK and both examples, then runs the Node.js tests. `npm run demo` builds them again and opens the macOS showcase, which displays plugin metadata, host information, lever state, and a greeting action. Both example plugins are discovered. The lever counter may write `~/.ahakey-flow-stats.json`; see [included examples](#included-examples).

The examples resolve `@ahakey/plugin-sdk` from the local package. For a separate project, use the local package workflow below.

## Create your own plugin

### 1. Build and package the SDK

From `sdks/typescript/`, after `npm ci`:

```bash
npm run build:sdk
npm pack
```

For the current package version, this creates `ahakey-plugin-sdk-0.1.0.tgz`. Use the filename printed by `npm pack` if the version changes. This guide installs that local archive and does not require a published npm package.

### 2. Create a separate plugin project

Create a `greeter/` directory inside a parent directory named `plugins/`, then enter `greeter/`. Add `package.json`:

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

Install the archive using its actual absolute path, then install the build tools:

```bash
npm install /absolute/path/to/desktop/sdks/typescript/ahakey-plugin-sdk-0.1.0.tgz
npm install --save-dev typescript @types/node
```

Add `tsconfig.json`:

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

Create `src/main.ts`:

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

### 3. Add the manifest and build

Create `plugin.json` beside `package.json`:

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

Run `npm run build` in `greeter/`. The resulting layout is:

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

### 4. Load it with the development host

From the AhaKey repository root, replace the path below with the absolute path to the parent `plugins/` directory:

```bash
AHAKEY_PLUGINS_DIR="/absolute/path/to/plugins" swift run --package-path ahakeyconfig-mac Plugin
```

The CLI discovers plugins, initializes them, waits about one second, and shuts them down. It does not call `greeter/greet`; use the [Swift host example](../README.md#swift-host-integration) to make that request. Starting `node dist/main.js` alone waits for JSON-RPC input and does not simulate a host.

For a custom directory, use the direct Swift command above. `npm run demo` and `npm run demo:cli` explicitly set `AHAKEY_PLUGINS_DIR` to the SDK's bundled examples. Their showcase actions target `demo/getStatus` and `demo/greet`, so they do not automatically provide buttons for arbitrary custom methods.

## Manifest and discovery

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | Stable plugin identifier; use a unique value such as `com.example.greeter` |
| `name`, `version` | Yes | Display metadata strings; keep them consistent with `definePlugin` |
| `entrypoint.command` | Yes | Executable name resolved through `/usr/bin/env`, or an absolute executable path |
| `entrypoint.args` | Yes | Argument array; use `[]` when there are no arguments |
| `entrypoint.env` | No | String-to-string environment map for the child process |
| `permissions` | No | Allowed host method names; defaults to `[]` |

The host replaces `${pluginDir}` in argument strings and environment **values** with the absolute directory containing the manifest. It does not expand this placeholder in `entrypoint.command`. The child process's working directory is the plugin directory. Commands run directly, without shell expansion or shell operators.

If `entrypoint.env` is omitted, the process inherits the host environment. If supplied, the current Swift implementation uses it as the process environment rather than merging it with the host's environment. Include the `PATH` and other variables your command needs, or use an absolute executable path.

`PluginManager` scans non-hidden immediate subdirectories of:

```text
~/Library/Application Support/AhaKeyConfig/plugins/
```

`AHAKEY_PLUGINS_DIR` replaces this root. Each child directory needs a manifest; placing `plugin.json` directly in the root will not discover it. The current runnable hosts are `Plugin` and `PluginShowcase`; copying a plugin into this directory does not yet enable it in the main desktop app.

Ship compiled JavaScript and its runtime dependencies alongside the manifest, or bundle the runtime imports yourself. The host launches the entry point; it does not build TypeScript or install npm dependencies.

## Lifecycle

`definePlugin(definition)` supplies TypeScript typing and returns the definition. `servePlugin(definition, options?)` creates and starts an `AhaKeyPluginServer`.

| Host message | SDK behavior | Your callback |
|---|---|---|
| Request `plugin/initialize` | Stores `{ host, hostMethods }`; returns plugin name, version, and method names | `onInitialize(params, host)` |
| Notification `plugin/initialized` | Signals that initialization completed | `onInitialized({ host, initializeParams })` |
| Request `plugin/shutdown` | Waits for cleanup, then returns `null` | `onShutdown(context)` |
| Notification `plugin/exit` | Runs the callback and closes the RPC peer | `onExit(context)` |

All callbacks can be synchronous or async. `onInitialize` may return a partial `{ name, version, methods }` override; changing the advertised method list does not register new handlers. Store a host reference during `onInitialize` if your custom methods need it. Start background work in `onInitialized` and clear timers, watchers, and other open resources in `onShutdown`/`onExit`.

Shutdown and exit callbacks accept `PluginContext | undefined`, so handle calls that arrive before initialization. `server.close()` closes the transport and rejects pending host calls; it does not run your shutdown hook or force the Node.js process to exit. Keep cleanup bounded: the Swift lifecycle helpers default to five seconds for initialization and three seconds for shutdown.

## Host API

`host` is an `AhaKeyHost` provided to lifecycle callbacks and available as `server.host`.

| SDK method | Host permission | Result |
|---|---|---|
| `getInfo()` | `host/getInfo` | `Promise<HostAppInfo>` with string fields `bundleID`, `version`, `build`, `platform` |
| `log(message, level = "info")` | `host/log` | `Promise<void>`; logs to host stderr. Levels include `debug`, `info`, `warn`, `error`, and custom strings |
| `getSwitchState()` | `host/getSwitchState` | `Promise<SwitchStateResult>` with `switchState: number \| null` and `agentReachable: boolean` |
| `supports(method)` | None | Whether the initialization payload advertised that method; `false` before initialization |
| `call<TResult, TParams>(method, params?, timeoutMs?)` | Matching registered host method | Typed request; defaults to a 30,000 ms timeout |
| `notify(method, params?)` | Depends on the host's notification handler | Sends without waiting for a response; returns `void` |

**Capability discovery and permissions are separate.** The current host advertises all three built-in methods, even if a plugin's manifest allows only some of them. `supports()` does not grant or verify permission. An undeclared built-in host request is rejected with JSON-RPC error `-32601`. Add every host method you call to `permissions`.

The built-in methods are request handlers: use `host.log()` or `host.call()`, not `host.notify("host/log", ...)`. The current default host does not register custom notification handlers. Generic `call`/`notify` methods become useful when a host integration registers corresponding handlers; TypeScript generics do not validate remote JSON at runtime.

A lever-aware plugin can use this callback, with `host/log` and `host/getSwitchState` in its manifest:

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

The Swift bridge asks the local agent through `/tmp/ahakey.sock`. It reports `agentReachable: true` when it obtains a numeric switch state; this is not a separate agent-health probe. `0` means automatic approval; a nonzero state means manual approval. `null` means a usable state was not returned and must not be treated as automatic approval. This API reads state; it does not change the lever or approve a tool call.

## Plugin methods and notifications

Register host-to-plugin request handlers in `methods`. Parameters default to `unknown`; validate incoming data before using it, as in the greeter tutorial. Return a JSON-serializable value or a promise for one. An `undefined` return becomes JSON `null`. Method names are advertised automatically during initialization.

Register handlers for host-to-plugin messages without an `id` in `notifications`:

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

Your host must explicitly send `greeter/refresh`; it is not a built-in event. Notifications have no response. Unknown notifications are ignored, and handler failures are logged to stderr. Keep the `plugin/*` lifecycle names reserved; registering the same name can replace the SDK's lifecycle handler.

## Server options and errors

| `PluginServerOptions` field | Default |
|---|---|
| `input` | `process.stdin` |
| `output` | `process.stdout` |
| `errorOutput` | `process.stderr` |
| `defaultCallTimeoutMs` | `30_000` |

Pass these options as the second argument to `servePlugin`, or construct `new AhaKeyPluginServer(definition, options)` and call `.start()`. Custom streams are useful for tests; see the [existing test harness](test/sdk.test.mjs). `server.context` is undefined until initialization. The server cannot be restarted after it closes.

For an individual request, pass milliseconds as the third argument to `host.call`. A timeout of `0` or a negative number disables that request's timer. Timeouts and closed-peer failures reject with ordinary `Error` objects; JSON-RPC error responses reject with `JsonRpcError`, whose fields are `code`, `message`, and optional `data`.

| `JSON_RPC_ERROR` key | Code | Meaning |
|---|---|---|
| `parseError` | `-32700` | Invalid JSON |
| `invalidRequest` | `-32600` | Invalid JSON-RPC envelope or request ID |
| `methodNotFound` | `-32601` | Unknown method, or a host method denied by manifest permissions |
| `invalidParams` | `-32602` | Invalid initialization parameters or explicit parameter validation failure |
| `internalError` | `-32603` | An ordinary error thrown by a request handler |

Use `throw new JsonRpcError(JSON_RPC_ERROR.invalidParams, "Expected { name: string }")` for a structured failure. Values sent over RPC, including error data, must be JSON-serializable.

**Reserve stdout for RPC.** Use `await host.log(...)`, `console.error(...)`, or `process.stderr.write(...)` for diagnostics. `console.log()` and third-party stdout banners can corrupt the protocol. The framing is one UTF-8 JSON object per line, without `Content-Length` headers or JSON-RPC batch arrays.

## Included examples

| Example | Methods | Behavior |
|---|---|---|
| [hello-plugin](examples/hello-plugin/src/main.ts) | `demo/greet`, `demo/getStatus` | Demonstrates host metadata, lever readings, and host-to-plugin calls |
| [lever-counter](examples/lever-counter/src/main.ts) | `demo/flowStats` | Polls every second; counts mode changes and dwell time; cleans up on shutdown |

Run these commands from `sdks/typescript/`:

| Command | Purpose |
|---|---|
| `npm run build:sdk` | Compile only the SDK, including declaration files |
| `npm run build` | Compile the SDK and both examples |
| `npm run typecheck` | Build SDK declarations and typecheck the example sources |
| `npm test` | Build everything and run the SDK's Node.js tests |
| `npm run demo` | Build and launch the macOS showcase; its status refreshes every two seconds |
| `npm run demo:agent` | Run the agent in the foreground for real BLE/lever readings |
| `npm run demo:cli` | Build, load both examples, and run a short lifecycle check |

For the physical keyboard, start `npm run demo:agent` in a second terminal, then `npm run demo` in the first. This development command does not install a LaunchAgent or modify IDE hooks. The agent needs the BLE connection; stop it with `Ctrl-C` before opening the full app for keyboard configuration.

When no real lever reading is available, the counter can read a simulation file. With the showcase running, use another terminal to change it:

```bash
printf '0\n' > "$HOME/.ahakey-fake-lever"
# Wait at least one polling interval, then switch to manual.
printf '1\n' > "$HOME/.ahakey-fake-lever"
cat "$HOME/.ahakey-flow-stats.json"
```

These commands overwrite the simulation input. Real readings take precedence. The counter saves its snapshot when it first obtains a mode, on mode changes, and on shutdown; it is not a continuously refreshed file. Counters start fresh for each process. `demo/flowStats` computes a current snapshot, but the showcase does not have a dedicated button for that method. The simulation is specific to this example and does not change the real lever.

## Troubleshooting

| Symptom | What to check |
|---|---|
| No plugins loaded | Point `AHAKEY_PLUGINS_DIR` at the parent directory; each immediate child needs a valid `plugin.json`. Inspect host stderr for load failures |
| `env: node: No such file or directory` | The host's environment may differ from your terminal. Set `entrypoint.command` to the actual absolute Node.js path, or provide a suitable `PATH` |
| Missing `dist/main.js` or package import | Build the plugin and install its runtime dependencies. Build the SDK before packing it |
| `-32601` from a host call | Check both the exact method name and the manifest's `permissions`; `supports()` alone is insufficient |
| Lever state is offline or `null` | Start the development agent, connect the keyboard, and avoid competing BLE owners. Treat the reading as unavailable |
| RPC timeout or unrecognized frame | Keep stdout free of logs, finish lifecycle hooks promptly, and confirm that the requested handler exists |
| Process stays alive after shutdown | Clear timers, close watchers/sockets, and release other active Node.js resources in lifecycle cleanup |

Set `AHAKEY_PLUGIN_DEBUG=1` on a Swift demo command to print the host's outgoing requests and incoming frames to stderr, for example `AHAKEY_PLUGIN_DEBUG=1 npm run demo:cli`. For API details, consult the [SDK source](src/index.ts) and [Swift host implementation](../../ahakeyconfig-mac/Sources/AhaKeyPluginKit/PluginHost.swift).
