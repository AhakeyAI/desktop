#!/usr/bin/env node
// opencode plugin（ahakey-bridge.js）的行為模擬測試 —— 手動執行，不進 CI。
//
// 用法：
//   1. 先讓 App 安裝 plugin（~/.config/opencode/plugins/ahakey-bridge.js 存在）
//   2. node ahakeyconfig-mac/scripts/plugin-sim.mjs
//   3. 讀 /tmp/sim/result.json 或看終端機的 ✅/❌ 表
//
// 為什麼要這個：plugin 是動態注入到 opencode 裡的 JS，Swift 單元測試碰不到它的聚合邏輯；
// 這裡把 AGENT_BIN 換成 stub、把時間常數縮小，就能在幾秒內把所有狀態機路徑跑一遍。
//
// 做法：把已安裝的 plugin 複製一份，改掉 AGENT_BIN → stub 腳本（只記錄事件名）、
// 把幾個時間常數縮小，然後用假的 opencode ctx 載入它，灌事件、檢查它實際送出的燈號事件。
//
// 驗證目標（使用者的要求）：
//   1. 任務完成 → 6（綠 sweep）
//   2. 等待審批/卡住 → 1（琥珀/紅）
//   3. 執行中 → 7（藍呼吸）
//   4. 各種故障（事件殘缺、重複、plugin 重載、殘留 session、缺 permission 掛鉤）不得讓燈號停在錯的狀態

import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const PLUGIN_SRC = path.join(os.homedir(), ".config/opencode/plugins/ahakey-bridge.js")
const STUB = "/tmp/sim/agent-stub.mjs"
const EMITTED = "/tmp/sim/emitted.log"
const TMP = "/tmp/sim"
const STATE_EVENT = {
  OpenCodeSessionStart: 4,
  OpenCodeUserPromptSubmit: 7,
  OpenCodePreToolUse: 3,
  OpenCodePostToolUse: 2,
  OpenCodeTaskCompleted: 6,
  OpenCodeStop: 5,
  OpenCodePermissionRequested: 1,
}

function buildPlugin(caseName) {
  let src = fs.readFileSync(PLUGIN_SRC, "utf8")
  // AGENT_BIN 是 JSON 字串字面值；換成 stub 路徑
  src = src.replace(/const AGENT_BIN = "[^"]*"/, `const AGENT_BIN = ${JSON.stringify(STUB)}`)
  // 縮小時間常數，讓測試跑得快又不失語意
  src = src.replace(/const HEARTBEAT_MS = \d+/, "const HEARTBEAT_MS = 150")
  src = src.replace(/const STALE_RUNNING_MS = \d+/, "const STALE_RUNNING_MS = 400")
  src = src.replace(/const DEDUPE_WINDOW_MS = \d+/, "const DEDUPE_WINDOW_MS = 40")
  src = src.replace(/const STATE_TIMEOUT_MS = \d+/, "const STATE_TIMEOUT_MS = 300")
  src = src.replace(/const TRANSIENT_RECOVER_MS = \d+/, "const TRANSIENT_RECOVER_MS = 120")
  const file = path.join(TMP, `plugin-${caseName}.mjs`)
  fs.writeFileSync(file, src)
  return file
}

function resetRuntimeState() {
  for (const f of [EMITTED, path.join(TMP, "rainbow"), "/tmp/ahakey-bridge-rainbow", "/tmp/ahakey-bridge-leader"]) {
    try { fs.unlinkSync(f) } catch {}
  }
  try {
    for (const f of fs.readdirSync(path.join(TMP, "dedupe"))) fs.unlinkSync(path.join(TMP, "dedupe", f))
  } catch {}
  try {
    for (const f of fs.readdirSync("/tmp/ahakey-bridge")) fs.unlinkSync(path.join("/tmp/ahakey-bridge", f))
  } catch {}
  delete globalThis.__ahakeyBridgeReady
}

function makeStream() {
  const queue = []
  let resolveNext = null
  let closed = false
  return {
    push(event) {
      if (resolveNext) { const r = resolveNext; resolveNext = null; r({ value: event, done: false }) }
      else queue.push(event)
    },
    close() {
      closed = true
      if (resolveNext) { const r = resolveNext; resolveNext = null; r({ value: undefined, done: true }) }
    },
    iterable: {
      [Symbol.asyncIterator]() {
        return {
          next() {
            if (queue.length) return Promise.resolve({ value: queue.shift(), done: false })
            if (closed) return Promise.resolve({ value: undefined, done: true })
            return new Promise((res) => { resolveNext = res })
          },
        }
      },
    },
  }
}

