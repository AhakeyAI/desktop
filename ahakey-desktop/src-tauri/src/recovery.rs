//! One connection supervisor, with explicit user intent separate from link state.
use crate::{backend, platform, settings, state::Runtime};
use ahakey_ble::{BleClient, ConnectionPhase};
use serde::Serialize;
use std::{
    sync::{atomic::Ordering, Arc},
    time::{Duration, Instant},
};
use tauri::Manager;

#[derive(Clone)]
struct Ticket {
    epoch: u64,
    id: String,
}

pub struct Recovery {
    target: Option<String>,
    epoch: u64,
    attempt: u32,
    in_flight: bool,
    next_at: Instant,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    enabled: bool,
    connecting: bool,
    attempt: u32,
    retry_after_seconds: u64,
}

impl Recovery {
    pub fn new(target: Option<String>) -> Self {
        Self {
            target,
            epoch: 0,
            attempt: 0,
            in_flight: false,
            next_at: Instant::now(),
        }
    }
    fn select(&mut self, id: String, now: Instant) {
        self.epoch += 1;
        self.target = Some(id);
        self.attempt = 0;
        self.in_flight = false;
        self.next_at = now;
    }
    pub fn pause(&mut self) {
        self.epoch += 1;
        self.target = None;
        self.in_flight = false;
        self.attempt = 0;
    }
    fn valid(&self, ticket: &Ticket) -> bool {
        self.epoch == ticket.epoch && self.target.as_ref() == Some(&ticket.id)
    }
    fn begin(&mut self, now: Instant) -> Option<Ticket> {
        if self.in_flight || now < self.next_at {
            return None;
        }
        let id = self.target.clone()?;
        self.in_flight = true;
        self.attempt = self.attempt.saturating_add(1);
        Some(Ticket {
            epoch: self.epoch,
            id,
        })
    }
    fn complete(&mut self, ticket: &Ticket, ready: bool, now: Instant) {
        if !self.valid(ticket) {
            return;
        }
        self.in_flight = false;
        if ready {
            self.attempt = 0;
        }
        self.next_at = now
            + if ready {
                Duration::ZERO
            } else {
                backoff(self.attempt)
            };
    }
    pub fn status(&self) -> Status {
        Status {
            enabled: self.target.is_some(),
            connecting: self.in_flight,
            attempt: self.attempt,
            retry_after_seconds: self
                .next_at
                .saturating_duration_since(Instant::now())
                .as_secs()
                .saturating_add(1),
        }
    }
}

fn backoff(attempt: u32) -> Duration {
    Duration::from_secs((1u64 << attempt.min(5)).min(30))
}

fn current(app: &tauri::AppHandle, ticket: &Ticket) -> bool {
    let state = app.state::<Runtime>();
    !state.closing.load(Ordering::SeqCst) && state.ble_recovery.lock().unwrap().valid(ticket)
}

// Caller owns ble_connection_gate. Do not hold any standard mutex over await.
async fn attempt(app: &tauri::AppHandle, ticket: &Ticket) -> Result<(), String> {
    if !current(app, ticket) {
        return Err("连接请求已取消".into());
    }
    if platform::java_running() {
        return Err("JavaFX AhaKey 仍在运行，请退出后自动重连".into());
    }
    let state = app.state::<Runtime>();
    let client = backend::ble_client(app).await?;
    let generation = {
        let policy = state.ble_recovery.lock().unwrap();
        if !policy.valid(ticket) || state.closing.load(Ordering::SeqCst) {
            return Err("连接请求已取消".into());
        }
        client.status().generation
    };
    client
        .reconnect_once_if(&ticket.id, generation)
        .await
        .map_err(|e| e.to_string())?;
    {
        let _settings_gate = state.settings_gate.lock().await;
        let policy = state.ble_recovery.lock().unwrap();
        if !policy.valid(ticket) || state.closing.load(Ordering::SeqCst) {
            return Err("连接请求已取消".into());
        }
        let mut saved = state.settings.lock().unwrap();
        if saved.saved_device.as_ref() != Some(&ticket.id) {
            let mut next = saved.clone();
            next.saved_device = Some(ticket.id.clone());
            settings::save(&state.settings_path, &next)?;
            *saved = next;
        }
    }
    backend::restore_device_preferences(app, &client).await;
    if !current(app, ticket) {
        return Err("连接请求已取消".into());
    }
    if client.status().phase != ConnectionPhase::Ready {
        return Err("设备在恢复设置时断开，将自动重试".into());
    }
    Ok(())
}

fn finish(app: &tauri::AppHandle, ticket: &Ticket, result: &Result<(), String>) {
    let state = app.state::<Runtime>();
    {
        let mut policy = state.ble_recovery.lock().unwrap();
        if state.closing.load(Ordering::SeqCst) || !policy.valid(ticket) {
            return;
        }
        policy.complete(ticket, result.is_ok(), Instant::now());
        *state.ble_error.lock().unwrap() = result.as_ref().err().cloned();
    }
    backend::pulse(app);
}

