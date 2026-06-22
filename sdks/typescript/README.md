# `@ahakey/plugin-sdk`

TypeScript SDK for AhaKey desktop plugins.

The AhaKey host launches each plugin as a child process and communicates through
newline-delimited JSON-RPC 2.0 messages over stdin/stdout. This SDK hides the
transport and lifecycle plumbing so a plugin only needs to register hooks and
methods.

## Requirements

- Node.js 18 or newer
- npm

## Build and test

```bash
cd sdks/typescript
npm install
npm test
```

## Minimal plugin

```ts
import { definePlugin, servePlugin } from "@ahakey/plugin-sdk";

servePlugin(definePlugin({
  name: "Hello Plugin",
  version: "0.1.0",
  async onInitialized({ host }) {
    const info = await host.getInfo();
    await host.log(`Connected to ${info.bundleID}`);
  },
}));
```

Each plugin directory also needs a `plugin.json` manifest:

```json
{
  "id": "com.example.hello",
  "name": "Hello Plugin",
  "version": "0.1.0",
  "entrypoint": {
    "command": "node",
    "args": ["${pluginDir}/dist/main.js"]
  },
  "permissions": ["host/getInfo", "host/log"]
}
```

The host replaces `${pluginDir}` with the directory containing `plugin.json`.
Only the declared `host/*` permissions can be called by the plugin.

## Host API

```ts
host.getInfo()
host.log("message", "info")
host.getSwitchState()
host.supports("host/getSwitchState")
host.call("host/customMethod", params)
host.notify("host/customNotification", params)
```

Current built-in host methods:

| Method | Result |
| --- | --- |
| `host/getInfo` | App bundle ID, version, build and platform |
| `host/log` | Writes a plugin log message to the host |
| `host/getSwitchState` | Returns the keyboard lever state and agent reachability |

## Plugin methods

Plugins can expose methods for future host calls:

```ts
servePlugin(definePlugin({
  name: "Greeter",
  version: "0.1.0",
  methods: {
    "hello/greet": (params) => ({ message: `Hello, ${params.name}!` }),
  },
}));
```

The SDK automatically implements:

- `plugin/initialize`
- `plugin/initialized`
- `plugin/shutdown`
- `plugin/exit`

## Run the included example

Launch the visual macOS showcase:

```bash
cd sdks/typescript
npm install
npm run demo
```

To read the physical lever state during source development, start the Agent in a
second terminal before launching the showcase. This does not install a
LaunchAgent or modify IDE hooks:

```bash
cd sdks/typescript
npm run demo:agent
```

Then run `npm run demo` in the first terminal. The Agent owns the BLE connection
while it is running; stop it with `Ctrl-C` before opening the full AhaKey Studio
app for keyboard configuration.

The `PluginShowcase` Swift target opens a small window that:

- discovers and launches the TypeScript example plugin;
- shows the plugin metadata and declared RPC methods;
- calls `demo/getStatus` to read host app metadata and the physical lever state;
- calls `demo/greet` to demonstrate a host-to-plugin request;
- refreshes the lever state every 2 seconds through the AhaKey agent bridge.

If the AhaKey agent is not running or does not own the BLE connection, the lever
state is displayed as offline. That is expected: the rest of the demo still
works.

When running the full `AhaKeyConfig` target from source, the existing
`安装并启用` button can also install the development Agent binary from the local
SwiftPM build directory. Packaged `.app` builds continue to use the bundled
`Contents/MacOS/ahakeyconfig-agent`.

For a terminal-only lifecycle smoke test, run:

```bash
npm run demo:cli
```
