import Foundation

/// opencode v2 的「Hooks 安装器」。
///
/// 与其它四个 Agent 不同，opencode 没有可写的 hook 配置文件，它是 **TS/JS plugin**：
/// 把 `ahakey-bridge.js` 放进 `~/.config/opencode/plugins/` 就会在每次 opencode 载入时执行。
/// 因此这里的「安装」= 落地一个带标记的 plugin 文件，「移除」= 只删掉带标记的那个文件。
///
/// 设计约束（对应 upstream 的几条既有规矩）：
/// - **不碰** `opencode.json(c)`：只写 plugins 目录，使用者自己的插件配置不受影响。
/// - 带版本标记 `ahakey-opencode-bridge v1`，重装会整体覆盖、卸载只删自己的文件。
/// - 尊重 `XDG_CONFIG_HOME`（opencode 本身也遵循）。
public enum OpenCodePluginInstaller {
    public static let marker = "ahakey-opencode-bridge v1"
    public static let fileName = "ahakey-bridge.js"
    public static let agentPlaceholder = "__AHAKEY_AGENT_BIN__"

    public enum InstallError: LocalizedError {
        case cannotCreateDirectory(String, Error)
        case cannotWrite(String, Error)

        public var errorDescription: String? {
            switch self {
            case let .cannotCreateDirectory(path, error):
                return "无法创建目录 \(path)：\(error.localizedDescription)"
            case let .cannotWrite(path, error):
                return "无法写入 \(path)：\(error.localizedDescription)"
            }
        }
    }

    /// `$XDG_CONFIG_HOME/opencode/plugins`，否则 `~/.config/opencode/plugins`。
    public static func pluginsDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("opencode/plugins", isDirectory: true)
        }
        return home.appendingPathComponent(".config/opencode/plugins", isDirectory: true)
    }

    public static func pluginURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        pluginsDirectory(environment: environment, home: home)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// 只认「带 AhaKey 标记」的文件，避免把使用者自己写的 `ahakey-bridge.js` 当成我们的。
    public static func isInstalled(at url: URL = pluginURL()) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    @discardableResult
    public static func install(agentBinaryPath: String, to url: URL = pluginURL()) throws -> URL {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw InstallError.cannotCreateDirectory(dir.path, error)
        }
        let text = script(agentBinaryPath: agentBinaryPath)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.cannotWrite(url.path, error)
        }
        return url
    }

    /// 回传是否真的删掉了东西；没有标记的文件一律不动。
    @discardableResult
    public static func remove(at url: URL = pluginURL()) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard isInstalled(at: url) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    public static func script(agentBinaryPath: String) -> String {
        let escaped = jsonStringLiteral(agentBinaryPath)
        return rawScript.replacingOccurrences(of: "\"\(agentPlaceholder)\"", with: escaped)
    }

    /// 路径可能含引号/反斜线，先转成合法 JSON 字符串字面量再嵌进 JS。
    private static func jsonStringLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [])) ?? Data("[]".utf8)
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [String],
              let first = array.first,
              let encoded = try? JSONEncoder().encode(first),
              let literal = String(data: encoded, encoding: .utf8) else {
            return "\"\(value)\""
        }
        return literal
    }

    // MARK: - plugin 源码

    private static let rawScript = #"""
// ahakey-opencode-bridge v1
// 由 AhaKey Studio 安装与管理；重新安装会整体覆盖本文件，移除时只删除本文件。
//
// 作用：把 opencode v2 的「拨杆审批」与「任务状态」接到 AhaKey 键盘。
//   - 审批：ctx.permission.hook("evaluate") → ahakeyconfig-agent hook OpenCodePermissionEvaluate
//   - 状态：ctx.event.subscribe() → OpenCodeSessionStart / OpenCodeUserPromptSubmit / OpenCodeStop
//
// 设计约定（勿改）：
//   - deny 是终局，plugin 永远不把 deny 改成 allow。
//   - 任何超时、解析失败、连接失败都保持 opencode 原有判定（fail-safe：交回 TUI 问人）。
import { spawn } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const AGENT_BIN = "__AHAKEY_AGENT_BIN__"
// opencode 的 TUI 会同步等 evaluate，所以这里留 3s 硬上限；agent 侧 2s 先回。
const EVALUATE_TIMEOUT_MS = 3000
const STATE_TIMEOUT_MS = 1500
const LOG_PATH = path.join(os.homedir(), ".cache", "opencode", "ahakey-bridge.log")

function log(line) {
  try {
    fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true })
    fs.appendFileSync(LOG_PATH, new Date().toISOString() + " " + line + "\n")
    if (fs.statSync(LOG_PATH).size > 512 * 1024) {
      const keep = fs.readFileSync(LOG_PATH, "utf8").split("\n").slice(-400).join("\n")
      fs.writeFileSync(LOG_PATH, keep)
    }
  } catch {}
}

