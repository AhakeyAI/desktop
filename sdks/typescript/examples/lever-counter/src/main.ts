import { servePlugin, definePlugin, type AhaKeyHost } from "@ahakey/plugin-sdk";
import { readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// AhaKey Lever Counter —— 一个最小的插件 demo:
//   后台每秒读一次物理拨杆,统计你在「自动 / 手动」两档之间翻了多少次、各待了多久,
//   每次翻档写一条 host 日志,并把快照落到 ~/.ahakey-flow-stats.json(随时 cat 查看)。
//   暴露 RPC 方法 `demo/flowStats` 供宿主主动查询。
//
// 无硬件演示:agent / 键盘读不到拨杆时,回退读模拟文件 ——
//   echo 0 > ~/.ahakey-fake-lever   # 自动档(full-send)
//   echo 1 > ~/.ahakey-fake-lever   # 手动档(human in the loop)

/** 模拟拨杆文件:真实拨杆读不到时的兜底输入。 */
const FAKE_LEVER = join(homedir(), ".ahakey-fake-lever");
/** 每次更新都把统计快照写到这里,方便直接 `cat` 查看。 */
const STATS_FILE = join(homedir(), ".ahakey-flow-stats.json");
const POLL_MS = 1000;

type Mode = "auto" | "manual";

interface Stats {
  startedAt: number;
  flips: number;
  enter: Record<Mode, number>;
  dwellMs: Record<Mode, number>;
  current: Mode | null;
  currentSince: number;
}

const stats: Stats = {
  startedAt: Date.now(),
  flips: 0,
  enter: { auto: 0, manual: 0 },
  dwellMs: { auto: 0, manual: 0 },
  current: null,
  currentSince: Date.now(),
};

let host: AhaKeyHost | undefined;
let timer: ReturnType<typeof setInterval> | undefined;

/** switchState 语义:0 = 自动档,非 0 = 手动档。 */
function modeOf(switchState: number | null): Mode | null {
  if (switchState === null) return null;
  return switchState === 0 ? "auto" : "manual";
}

/** 真实拨杆优先;读不到(offline)时回退到模拟文件。 */
async function readMode(): Promise<Mode | null> {
  if (host !== undefined) {
    try {
      const r = await host.getSwitchState();
      if (r.agentReachable && r.switchState !== null) return modeOf(r.switchState);
    } catch {
      // 落到模拟文件
    }
  }
  try {
    const n = Number(readFileSync(FAKE_LEVER, "utf8").trim());
    return Number.isFinite(n) ? modeOf(n) : null;
  } catch {
    return null;
  }
}

function fmt(ms: number): string {
  const total = Math.max(0, Math.round(ms / 1000));
  return `${Math.floor(total / 60)}m${String(total % 60).padStart(2, "0")}s`;
}

/** 只读快照:把当前档位「尚未结算」的时长也算进去。 */
function snapshot() {
  const now = Date.now();
  const dwell: Record<Mode, number> = { ...stats.dwellMs };
  const cur = stats.current;
  if (cur !== null) dwell[cur] += now - stats.currentSince;
  return {
    current: cur ?? "unknown",
    currentDwell: cur === null ? "0m00s" : fmt(now - stats.currentSince),
    flips: stats.flips,
    auto: { entered: stats.enter.auto, total: fmt(dwell.auto) },
    manual: { entered: stats.enter.manual, total: fmt(dwell.manual) },
    uptime: fmt(now - stats.startedAt),
  };
}

function persist(): void {
  try {
    writeFileSync(STATS_FILE, `${JSON.stringify(snapshot(), null, 2)}\n`);
  } catch {
    // 写不了就算了,不影响计数
  }
}

async function tick(): Promise<void> {
  const mode = await readMode();
  if (mode === null) return; // 读不到拨杆,不计

  const now = Date.now();
  const cur = stats.current;

  // 首次确定档位
  if (cur === null) {
    stats.current = mode;
    stats.currentSince = now;
    stats.enter[mode] += 1;
    persist();
    return;
  }

  // 翻档:结算上一档时长 + 计数
  if (mode !== cur) {
    stats.dwellMs[cur] += now - stats.currentSince;
    stats.flips += 1;
    stats.enter[mode] += 1;
    stats.current = mode;
    stats.currentSince = now;
    persist();
    const snap = snapshot();
    await host?.log(
      `lever ${cur.toUpperCase()}→${mode.toUpperCase()} · flips=${snap.flips} · auto ${snap.auto.total} / manual ${snap.manual.total}`,
    );
  }
}

servePlugin(definePlugin({
  name: "AhaKey Lever Counter",
  version: "0.1.0",
  methods: {
    "demo/flowStats": () => snapshot(),
  },
  onInitialize(_params, connectedHost) {
    host = connectedHost;
  },
  async onInitialized() {
    await host?.log("lever-counter online · polling switch state every 1s");
    timer = setInterval(() => {
      void tick();
    }, POLL_MS);
    timer.unref();
    void tick();
  },
  onShutdown() {
    if (timer !== undefined) {
      clearInterval(timer);
      timer = undefined;
    }
    persist();
  },
}));