async function loadPlugin(caseName, opts = {}) {
  resetRuntimeState()
  const file = buildPlugin(caseName)
  const ctx = {
    location: { directory: "/tmp/sim/project" },
    permission: opts.noPermissionHook ? undefined : {
      hook: async (_name, fn) => { ctx._evaluate = fn },
    },
    tool: {
      hook: async (name, fn) => { (ctx._tools ||= {})[name] = fn },
    },
    event: { subscribe: () => { ctx._stream = makeStream(); return ctx._stream.iterable } },
  }
  const mod = await import(`file://${file}?case=${caseName}-${Date.now()}`)
  await mod.default.setup(ctx)
  await sleep(30) // 讓 watchEvents 的 async generator 就位
  return { ctx, mod }
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)) }
function emitted() {
  try {
    return fs.readFileSync(EMITTED, "utf8").split("\n").filter(Boolean)
  } catch { return [] }
}
function emittedStates() { return emitted().map((e) => STATE_EVENT[e] ?? e) }
function clearEmitted() { try { fs.unlinkSync(EMITTED) } catch {} }

function ev(type, data = {}) { return { type, data } }

const results = []
async function runCase(name, expect, body) {
  try {
    clearEmitted()
    const notes = await body()
    const got = emittedStates()
    // 子序列比對（允許出現額外的 4=session start）
    const filtered = got.filter((s) => s !== 4).filter((v, i, a) => i === 0 || v !== a[i - 1])
    const ok = JSON.stringify(filtered) === JSON.stringify(expect)
    results.push({ name, ok, expect, got, filtered, notes })
  } catch (error) {
    results.push({ name, ok: false, expect, got: emittedStates(), error: String(error && error.stack || error) })
  }
}

// ────────────────────────────────── 案例 ──────────────────────────────────

// 1. 單輪：執行中 → 完成（藍 → 綠）
await runCase("單輪：started → succeeded", [7, 6], async () => {
  const { ctx } = await loadPlugin("c1")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "7 = 藍呼吸；6 = 綠 sweep"
})

// 2. 多步 + 工具：7 → 3 → 2 → 6
await runCase("多步：含工具 before/after", [7, 3, 2, 7, 6], async () => {
  const { ctx } = await loadPlugin("c2")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(40)
  await ctx._tools["execute.before"]({ sessionID: "A", tool: "bash" })
  await sleep(40)
  await ctx._tools["execute.after"]({ sessionID: "A", tool: "bash" })
  await sleep(60)
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "工具完成後聚合會把狀態拉回執行中（7）"
})

// 3. 多視窗：A 結束但 B 還在跑 → 不得變綠
await runCase("多視窗：A 完成、B 還在跑 → 不亂發（維持 7）", [], async () => {
  const { ctx } = await loadPlugin("c3")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  ctx._stream.push(ev("session.execution.started", { sessionID: "B" }))
  await sleep(60)
  clearEmitted()
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(80)
  ctx._stream.close()
  return "A 結束後應保持執行中"
})

// 4. 多視窗：全部結束 → 綠
await runCase("多視窗：全部完成 → 綠", [6], async () => {
  const { ctx } = await loadPlugin("c4")
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  ctx._stream.push(ev("session.execution.started", { sessionID: "B" }))
  await sleep(60)
  clearEmitted()
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(40)
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "B" }))
  await sleep(80)
  ctx._stream.close()
  return "兩個都結束才變綠"
})

// 5. 殘留 session：只有 started、之後沒有事件 → 超時後收斂成 done（綠），不得永遠卡藍
await runCase("殘留 session：只有 started → 超時後變綠", [7, 6], async () => {
  const { ctx } = await loadPlugin("c5")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "ghost" }))
  await sleep(120)
  // 等 prune（STALE_RUNNING_MS=400）+ 心跳（150ms）
  await sleep(700)
  ctx._stream.close()
  return "心跳每 150ms 會重送執行中；400ms 後 prune 應收斂成 done"
})

// 6. location 關閉：殘留 running 立即收斂
await runCase("location.shutdown：殘留 running 立即收斂", [7, 6], async () => {
  const { ctx } = await loadPlugin("c6")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "ghost" }))
  await sleep(60)
  ctx._stream.push(ev("location.shutdown", {}))
  await sleep(80)
  ctx._stream.close()
  return "shutdown 應立刻把 running 轉成 done"
})