function callAgent(event, payload, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false
    const finish = (value) => { if (!settled) { settled = true; resolve(value) } }
    let child
    try {
      child = spawn(AGENT_BIN, ["hook", event], { stdio: ["pipe", "pipe", "pipe"] })
    } catch (error) {
      log("spawn failed " + event + ": " + error)
      return finish(null)
    }
    let out = ""
    const timer = setTimeout(() => {
      try { child.kill("SIGKILL") } catch {}
      log("timeout " + event)
      finish(null)
    }, timeoutMs)
    child.stdout.on("data", (chunk) => { out += chunk })
    child.stderr.on("data", () => {})
    child.on("error", (error) => { clearTimeout(timer); log("error " + event + ": " + error); finish(null) })
    child.on("close", () => {
      clearTimeout(timer)
      const text = String(out).trim()
      if (!text) return finish(null)
      try { finish(JSON.parse(text)) } catch { log("bad json " + event + ": " + text.slice(0, 200)); finish(null) }
    })
    child.stdin.on("error", () => {})
    child.stdin.write(JSON.stringify(payload) + "\n")
    child.stdin.end()
  })
}

// 备注（实测结论，别再重复踩）：opencode 会按 location 多次激活同一个 plugin
// （一次 run 内 2～8 次，每次都会重新注册 hook），但**不会**因此让一次审批触发多次回调：
// 实测 N 个实例 → N 个 assert → N 次 evaluate → N 次 spawn，是 1:1，不是 1:N。
// 所以这里刻意不加进程外去重（加了反而会误杀 800ms 内两次同动作的合法审批）。
// 若将来发现 1:N，再在 agent 侧按 (event, session, action) 做选主。

// 燈條語意（AhaKey 的 IDE 狀態 → 燈效，出厂默认映射）：
//   4 SessionStart  → rainbowWave（開場）
//   7 UserPromptSubmit → breathing（藍，執行中）
//   2 PostToolUse   → successSweep（綠閃，工具完成）
//   6 TaskCompleted → successSweep（綠，任務完成）   ← 成功要走這個，不是 Stop
//   5 Stop          → middleLight（單燈，結束/失敗）
//   1 Permission    → approvalWait（紅，等待批准；由 evaluate 路徑觸發）
// opencode 會按 location 多次激活 plugin，且**每個實例都會收到同一份事件流**（實測同事件重複 2~3 次）。
// 對策：純事件驅動的聚合（不猜、不用計時器），重複事件收斂到同一狀態；跨實例的
// 重複送出由 dedupe 窗口吸收。完成判斷只用 session 生命週期事件，不看 step 級事件。
const dedupeDir = path.join(os.tmpdir(), "ahakey-bridge")
const DEDUPE_WINDOW_MS = 800

function claimStateOnce(key) {
  try {
    fs.mkdirSync(dedupeDir, { recursive: true })
    const file = path.join(dedupeDir, Buffer.from(key).toString("hex").slice(0, 40))
    const now = Date.now()
    try { if (now - fs.statSync(file).mtimeMs < DEDUPE_WINDOW_MS) return false } catch {}
    fs.writeFileSync(file, String(now))
    return true
  } catch {
    return true
  }
}

// 開場彩虹：60 秒內只送一次（多視窗、多 location 都會觸發 setup，不能每次都閃彩虹）
function claimRainbow() {
  try {
    const file = path.join(os.tmpdir(), "ahakey-bridge-rainbow")
    const now = Date.now()
    try { if (now - fs.statSync(file).mtimeMs < 60000) return false } catch {}
    fs.writeFileSync(file, String(now))
    return true
  } catch {
    return true
  }
}

function callAgentDeduped(event, payload, timeoutMs) {
  const key = [event, payload && payload.session_id, payload && payload.tool_name].join("|")
  if (!claimStateOnce(key)) return Promise.resolve(null)
  return callAgent(event, payload, timeoutMs)
}

// ── session 聚合 ────────────────────────────────────────────────────────────
// 只看「這一輪是否還在跑」：execution.started → running，execution.succeeded/failed → done。
// 多視窗時取合併結果：任一個還在跑就是「執行中」；全部結束才變「完成」。
const sessions = new Map()   // sessionID -> "running" | "done"
const SESSION_TTL_MS = 10 * 60 * 1000
let heartbeatTimer = null
let lastEmitted = null

function phaseFor(sessionID, phase) {
  if (!sessionID) return
  sessions.set(sessionID, { phase, at: Date.now(), sid: sessionID.slice(-6) })
  emitAggregate()
}

