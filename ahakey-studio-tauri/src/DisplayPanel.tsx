import React, { useEffect, useRef, useState } from "react";
import { invoke, isTauri } from "@tauri-apps/api/core";
import {
  ArrowDown,
  ArrowUp,
  Image,
  Plus,
  RefreshCw,
  ShieldCheck,
  Trash2,
} from "lucide-react";
import {
  Account,
  Cards,
  Provider,
  QuotaResult,
  defaultCards,
  encodeRgb565,
  fitRect,
  imageDimensions,
  newAccount,
  percentage,
  providerNames,
} from "./display";
const native = isTauri();
export function DisplayPanel() {
  const [config, setConfig] = useState<Cards>(defaultCards);
  const [loaded, setLoaded] = useState(!native);
  const [saved, setSaved] = useState<string>("");
  const [results, setResults] = useState<Record<string, QuotaResult>>({});
  const [tokens, setTokens] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [selected, setSelected] = useState("minimax");
  const [windowIndex, setWindowIndex] = useState(0);
  const [mode, setMode] = useState<"contain" | "cover">("contain");
  const [imageSource, setImageSource] = useState("");
  const [imageReady, setImageReady] = useState(false);
  const [imageVersion, setImageVersion] = useState(0);
  const [imageName, setImageName] = useState("");
  const imageCanvas = useRef<HTMLCanvasElement>(null);
  const cardCanvas = useRef<HTMLCanvasElement>(null);
  const imageRequest = useRef(0);
  const importRequest = useRef(0);
  const alive = useRef(true);
  const pending = useRef(false);
  const configRef = useRef(config);
  configRef.current = config;
  const dirty = JSON.stringify(config) !== saved;
  const account =
    config.accounts.find((a) => a.id === selected) ?? config.accounts[0];
  const result = account ? results[account.id] : undefined;
  const visibleWindowIndex = Math.min(
    windowIndex,
    Math.max(0, (result?.windows.length ?? 1) - 1),
  );
  const quota = result?.windows[visibleWindowIndex];
  useEffect(() => {
    alive.current = true;
    if (native)
      invoke<{ config: Cards; results: QuotaResult[] }>("get_cards")
        .then((s) => {
          if (alive.current) {
            setConfig(s.config);
            setLoaded(true);
            setSaved(JSON.stringify(s.config));
            setResults(
              Object.fromEntries(s.results.map((r) => [r.accountId, r])),
            );
          }
        })
        .catch((e) => {
          if (alive.current) setError(String(e));
        });
    return () => {
      alive.current = false;
      imageRequest.current++;
      importRequest.current++;
    };
  }, []);
  function patchAccount(id: string, patch: Partial<Account>) {
    setConfig((c) => ({
      ...c,
      accounts: c.accounts.map((a) => (a.id === id ? { ...a, ...patch } : a)),
    }));
    setResults((r) => {
      const next = { ...r };
      delete next[id];
      return next;
    });
  }
  async function run(action: () => Promise<void>) {
    if (pending.current) return;
    pending.current = true;
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await action();
    } catch (e) {
      if (alive.current) setError(String(e));
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  async function refreshAll() {
    await run(async () => {
      for (const a of configRef.current.accounts.filter((a) => a.enabled)) {
        if (!alive.current) break;
        const identity = JSON.stringify(a);
        const next = await invoke<QuotaResult>("refresh_quota", {
          accountId: a.id,
        });
        if (
          alive.current &&
          JSON.stringify(
            configRef.current.accounts.find((v) => v.id === a.id),
          ) === identity
        )
          setResults((r) => ({ ...r, [a.id]: next }));
      }
    });
  }
  useEffect(() => {
    if (!native || dirty || !config.autoRefresh) return;
    const timer = window.setInterval(() => {
      void refreshAll();
    }, config.refreshSeconds * 1000);
    return () => window.clearInterval(timer);
  }, [config.autoRefresh, config.refreshSeconds, dirty]);
  useEffect(() => {
    const ctx = cardCanvas.current?.getContext("2d");
    if (!ctx) return;
    ctx.fillStyle = "#102922";
    ctx.fillRect(0, 0, 160, 80);
    ctx.fillStyle = "#ffffff";
    ctx.font = "11px sans-serif";
    ctx.fillText((account?.label ?? "选择账户").slice(0, 20), 8, 16);
    ctx.font = "bold 25px sans-serif";
    ctx.fillText(percentage(quota?.remainingPercent), 8, 45);
    ctx.font = "10px sans-serif";
    ctx.fillText((quota?.label ?? "尚未查询真实额度").slice(0, 24), 8, 61);
    ctx.fillStyle = "#c5d8cc";
    ctx.font = "9px sans-serif";
    ctx.fillText(
      result?.state === "stale"
        ? "旧数据 · 查询失败"
        : result?.updatedAt
          ? new Date(result.updatedAt * 1000).toLocaleTimeString()
          : "电脑预览 · 尚未发送",
      8,
      75,
    );
  }, [account, quota, result]);
  useEffect(() => {
    const current = ++imageRequest.current;
    setImageReady(false);
    const ctx = imageCanvas.current?.getContext("2d");
    if (!ctx) return;
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, 160, 80);
    if (!imageSource) return;
    const img = new window.Image();
    img.onload = () => {
      if (current !== imageRequest.current) return;
      ctx.fillStyle = "#000000";
      ctx.fillRect(0, 0, 160, 80);
      ctx.drawImage(img, ...fitRect(img.naturalWidth, img.naturalHeight, mode));
      setImageReady(true);
    };
    img.onerror = () => {
      if (current === imageRequest.current) setError("图片解码失败");
    };
    img.src = imageSource;
  }, [imageSource, mode, imageVersion]);
  async function importImage(file: File | undefined) {
    if (!file) return;
    const request = ++importRequest.current;
    setImageReady(false);
    setError("");
    try {
      if (file.size > 4 * 1024 * 1024) throw new Error("图片上限为 4 MB");
      const bytes = new Uint8Array(await file.arrayBuffer());
      imageDimensions(bytes, file.type);
      const source = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result));
        reader.onerror = () => reject(new Error("图片读取失败"));
        reader.readAsDataURL(file);
      });
      if (request === importRequest.current && alive.current) {
        setImageName(file.name);
        setImageSource(source);
        setImageVersion((v) => v + 1);
      }
    } catch (e) {
      if (request === importRequest.current && alive.current)
        setError(String(e));
    }
  }
  function exportImage() {
    const canvas = imageCanvas.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx || !imageReady) return;
    const bytes = encodeRgb565(ctx.getImageData(0, 0, 160, 80).data);
    const url = URL.createObjectURL(
      new Blob([bytes as BlobPart], { type: "application/octet-stream" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = "ahakey-160x80.rgb565";
    a.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function move(index: number, delta: number) {
    setConfig((c) => {
      const accounts = [...c.accounts];
      [accounts[index], accounts[index + delta]] = [
        accounts[index + delta],
        accounts[index],
      ];
      return { ...c, accounts };
    });
  }
  return (
    <div className="display-page">
      <section className="surface">
        <div className="section-heading">
          <h2>
            <Image size={18} aria-hidden="true" />
            屏幕素材
          </h2>
          <span className="badge">本机预览</span>
        </div>
        <p className="section-description">
          160 × 80 ·
          RGB565。先预览和导出素材；设备图片存储区域尚未核实，上传保持关闭。
        </p>
        <div className="display-preview-row">
          <canvas
            ref={imageCanvas}
            width={160}
            height={80}
            role="img"
            aria-label={imageName ? `图片预览：${imageName}` : "空白屏幕预览"}
          />
          <div className="display-preview-controls">
            <label>
              导入 PNG / JPEG
              <input
                type="file"
                accept="image/png,image/jpeg"
                onChange={(e) => void importImage(e.target.files?.[0])}
              />
            </label>
            <label>
              缩放方式
              <select
                value={mode}
                onChange={(e) => setMode(e.target.value as typeof mode)}
              >
                <option value="contain">完整显示 · 留黑边</option>
                <option value="cover">填满屏幕 · 居中裁剪</option>
              </select>
            </label>
            <div className="button-row">
              <button
                className="secondary"
                disabled={!imageReady}
                onClick={exportImage}
              >
                导出 RGB565
              </button>
              <button disabled title="需要先核实设备存储布局及固件 ACK">
                上传到键盘（未开放）
              </button>
            </div>
          </div>
        </div>
      </section>
      <section className="surface">
        <div className="section-heading">
          <h2>额度插件</h2>
          <button
            className="secondary"
            disabled={!native || !loaded || dirty || busy}
            onClick={() => void refreshAll()}
          >
            <RefreshCw size={16} aria-hidden="true" />
            {busy ? "处理中…" : "刷新已启用账户"}
          </button>
        </div>
        <p className="section-description">
          以真实账户和套餐为准，不按模型名推算。密钥只保存在本机系统凭据库，不发送到键盘。
        </p>
        {!native && (
          <p className="hint">
            浏览器仅可编辑和预览；保存、凭据管理与真实查询需要原生客户端。
          </p>
        )}
        {error && (
          <p className="message error" role="alert">
            {error}
          </p>
        )}
        {notice && (
          <p className="message" role="status">
            {notice}
          </p>
        )}
        {!loaded && !error && (
          <p className="hint" role="status">
            正在读取卡片配置…
          </p>
        )}
        <fieldset disabled={!loaded} className="quota-editor">
          <div className="quota-settings-row">
            <label>
              <input
                type="checkbox"
                checked={config.autoRefresh}
                onChange={(e) =>
                  setConfig((c) => ({ ...c, autoRefresh: e.target.checked }))
                }
              />{" "}
              本页面打开时自动刷新
            </label>
            <label>
              间隔（秒）
              <input
                type="number"
                min={60}
                max={3600}
                value={config.refreshSeconds}
                onChange={(e) =>
                  setConfig((c) => ({
                    ...c,
                    refreshSeconds: Number(e.target.value),
                  }))
                }
              />
            </label>
            <button
              className="primary"
              disabled={!native || !loaded || !dirty || busy}
              onClick={() =>
                void run(async () => {
                  const next = configRef.current;
                  await invoke("save_cards", { config: next });
                  if (alive.current) {
                    setSaved(JSON.stringify(next));
                    setNotice("卡片配置已保存；没有向键盘写入");
                  }
                })
              }
            >
              保存卡片配置
            </button>
          </div>
          <div className="quota-grid">
            {config.accounts.map((a, index) => {
              const r = results[a.id];
              return (
                <article className="quota-account" key={a.id}>
                  <div className="section-heading">
                    <label className="switch-label">
                      <input
                        type="checkbox"
                        checked={a.enabled}
                        onChange={(e) =>
                          patchAccount(a.id, { enabled: e.target.checked })
                        }
                      />
                      {a.label}
                    </label>
                    <div className="button-row">
                      <button
                        className="icon-button"
                        aria-label={`上移 ${a.label}`}
                        disabled={index === 0 || busy}
                        onClick={() => move(index, -1)}
                      >
                        <ArrowUp size={16} />
                      </button>
                      <button
                        className="icon-button"
                        aria-label={`下移 ${a.label}`}
                        disabled={index === config.accounts.length - 1 || busy}
                        onClick={() => move(index, 1)}
                      >
                        <ArrowDown size={16} />
                      </button>
                    </div>
                  </div>
                  <div className="quota-windows">
                    {r?.windows.length ? (
                      r.windows.map((w) => (
                        <div key={w.id}>
                          <span>{w.label}</span>
                          <strong>
                            {percentage(w.remainingPercent)} <small>剩余</small>
                          </strong>
                          {w.remainingPercent != null && (
                            <meter
                              min={0}
                              max={100}
                              value={w.remainingPercent}
                              low={a.warningPercent}
                              optimum={100}
                              aria-label={`${w.label}剩余比例`}
                            />
                          )}
                          <small>
                            {w.resetsAt
                              ? `重置：${new Date(w.resetsAt * 1000).toLocaleString()}`
                              : "重置时间未提供"}
                          </small>
                        </div>
                      ))
                    ) : (
                      <p className="hint">尚无额度数据</p>
                    )}
                  </div>
                  <p className="hint" role="status">
                    {r?.error ??
                      (r?.state === "unknown"
                        ? "响应字段缺失，额度未知"
                        : r?.updatedAt
                          ? `更新时间：${new Date(r.updatedAt * 1000).toLocaleString()}`
                          : "未查询")}
                    {r?.state === "stale" ? " · 上面是旧数据" : ""}
                  </p>
                  <details className="compact-details">
                    <summary>账户设置与密钥</summary>
                    <div className="quota-fields">
                      <label>
                        名称
                        <input
                          value={a.label}
                          maxLength={40}
                          onChange={(e) =>
                            patchAccount(a.id, { label: e.target.value })
                          }
                        />
                      </label>
                      <label>
                        服务
                        <select
                          value={a.provider}
                          onChange={(e) => {
                            const p = e.target.value as Provider;
                            patchAccount(a.id, {
                              provider: p,
                              endpoint: "",
                              mappings:
                                p === "custom"
                                  ? [
                                      {
                                        label: "剩余额度",
                                        pointer: "/remainingPercent",
                                        usedPercent: false,
                                      },
                                    ]
                                  : [],
                            });
                            setTokens((t) => ({ ...t, [a.id]: "" }));
                          }}
                        >
                          {Object.entries(providerNames).map(([id, label]) => (
                            <option key={id} value={id}>
                              {label}
                            </option>
                          ))}
                        </select>
                      </label>
                      {(a.provider === "minimax" || a.provider === "glm") && (
                        <label>
                          <input
                            type="checkbox"
                            checked={a.international}
                            onChange={(e) =>
                              patchAccount(a.id, {
                                international: e.target.checked,
                              })
                            }
                          />{" "}
                          国际站账户
                        </label>
                      )}
                      <label>
                        低额度提醒阈值（%）
                        <input
                          type="number"
                          min={0}
                          max={100}
                          value={a.warningPercent}
                          onChange={(e) =>
                            patchAccount(a.id, {
                              warningPercent: Number(e.target.value),
                            })
                          }
                        />
                      </label>
                      {a.provider === "custom" && (
                        <>
                          <label>
                            只读 HTTPS 查询地址
                            <input
                              type="url"
                              value={a.endpoint}
                              onChange={(e) =>
                                patchAccount(a.id, { endpoint: e.target.value })
                              }
                              placeholder="https://example.com/quota"
                            />
                          </label>
                          {a.mappings.map((m, i) => (
                            <div className="mapping-fields" key={i}>
                              <label>
                                窗口名称
                                <input
                                  value={m.label}
                                  onChange={(e) =>
                                    patchAccount(a.id, {
                                      mappings: a.mappings.map((v, j) =>
                                        j === i
                                          ? { ...v, label: e.target.value }
                                          : v,
                                      ),
                                    })
                                  }
                                />
                              </label>
                              <label>
                                百分比字段（JSON Pointer）
                                <input
                                  value={m.pointer}
                                  onChange={(e) =>
                                    patchAccount(a.id, {
                                      mappings: a.mappings.map((v, j) =>
                                        j === i
                                          ? { ...v, pointer: e.target.value }
                                          : v,
                                      ),
                                    })
                                  }
                                />
                              </label>
                              <label>
                                <input
                                  type="checkbox"
                                  checked={m.usedPercent}
                                  onChange={(e) =>
                                    patchAccount(a.id, {
                                      mappings: a.mappings.map((v, j) =>
                                        j === i
                                          ? {
                                              ...v,
                                              usedPercent: e.target.checked,
                                            }
                                          : v,
                                      ),
                                    })
                                  }
                                />{" "}
                                来源数值表示已用比例
                              </label>
                              <button
                                className="text-button"
                                disabled={a.mappings.length === 1}
                                onClick={() =>
                                  patchAccount(a.id, {
                                    mappings: a.mappings.filter(
                                      (_, j) => j !== i,
                                    ),
                                  })
                                }
                              >
                                移除此窗口
                              </button>
                            </div>
                          ))}
                          <button
                            className="text-button"
                            disabled={a.mappings.length >= 8}
                            onClick={() =>
                              patchAccount(a.id, {
                                mappings: [
                                  ...a.mappings,
                                  {
                                    label: "新窗口",
                                    pointer: "/remainingPercent",
                                    usedPercent: false,
                                  },
                                ],
                              })
                            }
                          >
                            添加额度窗口
                          </button>
                        </>
                      )}
                      {a.provider === "codex" ? (
                        <p className="hint">
                          使用 PATH 中的 Codex CLI 官方登录。仅请求
                          account/rateLimits/read，不创建会话或执行模型任务。
                        </p>
                      ) : (
                        <>
                          <label>
                            API Key
                            <input
                              type="password"
                              autoComplete="new-password"
                              value={tokens[a.id] ?? ""}
                              onChange={(e) =>
                                setTokens((t) => ({
                                  ...t,
                                  [a.id]: e.target.value,
                                }))
                              }
                              placeholder="留空不会覆盖已保存密钥"
                            />
                          </label>
                          <div className="button-row">
                            <button
                              className="secondary"
                              disabled={
                                !native || dirty || busy || !tokens[a.id]
                              }
                              onClick={() =>
                                void run(async () => {
                                  const token = tokens[a.id];
                                  setTokens((t) => ({ ...t, [a.id]: "" }));
                                  await invoke("save_quota_key", {
                                    accountId: a.id,
                                    token,
                                  });
                                  setNotice("密钥已保存到本机系统凭据库");
                                })
                              }
                            >
                              <ShieldCheck size={16} aria-hidden="true" />
                              保存密钥
                            </button>
                            <button
                              className="text-button"
                              disabled={!native || dirty || busy}
                              onClick={() =>
                                void run(async () => {
                                  await invoke("clear_quota_key", {
                                    accountId: a.id,
                                  });
                                  setNotice("该账户的本机密钥已清除");
                                  setResults((r) => {
                                    const n = { ...r };
                                    delete n[a.id];
                                    return n;
                                  });
                                })
                              }
                            >
                              清除密钥
                            </button>
                          </div>
                        </>
                      )}
                      <button
                        className="text-button"
                        disabled={busy}
                        onClick={() => {
                          setConfig((c) => ({
                            ...c,
                            accounts: c.accounts.filter((v) => v.id !== a.id),
                          }));
                          setTokens((t) => {
                            const n = { ...t };
                            delete n[a.id];
                            return n;
                          });
                        }}
                      >
                        <Trash2 size={16} aria-hidden="true" />
                        移除卡片（密钥请先单独清除）
                      </button>
                    </div>
                  </details>
                </article>
              );
            })}
          </div>
          <button
            className="text-button"
            disabled={config.accounts.length >= 16 || busy}
            onClick={() =>
              setConfig((c) => ({
                ...c,
                accounts: [
                  ...c.accounts,
                  newAccount("custom", crypto.randomUUID()),
                ],
              }))
            }
          >
            <Plus size={16} aria-hidden="true" />
            添加账户 / 自定义来源
          </button>
        </fieldset>
      </section>
      <section className="surface">
        <div className="section-heading">
          <h2>键盘信息卡片预览</h2>
          <span className="badge">未发送到设备</span>
        </div>
        <div className="display-preview-row">
          <canvas
            ref={cardCanvas}
            width={160}
            height={80}
            role="img"
            aria-label={`额度卡片预览：${account?.label ?? "无账户"}，剩余 ${percentage(quota?.remainingPercent)}`}
          />
          <div className="display-preview-controls">
            <label>
              预览账户
              <select
                value={account?.id ?? ""}
                onChange={(e) => {
                  setSelected(e.target.value);
                  setWindowIndex(0);
                }}
              >
                {config.accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              额度窗口
              <select
                value={visibleWindowIndex}
                onChange={(e) => setWindowIndex(Number(e.target.value))}
              >
                {result?.windows.map((w, i) => (
                  <option value={i} key={w.id}>
                    {w.label}
                  </option>
                ))}
              </select>
            </label>
            <p className="hint">
              实时卡片和双主机控制需要经过验证的新固件。动态刷新不复用持久图片写入；当前不会发送
              BLE 命令。
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}