/// Opt-in integration probe: release only our GATT session, keeping recovery
/// intent. This tests recovery plumbing, not actual firmware sleep or radio loss.
#[tauri::command]
pub async fn test_ble_link_loss(window: tauri::WebviewWindow) -> Result<(), String> {
    backend::require_main(&window)?;
    if std::env::var("AHAKEY_BLE_TEST").as_deref() != Ok("1") {
        return Err("BLE 故障模拟未启用".into());
    }
    let state = window.state::<Runtime>();
    let _gate = state.ble_connection_gate.lock().await;
    let client = state.ble.lock().await.clone().ok_or("蓝牙尚未初始化")?;
    if client.status().phase != ConnectionPhase::Ready {
        return Err("仅对已就绪设备运行测试".into());
    }
    client.disconnect().await.map_err(|e| e.to_string())?;
    backend::pulse(window.app_handle());
    Ok(())
}

/// Started exactly once at application setup, including when no device is saved.
pub fn start(app: &tauri::AppHandle) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(1));
        tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            tick.tick().await;
            let state = app.state::<Runtime>();
            if state.closing.load(Ordering::SeqCst) {
                break;
            }
            let Ok(_gate) = state.ble_connection_gate.try_lock() else {
                continue;
            };
            let link = state.ble.lock().await.as_ref().map(|c| c.status());
            if link.as_ref().is_some_and(|s| {
                matches!(
                    s.phase,
                    ConnectionPhase::Ready | ConnectionPhase::Connecting
                )
            }) {
                continue;
            }
            let ticket = state.ble_recovery.lock().unwrap().begin(Instant::now());
            if let Some(ticket) = ticket {
                backend::pulse(&app);
                let result = attempt(&app, &ticket).await;
                finish(&app, &ticket, &result);
            }
        }
    });
}

pub async fn connect(app: &tauri::AppHandle, id: String) -> Result<(), String> {
    let client = backend::ble_client(app).await?;
    let state = app.state::<Runtime>();
    let ticket = {
        let mut policy = state.ble_recovery.lock().unwrap();
        policy.select(id, Instant::now());
        client.cancel_pending();
        policy
            .begin(Instant::now())
            .expect("new explicit intent is immediately eligible")
    };
    backend::pulse(app);
    let _gate = state.ble_connection_gate.lock().await;
    let result = attempt(app, &ticket).await;
    finish(app, &ticket, &result);
    result
}

pub async fn disconnect(app: &tauri::AppHandle) -> Result<(), String> {
    let state = app.state::<Runtime>();
    let client: Option<Arc<BleClient>> = state.ble.lock().await.clone();
    let epoch = {
        let mut policy = state.ble_recovery.lock().unwrap();
        policy.pause();
        if let Some(client) = &client {
            client.cancel_pending();
        }
        policy.epoch
    };
    backend::pulse(app);
    let _gate = state.ble_connection_gate.lock().await;
    if state.ble_recovery.lock().unwrap().epoch != epoch {
        return Ok(());
    }
    if let Some(client) = client {
        client.disconnect().await.map_err(|e| e.to_string())?;
    }
    *state.ble_error.lock().unwrap() = None;
    *state.settings_notice.lock().unwrap() =
        "已手动断开，本次运行暂停自动重连；点击连接可恢复".into();
    backend::pulse(app);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sleep_failure_retries_until_awake_and_resets_backoff() {
        let now = Instant::now();
        let mut p = Recovery::new(None);
        p.select("keyboard".into(), now);
        for (i, delay) in [2, 4, 8, 16, 30, 30].into_iter().enumerate() {
            let t = p.begin(p.next_at).unwrap();
            assert_eq!(p.attempt, i as u32 + 1);
            assert!(p.begin(p.next_at).is_none());
            p.complete(&t, false, now);
            assert_eq!(p.next_at.duration_since(now), Duration::from_secs(delay));
            assert!(p.begin(p.next_at - Duration::from_millis(1)).is_none());
        }
        let t = p.begin(p.next_at).unwrap();
        p.complete(&t, true, now);
        assert_eq!(p.attempt, 0);
        // A later sleep is immediately eligible, without an old 30-second penalty.
        assert!(p.begin(now).is_some());
    }
    #[test]
    fn manual_disconnect_and_shutdown_invalidate_pending_success() {
        let now = Instant::now();
        let mut p = Recovery::new(Some("a".into()));
        let old = p.begin(now + Duration::from_secs(1)).unwrap();
        p.pause();
        p.complete(&old, true, now);
        assert!(!p.valid(&old));
        assert!(p.begin(now + Duration::from_secs(3600)).is_none());
        assert!(!p.status().enabled);
    }
    #[test]
    fn switching_device_rejects_old_completion_and_no_saved_device_stays_idle() {
        let now = Instant::now();
        let mut p = Recovery::new(None);
        assert!(p.begin(now).is_none());
        p.select("a".into(), now);
        let old = p.begin(now).unwrap();
        p.select("b".into(), now);
        let next = p.begin(now).unwrap();
        p.complete(&old, false, now);
        assert!(p.in_flight);
        assert!(p.valid(&next));
        assert_eq!(p.attempt, 1);
    }
}