// 殘留 running 是實測踩過的坑：某個 session 收到 execution.started 卻再也沒有結束事件時，
// 它會讓聚合永遠停在「執行中」，心跳每 20 秒把燈拉回藍色（任務其實早就結束了）。
// 對策：超過 STALE_RUNNING_MS 沒有任何事件、且已經有別的 session 完成過的 running，視為殘留。
const STALE_RUNNING_MS = 120000

function pruneStaleSessions(now) {
  let pruned = 0
  for (const [sid, v] of sessions) {
    if (v.phase !== "running") continue
    if (now - v.at > STALE_RUNNING_MS) {
      // 不要 delete：刪掉之後聚合會變空 → 不發任何狀態 → 燈條停在最後一個顏色（藍）。
      // 改成 done，聚合就會收斂成「完成」並亮綠。
      sessions.set(sid, { phase: "done", at: now, sid: v.sid })
      pruned += 1
    }
  }
  return pruned
}

function emitAggregate(force) {
  const now = Date.now()
  pruneStaleSessions(now)
  const phases = [...sessions.values()].map((v) => v.phase)
  let phase = null
  if (phases.includes("running")) phase = "running"
  else if (phases.includes("done")) phase = "done"
  if (!phase) return
  if (!force && phase === lastEmitted) return
  lastEmitted = phase
  const event = phase === "running" ? "OpenCodeUserPromptSubmit" : "OpenCodeTaskCompleted"
  void callAgentDeduped(event, { session_id: "aggregate" }, STATE_TIMEOUT_MS)
}

// 短暫提示（工具完成 = 2、權限 = 1）只該亮一下子，之後要回到聚合狀態（通常是 7 執行中）。
// 沒有這個回收，燈條會一直停在提示態 —— 模擬測試抓到的（工具完成後回不到藍）。
const TRANSIENT_RECOVER_MS = 2000
const transientTimers = new Map()

function scheduleTransientRecovery() {
  const key = "global"
  const existing = transientTimers.get(key)
  if (existing) clearTimeout(existing)
  const t = setTimeout(() => {
    transientTimers.delete(key)
    // 非強制：若期間聚合狀態已經送過（例如任務剛好結束送 6），就不要再補一次
    emitAggregate(false)
  }, TRANSIENT_RECOVER_MS)
  if (t.unref) t.unref()
  transientTimers.set(key, t)
}

/// 送一個「短暫」燈態（工具開始/完成、權限請求）。它不進聚合，
/// 所以要把 lastEmitted 清掉，否則回收時會被「狀態沒變」擋住、燈條卡在提示態。
function emitDirect(event, sessionID) {
  lastEmitted = null
  void callAgentDeduped(event, { session_id: sessionID || "direct" }, STATE_TIMEOUT_MS)
  scheduleTransientRecovery()
}

const HEARTBEAT_MS = 20000

function startHeartbeat() {
  if (heartbeatTimer) return
  heartbeatTimer = setInterval(() => {
    // 長任務若完全沒有事件，daemon 看門狗會誤判「已死」而發 Stop(5)（紅燈）→ 心跳補送「執行中」
    // 注意：心跳本身不刷新 session 的 at，否則殘留的 running 永遠不會被 prune（見 pruneStaleSessions）
    const running = [...sessions.values()].filter((v) => v.phase === "running")
    if (running.length > 0) {
      const detail = running.map((v) => v.sid + "@" + Math.round((Date.now() - v.at) / 1000) + "s").join(",")
      log("heartbeat: running sessions=" + running.length + "/" + sessions.size + " [" + detail + "]")
      emitAggregate(true)
    }
  }, HEARTBEAT_MS)
  if (heartbeatTimer.unref) heartbeatTimer.unref()
}

const EVENT_MAP = {
  "session.created": "OpenCodeSessionStart",
  "session.active": "OpenCodeSessionStart",
  "session.compaction.started": "OpenCodePreCompact",
}

