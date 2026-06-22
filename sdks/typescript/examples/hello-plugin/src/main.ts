import {
  definePlugin,
  servePlugin,
  type AhaKeyHost,
  type SwitchStateResult,
} from "@ahakey/plugin-sdk";

let host: AhaKeyHost | undefined;

function describeSwitchState(state: SwitchStateResult): string {
  if (!state.agentReachable) {
    return "offline: start the AhaKey agent and let it own the BLE connection";
  }
  return state.switchState === 0
    ? "automatic approval"
    : `manual approval (switchState=${state.switchState ?? "unknown"})`;
}

async function getShowcaseStatus() {
  if (host === undefined) {
    throw new Error("Plugin has not completed initialization");
  }

  const [info, state] = await Promise.all([
    host.getInfo(),
    host.getSwitchState(),
  ]);
  return {
    plugin: "AhaKey TypeScript Showcase",
    host: info,
    lever: {
      ...state,
      description: describeSwitchState(state),
    },
  };
}

servePlugin(definePlugin({
  name: "AhaKey TypeScript Showcase",
  version: "0.1.0",
  methods: {
    "demo/greet": (params) => {
      const name = typeof params === "object"
        && params !== null
        && "name" in params
        && typeof params.name === "string"
        ? params.name
        : "world";
      return { message: `Hello, ${name}!` };
    },
    "demo/getStatus": getShowcaseStatus,
  },
  onInitialize(_params, connectedHost) {
    host = connectedHost;
  },
  async onInitialized({ host: connectedHost }) {
    const status = await getShowcaseStatus();
    const description = status.lever.description;
    await connectedHost.log(
      `TypeScript showcase connected to ${status.host.bundleID}; lever=${description}`,
    );
  },
  async onShutdown(context) {
    const connectedHost = context?.host ?? host;
    if (connectedHost === undefined) {
      return;
    }
    await connectedHost.log(
      "TypeScript showcase received plugin/shutdown",
    );
  },
}));