// 7. 審批：權限請求 → 1（琥珀/紅）；回覆後回到執行中 → 完成後綠
await runCase("權限：asked → 1；replied + 完成 → 7,6", [1, 7, 6], async () => {
  const { ctx } = await loadPlugin("c7")
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(50)
  clearEmitted()
  ctx._stream.push(ev("permission.asked", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.push(ev("permission.replied", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "權限亮 1；回覆後回 7；完成 6"
})

// 8. 兩輪對話：7,6 → 7,6
await runCase("兩輪：完成後再開始一輪", [7, 6, 7, 6], async () => {
  const { ctx } = await loadPlugin("c8")
  clearEmitted()
  for (let i = 0; i < 2; i++) {
    ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
    await sleep(50)
    ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
    await sleep(60)
  }
  ctx._stream.close()
  return ""
})

// 9. 畸形事件：不得崩潰、不得亂發狀態
await runCase("畸形事件：null/缺欄位/未知型別 → 不亂發", [], async () => {
  const { ctx } = await loadPlugin("c9")
  clearEmitted()
  ctx._stream.push(null)
  ctx._stream.push({})
  ctx._stream.push({ type: "session.execution.started" })               // 缺 data
  ctx._stream.push({ type: "session.execution.started", data: null })
  ctx._stream.push({ type: "session.execution.started", data: {} })     // 缺 sessionID
  ctx._stream.push({ type: "weird.event", data: { sessionID: "X" } })
  ctx._stream.push({ type: "session.execution.succeeded", data: null })
  await sleep(120)
  ctx._stream.close()
  return "應完全不產生狀態事件（不會亮錯燈）"
})

// 10. 缺 permission 掛鉤：setup 不得拋錯（退回不介入）
await runCase("缺 permission 掛鉤：setup 不拋錯、狀態照常", [7], async () => {
  const { ctx } = await loadPlugin("c10", { noPermissionHook: true })
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "只有狀態事件，沒有審批介入"
})

// 11. 重複實例：同一事件被兩個實例收到 → 去重後只發一次
await runCase("重複實例去重：同事件兩實例只發一次", [7], async () => {
  const a = await loadPlugin("c11a")
  const b = await loadPlugin("c11b")
  clearEmitted()
  a.ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  b.ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(120)
  a.ctx._stream.close(); b.ctx._stream.close()
  return "800ms（測試值 40ms）內的第二個實例應被 dedupe 抑制"
})

// 12. 長任務：中途有工具、之後長時間沒事件，最後完成 → 中間有 7、最後 6
await runCase("長任務：安靜期由提示回收/心跳維持 7，最後 6", [7, 3, 2, 7, 6], async () => {
  const { ctx } = await loadPlugin("c12")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(40)
  await ctx._tools["execute.before"]({ sessionID: "A", tool: "bash" })
  await sleep(40)
  await ctx._tools["execute.after"]({ sessionID: "A", tool: "bash" })
  await sleep(60)
  await sleep(220)                       // 超過心跳間隔（150ms），應補一次 7
  ctx._stream.push(ev("session.execution.succeeded", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "安靜期由心跳維持執行中"
})

// 13. 失敗/中斷：failed → 6（綠色仍是「結束」語意，不是紅）
await runCase("失敗/中斷：failed → 結束狀態", [7, 6], async () => {
  const { ctx } = await loadPlugin("c13")
  clearEmitted()
  ctx._stream.push(ev("session.execution.started", { sessionID: "A" }))
  await sleep(50)
  ctx._stream.push(ev("session.execution.failed", { sessionID: "A" }))
  await sleep(60)
  ctx._stream.close()
  return "failed 收斂成 done（與 succeeded 同一語意）"
})

// 14. 審批掛鉤本身：evaluate 被呼叫時要回 ask（手動檔）且不 crash
await runCase("evaluate 掛鉤：回 ask 且不崩", ["OpenCodePermissionEvaluate"], async () => {
  const { ctx } = await loadPlugin("c14")
  clearEmitted()
  const event = { effect: "ask", sessionID: "A", tool: { name: "bash" } }
  await ctx._evaluate(event)
  await sleep(60)
  const got = emittedStates().filter((x) => x !== "OpenCodePermissionEvaluate")
  const ok = event.effect === "ask"
  if (!ok) throw new Error("手動檔（switchState=1）不得被改成 " + event.effect)
  return `evaluate 回 effect=${event.effect}（手動檔維持 ask），另外送出的燈態=${JSON.stringify(got)}`
})

// ────────────────────────────────── 輸出 ──────────────────────────────────
const pad = (s, n) => String(s).padEnd(n)
console.log("\n" + pad("案例", 46) + pad("期望", 22) + pad("實得", 22) + "結果")
console.log("─".repeat(108))
for (const r of results) {
  const exp = JSON.stringify(r.expect ?? [])
  const got = JSON.stringify(r.filtered ?? r.got ?? [])
  console.log(pad(r.name, 46) + pad(exp, 22) + pad(got, 22) + (r.ok ? "✅ PASS" : "❌ FAIL"))
  if (r.notes) console.log("    ↳ " + r.notes)
  if (r.error) console.log("    ↳ ERROR: " + r.error.split("\n")[0])
}
const failed = results.filter((r) => !r.ok)
console.log("\n" + `${results.length - failed.length}/${results.length} 通過`)
if (failed.length) {
  console.log("失敗案例：")
  for (const f of failed) console.log("  - " + f.name + " 期望 " + JSON.stringify(f.expect) + " 實得 " + JSON.stringify(f.filtered ?? f.got))
}
fs.writeFileSync("/tmp/sim/result.json", JSON.stringify(results, null, 2))
process.exit(failed.length ? 1 : 0)