export default {
  id: "ahakey-bridge",
  async setup(ctx) {
    // opencode 的扩展机制只有 plugin（没有 hooks 设置文件）。plugin 内可用官方文档化的
    // event / tool.execute.before 挂钩；而下面这个 permission hooks 属于 2.2.5 的**内部 API**
    // （官方 /docs/permissions 只描述 config 的静态规则）。找不到它就退回「不介入」，
    // opencode 使用自己的默认审批流程，AhaKey 不会挡住它。
    if (ctx && ctx.permission && typeof ctx.permission.hook === "function") {
      try {
        await ctx.permission.hook("evaluate", evaluate)
        if (!globalThis.__ahakeyBridgeReady) {
          globalThis.__ahakeyBridgeReady = true
          log("bridge ready: evaluate hook registered, agent=" + AGENT_BIN)
        } else {
          log("bridge re-attached for another location")
        }
      } catch (error) {
        log("permission.evaluate unavailable: " + error)
      }
    } else {
      log("permission.hook unavailable: approval is NOT bridged in this opencode build")
    }
    // 補一手：plugin 載入即代表「這個位置啟動了 opencode」。實測 session.created 常常在
    // plugin 訂閱事件流之前就發出（race），導致開場的彩虹波永遠看不到。
    // 但 opencode 會反覆啟用 location，若每次都送就會變成一直在閃彩虹 → 節流 + 只在閒置時送。
    if (sessions.size === 0 && claimRainbow()) {
      void callAgent("OpenCodeSessionStart", { session_id: "startup" }, STATE_TIMEOUT_MS)
    }

    if (ctx && ctx.tool && typeof ctx.tool.hook === "function") {
      try {
        let lastToolDoneAt = 0
        await ctx.tool.hook("execute.before", (event) => {
          // 工具開始 → 執行中（藍）
          emitDirect("OpenCodePreToolUse", (event && event.sessionID) || "tool")
        })
        await ctx.tool.hook("execute.after", (event) => {
          const ok = !event || event.status !== "error"
          if (!ok) return
          const now = Date.now()
          if (now - lastToolDoneAt < 1500) return   // 連續工具時不要把燈閃來閃去
          lastToolDoneAt = now
          // 工具完成 → 柔和的單點藍色來回流水（singleMove）
          emitDirect("OpenCodePostToolUse", (event && event.sessionID) || "tool")
        })
      } catch (error) {
        log("tool.execute hooks unavailable: " + error)
      }
    }
    watchEvents(ctx)
  },
}

// opencode 在「规则判定后、动作执行或提示发布前」调用；只改 ask，不动 allow / deny。
async function evaluate(event) {
  if (!event || event.effect !== "ask") return
  const reply = await callAgent("OpenCodePermissionEvaluate", {
    session_id: event.sessionID,
    tool_name: event.action,
    resources: event.resources,
  }, EVALUATE_TIMEOUT_MS)
  if (!reply || reply.decision !== "allow") {
    // fail-safe：保留 opencode 原本的 ask，交给 TUI 问人。写一行日志便于现场排查。
    log("defer " + String(event.action || "") + " → " + ((reply && reply.decision) || "no-reply"))
    return
  }
  event.effect = "allow"
  log("lever auto → allow " + String(event.action || ""))
}

function watchEvents(ctx) {
  if (!ctx || !ctx.event || typeof ctx.event.subscribe !== "function") {
    log("event.subscribe unavailable; only approval is bridged")
    return
  }
  const stream = ctx.event.subscribe()
  ;(async () => {
    startHeartbeat()
    try {
      for await (const event of stream) {
      const type = event && event.type
      const sessionID = (event.data && event.data.sessionID) || ""
      switch (type) {
        case "session.execution.started":
          phaseFor(sessionID, "running")
          continue
        case "session.execution.succeeded":
        case "session.execution.failed":
        case "session.execution.interrupted":
          phaseFor(sessionID, "done")
          continue
        case "session.idle":
          phaseFor(sessionID, "done")
          continue
        case "session.status": {
          const status = (event.data && event.data.status) || {}
          phaseFor(sessionID, status.type === "idle" ? "done" : "running")
          continue
        }
        case "location.shutdown":
          // 這個 location 被關掉了（opencode run 結束 / TUI 退出）→ 裡面不可能還有東西在跑。
          // 直接把殘留的 running 收成 done，比等 2 分鐘的 prune 更即時。
          for (const [sid, v] of sessions) {
            if (v.phase === "running") sessions.set(sid, { phase: "done", at: Date.now(), sid: v.sid })
          }
          emitAggregate(true)
          continue
        case "permission.asked":
          emitDirect("OpenCodePermissionRequested", sessionID)
          continue
        case "permission.replied":
        case "permission.rejected":
          emitAggregate(true)
          continue
        default: {
          const hookEvent = EVENT_MAP[type]
          if (!hookEvent) continue
          await callAgentDeduped(hookEvent, { session_id: sessionID, event: type }, STATE_TIMEOUT_MS)
        }
      }
      }
    } finally {
      // 事件流結束（location 關閉 / plugin 重載）→ 停掉心跳與殘留計時器，
      // 否則舊實例會繼續每 20 秒把「執行中」寫回裝置，造成燈號在綠/藍之間亂跳。
      if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null }
      for (const t of transientTimers.values()) clearTimeout(t)
      transientTimers.clear()
    }
  })().catch((error) => log("event loop: " + error))
}
"""#
}
