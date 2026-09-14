use crate::{
    settings::Provider,
    state::{Runtime, SpeechStatus},
};
use ahakey_cloud::{CloudConfig, CloudEvent, CloudSession};
use ahakey_speech::{MicrophoneCapture, SessionConfig, SpeechEvent, SpeechSession};
use std::{
    sync::{atomic::Ordering, Arc, Mutex},
    time::Duration,
};
use tauri::{Emitter, Manager};
use tokio::sync::mpsc;
pub enum Active {
    Local(SpeechSession),
    Cloud {
        session: Arc<CloudSession>,
        capture: Option<MicrophoneCapture>,
        pending: Arc<Mutex<Vec<i16>>>,
    },
    External {
        wechat: bool,
    },
}
impl Active {
    fn cancel(&mut self) {
        match self {
            Self::Local(s) => s.cancel(),
            Self::Cloud {
                session, capture, ..
            } => {
                if let Some(mut c) = capture.take() {
                    c.stop()
                }
                session.cancel()
            }
            Self::External { wechat } => {
                let _ = crate::platform::external_toggle(*wechat);
            }
        }
    }
}

fn take_external(slot: &mut Option<Active>) -> Option<bool> {
    if let Some(Active::External { wechat }) = slot.as_ref() {
        let wechat = *wechat;
        slot.take();
        Some(wechat)
    } else {
        None
    }
}
enum Update {
    Phase(&'static str, &'static str),
    Partial(String),
    Final(String),
    Error(String),
    Cancel,
}
fn post(tx: &mpsc::Sender<Update>, event: Update) {
    match event {
        Update::Partial(_) | Update::Phase(_, _) => {
            let _ = tx.try_send(event);
        }
        _ => {
            let sender = tx.clone();
            tauri::async_runtime::spawn(async move {
                let _ = sender.send(event).await;
            });
        }
    }
}
pub async fn cancel(app: &tauri::AppHandle) {
    let state = app.state::<Runtime>();
    let _gate = state.voice_gate.lock().await;
    cancel_locked(app);
}
fn cancel_locked(app: &tauri::AppHandle) {
    let state = app.state::<Runtime>();
    state.generation.fetch_add(1, Ordering::SeqCst);
    state.recording.store(false, Ordering::SeqCst);
    let active = state.voice.lock().unwrap().take();
    if let Some(mut active) = active {
        active.cancel();
    }
    *state.speech.lock().unwrap() = SpeechStatus {
        phase: "idle".into(),
        message: "语音已取消".into(),
        recording: false,
    };
    let _ = crate::backend::display_caption(app, "idle", "", false);
}
pub async fn start(
    app: tauri::AppHandle,
    target: Option<usize>,
    key_epoch: Option<u64>,
    press_sequence: Option<u64>,
) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let _gate = state.voice_gate.lock().await;
    if state.closing.load(Ordering::SeqCst)
        || key_epoch.is_some_and(|e| {
            e != state.key_epoch.load(Ordering::SeqCst) || !state.key_enabled.load(Ordering::SeqCst)
        })
        || press_sequence.is_some_and(|seq| seq != state.key_sequence.load(Ordering::SeqCst))
    {
        return Ok(());
    }
    if state.recording.load(Ordering::SeqCst) {
        return Ok(());
    }
    if state.speech.lock().unwrap().phase == "transcribing" {
        return Err("上一句仍在识别，请稍候".into());
    }
    cancel_locked(&app);
    let settings = state.settings.lock().unwrap().clone();
    if settings.provider == Provider::Local && !state.model_store().is_installed() {
        return Err("请先在设置中下载或导入 SenseVoice 模型".into());
    }
    let external = matches!(
        settings.provider,
        Provider::Wechat | Provider::WindowsNative
    );
    if external && target.is_none() {
        return Err("请先把光标放到目标输入框，再按键盘语音键使用微信或 Win+H".into());
    }
    if external {
        // External input methods own their recording UI and lifetime. Do not
        // create an ASR event task, caption placement or a blind timeout toggle.
        if state.closing.load(Ordering::SeqCst)
            || key_epoch.is_some_and(|e| {
                e != state.key_epoch.load(Ordering::SeqCst)
                    || !state.key_enabled.load(Ordering::SeqCst)
            })
            || press_sequence.is_some_and(|seq| seq != state.key_sequence.load(Ordering::SeqCst))
        {
            return Ok(());
        }
        let wechat = settings.provider == Provider::Wechat;
        let result = crate::platform::external_toggle(wechat);
        if result.is_ok() {
            *state.voice.lock().unwrap() = Some(Active::External { wechat });
            state.recording.store(true, Ordering::SeqCst);
        }
        *state.speech.lock().unwrap() = SpeechStatus {
            phase: if result.is_ok() { "listening" } else { "error" }.into(),
            message: result
                .as_ref()
                .err()
                .cloned()
                .unwrap_or_else(|| "已发送外部语音启动快捷键；输入法状态未回读".into()),
            recording: result.is_ok(),
        };
        let _ = app.emit("runtime-update", ());
        return result;
    }
    let id = state.generation.fetch_add(1, Ordering::SeqCst) + 1;
    let (tx, mut rx) = mpsc::channel(16);
    let target_app = app.clone();
    let insert = settings.auto_insert;
    tauri::async_runtime::spawn(async move {
        while let Some(update) = rx.recv().await {
            let state = target_app.state::<Runtime>();
            let _gate = state.voice_gate.lock().await;
            if state.generation.load(Ordering::SeqCst) != id {
                break;
            }
            match update {
                Update::Phase(phase, message) => {
                    if phase == "listening" && !state.recording.load(Ordering::SeqCst) {
                        continue;
                    }
                    *state.speech.lock().unwrap() = SpeechStatus {
                        phase: phase.into(),
                        message: message.into(),
                        recording: state.recording.load(Ordering::SeqCst),
                    };
                    let _ = crate::backend::display_caption(&target_app, phase, message, false);
                }
                Update::Partial(text) => {
                    if !state.recording.load(Ordering::SeqCst) {
                        continue;
                    }
                    let _ = crate::backend::display_caption(&target_app, "listening", &text, false);
                }
                Update::Final(text) => {
                    state.recording.store(false, Ordering::SeqCst);
                    let mut message = "识别完成".to_string();
                    if insert
                        && !text.trim().is_empty()
                        && state.generation.load(Ordering::SeqCst) == id
                    {
                        if let Err(e) = crate::platform::insert(target, &text) {
                            message = e;
                        }
                    }
                    *state.speech.lock().unwrap() = SpeechStatus {
                        phase: "final".into(),
                        message,
                        recording: false,
                    };
                    let _ = crate::backend::display_caption(&target_app, "final", &text, true);
                    state.voice.lock().unwrap().take();
                    break;
                }
                Update::Error(error) => {
                    state.recording.store(false, Ordering::SeqCst);
                    *state.speech.lock().unwrap() = SpeechStatus {
                        phase: "error".into(),
                        message: error.clone(),
                        recording: false,
                    };
                    let _ = crate::backend::display_caption(&target_app, "error", &error, true);
                    let active = state.voice.lock().unwrap().take();
                    if let Some(mut a) = active {
                        a.cancel();
                    }
                    break;
                }
                Update::Cancel => break,
            }
            let _ = target_app.emit("runtime-update", ());
        }
        let _ = target_app.emit("runtime-update", ());
    });
    // Caption placement uses the same captured target as text insertion.
    // Manual UI recording has no insertion target, so preview on the main window.
    let caption_target = target.or_else(|| {
        #[cfg(windows)]
        {
            app.get_webview_window("main")
                .and_then(|w| w.hwnd().ok())
                .map(|h| h.0 as usize)
        }
        #[cfg(not(windows))]
        {
            None
        }
    });
    *state.caption_target.lock().unwrap() = caption_target;
    crate::backend::position_caption(&app, settings.caption_bottom_offset)?;
    state.recording.store(true, Ordering::SeqCst);
    *state.speech.lock().unwrap() = SpeechStatus {
        phase: "listening".into(),
        message: "正在录音".into(),
        recording: true,
    };
    let active = match settings.provider {
        Provider::Local => {
            let mut config = SessionConfig::new(state.model_store().directory().to_path_buf());
            config.device_name = settings.microphone;
            let events = tx.clone();
            SpeechSession::start(config, move |event| {
                let update = match event {
                    SpeechEvent::Loading => Update::Phase("listening", "正在录音 · 准备本地引擎"),
                    SpeechEvent::Recording => Update::Phase("listening", "正在聆听…"),
                    SpeechEvent::Partial(t) => Update::Partial(t),
                    SpeechEvent::Recognizing => Update::Phase("transcribing", "正在完成识别…"),
                    SpeechEvent::Final(t) => Update::Final(t),
                    SpeechEvent::Error(e) => Update::Error(e),
                    SpeechEvent::Cancelled => Update::Cancel,
                };
                post(&events, update);
            })
            .map(Active::Local)
            .map_err(|e| e.to_string())
        }
        Provider::Doubao => {
            let result = (|| -> Result<Active, String> {
                let token = state.credentials().load().map_err(|e| e.to_string())?;
                let config = CloudConfig {
                    app_id: settings.cloud_app_id,
                    resource_id: settings.cloud_resource_id,
                };
                let events = tx.clone();
                let session = Arc::new(
                    CloudSession::start(config, token, move |event| {
                        post(
                            &events,
                            match event {
                                CloudEvent::Partial(t) => Update::Partial(t),
                                CloudEvent::Final(t) => Update::Final(t),
                                CloudEvent::Error(e) => Update::Error(e.to_string()),
                            },
                        );
                    })
                    .map_err(|e| e.to_string())?,
                );
                let pending = Arc::new(Mutex::new(Vec::<i16>::new()));
                let buffer = pending.clone();
                let cloud = session.clone();
                let errors = tx.clone();
                let capture_errors = tx.clone();
                let capture = MicrophoneCapture::start(
                    settings.microphone.as_deref(),
                    move |audio| {
                        let mut data = buffer.lock().unwrap();
                        data.extend(
                            audio
                                .iter()
                                .map(|s| (s.clamp(-1.0, 1.0) * 32767.0).round() as i16),
                        );
                        while data.len() >= 3200 {
                            let packet: Vec<i16> = data.drain(..3200).collect();
                            if let Err(error) = cloud.try_send_pcm16(&packet) {
                                post(&errors, Update::Error(error.to_string()));
                                break;
                            }
                        }
                    },
                    move |error| post(&capture_errors, Update::Error(error)),
                )
                .map_err(|e| e.to_string())?;
                Ok(Active::Cloud {
                    session,
                    capture: Some(capture),
                    pending,
                })
            })();
            result
        }
        Provider::Wechat | Provider::WindowsNative => unreachable!("handled before recorder setup"),
    };
    match active {
        Ok(mut active) => {
            if state.generation.load(Ordering::SeqCst) != id {
                active.cancel();
                return Ok(());
            }
            *state.voice.lock().unwrap() = Some(active);
        }
        Err(error) => {
            state.recording.store(false, Ordering::SeqCst);
            post(&tx, Update::Error(error.clone()));
            return Err(error);
        }
    }
    let _ = app.emit("runtime-update", ());
    let deadline = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(Duration::from_secs(120)).await;
        let state = deadline.state::<Runtime>();
        if state.generation.load(Ordering::SeqCst) == id && state.recording.load(Ordering::SeqCst) {
            let _ = finish_generation(deadline.clone(), Some(id)).await;
        }
    });
    Ok(())
}
pub async fn finish(app: tauri::AppHandle) -> Result<(), String> {
    finish_generation(app, None).await
}
async fn finish_generation(app: tauri::AppHandle, expected: Option<u64>) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let _gate = state.voice_gate.lock().await;
    if expected.is_some_and(|id| state.generation.load(Ordering::SeqCst) != id) {
        return Ok(());
    }
    if !state.recording.swap(false, Ordering::SeqCst) {
        return Ok(());
    }
    // Consume ownership BEFORE sending the stop toggle. If SendInput fails or
    // only partly succeeds, generic cleanup must never send a second toggle.
    let external = take_external(&mut state.voice.lock().unwrap());
    if let Some(wechat) = external {
        let result = crate::platform::external_toggle(wechat);
        if result.is_err() {
            crate::backend::invalidate_keys(&app);
        }
        *state.speech.lock().unwrap() = SpeechStatus {
            phase: if result.is_ok() { "idle" } else { "error" }.into(),
            message: if result.is_ok() {
                "已发送外部语音结束快捷键".into()
            } else {
                "结束快捷键未确认，请在输入法浮窗手动结束后再使用；不会自动重试开关".into()
            },
            recording: false,
        };
        let _ = app.emit("runtime-update", ());
        return result;
    }
    let result = (|| -> Result<Option<Arc<CloudSession>>, String> {
        let mut active = state.voice.lock().unwrap();
        match active.as_mut() {
            Some(Active::Local(s)) => {
                s.finish();
                Ok(None)
            }
            Some(Active::Cloud {
                session,
                capture,
                pending,
            }) => {
                if let Some(mut c) = capture.take() {
                    c.stop()
                }
                let tail = std::mem::take(&mut *pending.lock().unwrap());
                if !tail.is_empty() {
                    session.try_send_pcm16(&tail).map_err(|e| e.to_string())?;
                }
                Ok(Some(session.clone()))
            }
            Some(Active::External { .. }) => unreachable!("external session was consumed above"),
            None => Ok(None),
        }
    })();
    let cloud = match result {
        Ok(c) => c,
        Err(error) => {
            cancel_locked(&app);
            *state.speech.lock().unwrap() = SpeechStatus {
                phase: "error".into(),
                message: error.clone(),
                recording: false,
            };
            let _ = app.emit("runtime-update", ());
            return Err(error);
        }
    };
    if state.voice.lock().unwrap().is_none() {
        return Ok(());
    }
    *state.speech.lock().unwrap() = SpeechStatus {
        phase: "transcribing".into(),
        message: "正在完成识别…".into(),
        recording: false,
    };
    let _ = app.emit("runtime-update", ());
    if let Some(cloud) = cloud {
        if let Err(e) = cloud.finish().await {
            cancel_locked(&app);
            let error = e.to_string();
            *state.speech.lock().unwrap() = SpeechStatus {
                phase: "error".into(),
                message: error.clone(),
                recording: false,
            };
            let _ = app.emit("runtime-update", ());
            return Err(error);
        }
    }
    Ok(())
}

#[cfg(test)]
mod external_tests {
    use super::*;
    #[test]
    fn failed_stop_cannot_leave_an_external_session_for_cleanup_to_toggle_again() {
        let mut slot = Some(Active::External { wechat: true });
        assert_eq!(take_external(&mut slot), Some(true));
        // A failed send does not put the consumed toggle session back.
        assert!(slot.is_none());
        assert_eq!(take_external(&mut slot), None);
    }
}
