import { useState } from "react";
import { Check, Cloud, Cpu, Download, MessageCircle, Monitor, Sparkles, XCircle } from "lucide-react";
import { CleanupMode, Provider, Settings, Snapshot, SpeechEngine, WhisperSize } from "./contracts";

export interface ProviderPickerProps {
  value: Provider;
  onChange: (provider: Provider) => void;
  windows: boolean;
  draft?: Settings;
  patch?: (partial: Partial<Settings>) => void;
  snapshot?: Snapshot | null;
  onPrepareModel?: () => void;
  onCancelModel?: () => void;
}

export function ProviderPicker({
  value,
  onChange,
  windows,
  draft,
  patch,
  snapshot,
  onPrepareModel,
  onCancelModel,
}: ProviderPickerProps) {
  const [showKey, setShowKey] = useState(false);

  const localDetail = draft
    ? draft.speechEngine === "whisper"
      ? `Whisper (${draft.whisperSize}) · 离线`
      : "SenseVoice · 离线"
    : "SenseVoice · 离线";

  const choices = [
    { id: "wechat" as const, label: "微信输入法", detail: "输入法语音", icon: MessageCircle, windows: true },
    { id: "windows-native" as const, label: "Windows 听写", detail: "Win + H", icon: Monitor, windows: true },
    { id: "local" as const, label: "本地模型", detail: localDetail, icon: Cpu, windows: false },
    { id: "doubao" as const, label: "豆包云端", detail: "API · 流式识别", icon: Cloud, windows: false },
  ].filter(choice => windows || !choice.windows);

  return (
    <div className="provider-container">
      <div className="provider-switcher" role="group" aria-label="语音识别渠道">
        {choices.map(({ id, label, detail, icon: Icon }) => (
          <button
            key={id}
            className={`provider-option ${id === value ? "selected" : ""}`}
            aria-pressed={id === value}
            onClick={() => onChange(id)}
          >
            <span className="provider-option-top">
              <Icon size={20} aria-hidden="true" />
              {id === value && <Check size={15} aria-hidden="true" />}
            </span>
            <strong>{label}</strong>
            <span>{detail}</span>
          </button>
        ))}
      </div>

      {value === "local" && draft && patch && (
        <div className="local-model-options surface" style={{ marginTop: "1rem" }}>
          <div className="section-heading">
            <h3><Cpu size={18} aria-hidden="true" /> 本地引擎设置</h3>
            <span>离线模型与文本整理</span>
          </div>

          <div className="two-columns" style={{ marginTop: "0.5rem" }}>
            <label>
              离线语音识别引擎
              <select
                aria-label="选择识别引擎"
                value={draft.speechEngine}
                onChange={e => patch({ speechEngine: e.target.value as SpeechEngine })}
              >
                <option value="sense-voice">SenseVoice (推荐 · 中粤英日韩)</option>
                <option value="whisper">Whisper (OpenAI 多语言)</option>
              </select>
            </label>

            {draft.speechEngine === "whisper" ? (
              <label>
                Whisper 模型尺寸
                <select
                  aria-label="选择 Whisper 尺寸"
                  value={draft.whisperSize}
                  onChange={e => patch({ whisperSize: e.target.value as WhisperSize })}
                >
                  <option value="tiny">Tiny (轻量 · 约 100 MB)</option>
                  <option value="base">Base (推荐 · 约 160 MB)</option>
                  <option value="small">Small (高精度 · 约 375 MB)</option>
                  <option value="turbo">Turbo (Large V3 Turbo · 约 1 GB)</option>
                </select>
              </label>
            ) : (
              <div className="hint" style={{ alignSelf: "center", paddingTop: "1rem" }}>
                阿里开源多语言语音大模型，自带情绪及富文本标点检测。
              </div>
            )}
          </div>

          <label className="setting-row" style={{ marginTop: "0.5rem" }}>
            <span>启动时自动在后台下载选中的模型权重</span>
            <input
              type="checkbox"
              checked={draft.autoDownloadModel}
              onChange={e => patch({ autoDownloadModel: e.target.checked })}
            />
          </label>
          <p className="hint">
            开启后若当前所选模型未安装，应用启动时将自动在后台安全下载并校验 SHA256。关闭则仅在手动点击时下载。
          </p>

          {snapshot && (
            <div className="model-status-card" style={{ marginTop: "0.75rem", padding: "0.75rem", background: "var(--card-bg, rgba(0,0,0,0.03))", borderRadius: "8px" }}>
              <div className="setting-row">
                <div>
                  <strong>当前模型状态</strong>
                  <p className="hint" style={{ margin: 0 }}>{snapshot.modelDirectory}</p>
                </div>
                <span>
                  {snapshot.download.busy ? (
                    "正在下载 / 导入…"
                  ) : snapshot.modelInstalled ? (
                    <span style={{ color: "var(--success-color, #10b981)", fontWeight: 600 }}>模型已安装</span>
                  ) : (
                    <span style={{ color: "var(--warning-color, #f59e0b)" }}>未安装权重</span>
                  )}
                </span>
              </div>

              {snapshot.download.busy && (
                <div style={{ marginTop: "0.5rem" }}>
                  <progress aria-label="模型准备进度" max="1" value={snapshot.download.progress} style={{ width: "100%" }} />
                  <div className="button-row" style={{ marginTop: "0.25rem", justifyContent: "space-between" }}>
                    <span className="hint" role="status">{snapshot.download.message}</span>
                    {onCancelModel && (
                      <button className="text-button" onClick={onCancelModel}>
                        <XCircle size={14} aria-hidden="true" /> 取消下载
                      </button>
                    )}
                  </div>
                </div>
              )}

              {!snapshot.download.busy && !snapshot.modelInstalled && onPrepareModel && (
                <div className="button-row" style={{ marginTop: "0.5rem" }}>
                  <button className="secondary" onClick={onPrepareModel}>
                    <Download size={16} aria-hidden="true" /> 立即下载并校验权重
                  </button>
                </div>
              )}
            </div>
          )}

          <div style={{ marginTop: "1rem", paddingTop: "0.75rem", borderTop: "1px solid var(--border-color, rgba(0,0,0,0.08))" }}>
            <div className="section-heading">
              <h4><Sparkles size={16} aria-hidden="true" /> 大模型文本整理</h4>
              <span>修正标点、移除口癖</span>
            </div>

            <div className="setting-row">
              <label style={{ width: "100%" }}>
                整理模式
                <select
                  aria-label="选择整理模式"
                  value={draft.cleanupMode}
                  onChange={e => patch({ cleanupMode: e.target.value as CleanupMode })}
                >
                  <option value="off">关闭 (输出原始语音识别结果)</option>
                  <option value="local">本地大模型 (Ollama / 本地 OpenAI 兼容接口)</option>
                </select>
              </label>
            </div>

            {draft.cleanupMode === "local" && (
              <div className="local-llm-fields" style={{ marginTop: "0.5rem" }}>
                <div className="two-columns">
                  <label>
                    服务地址 (Base URL)
                    <input
                      type="text"
                      value={draft.cleanupBaseUrl}
                      onChange={e => patch({ cleanupBaseUrl: e.target.value })}
                      placeholder="http://localhost:11434"
                    />
                  </label>
                  <label>
                    模型名称 (Model)
                    <input
                      type="text"
                      value={draft.cleanupModel}
                      onChange={e => patch({ cleanupModel: e.target.value })}
                      placeholder="qwen2.5:3b"
                    />
                  </label>
                </div>

                <label style={{ marginTop: "0.5rem" }}>
                  API 密钥 (可选，本地 Ollama 通常无需填写)
                  <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
                    <input
                      type={showKey ? "text" : "password"}
                      value={draft.cleanupApiKey ?? ""}
                      onChange={e => patch({ cleanupApiKey: e.target.value || null })}
                      placeholder="sk-..."
                      style={{ flex: 1 }}
                    />
                    <button
                      type="button"
                      className="text-button"
                      onClick={() => setShowKey(!showKey)}
                      style={{ whiteSpace: "nowrap" }}
                    >
                      {showKey ? "隐藏" : "显示"}
                    </button>
                  </div>
                </label>
                <p className="hint">
                  转写完成后通过本地大模型修正标点及口癖。任何网络失败或超时 (30s) 将自动回退为原始转写结果。
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
