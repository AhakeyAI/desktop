//! In-process native GATT transport: WinRT on Windows, CoreBluetooth on macOS,
//! and BlueZ on Linux (provided by btleplug). No helper executable or TCP bridge.
pub mod protocol;
pub mod routing;
#[cfg(windows)]
pub mod usb_routing;
#[cfg(not(windows))]
use btleplug::platform::Peripheral;
use btleplug::{
    api::{
        Central, CharPropFlags, Characteristic, Manager as _, Peripheral as _, ScanFilter,
        WriteType,
    },
    platform::{Adapter, Manager},
};
#[cfg(windows)]
mod native_windows;
#[cfg(not(windows))]
use btleplug::api::RetrievePeripheralsOptions;
use futures::StreamExt;
#[cfg(windows)]
use native_windows::Peripheral;
pub use protocol::{DeviceStatus, KeyConfig, ProfileConfig};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    future::Future,
    sync::{Arc, Mutex as StdMutex},
    time::Duration,
};
use tokio::{
    sync::{broadcast, Mutex},
    task::JoinHandle,
    time::{sleep, timeout},
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

pub type Result<T> = std::result::Result<T, BleError>;
#[derive(Debug, thiserror::Error)]
pub enum BleError {
    #[error("Bluetooth: {0}")]
    Native(String),
    #[error("Bluetooth operation timed out: {0}")]
    Timeout(&'static str),
    #[error("Bluetooth operation cancelled")]
    Cancelled,
    #[error("Device is not ready")]
    NotConnected,
    #[error("{0}")]
    Invalid(String),
}
impl From<btleplug::Error> for BleError {
    fn from(e: btleplug::Error) -> Self {
        Self::Native(e.to_string())
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ConnectionPhase {
    Disconnected,
    Connecting,
    Ready,
    Error,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub rssi: Option<i16>,
    pub is_candidate: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BleSnapshot {
    pub generation: u64,
    pub phase: ConnectionPhase,
    pub device: Option<DeviceInfo>,
    pub status: Option<DeviceStatus>,
    pub error: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "data", rename_all = "camelCase")]
pub enum BleEvent {
    State(BleSnapshot),
    Devices(Vec<DeviceInfo>),
}

struct Shared {
    state: StdMutex<BleSnapshot>,
    cancel: StdMutex<CancellationToken>,
    events: broadcast::Sender<BleEvent>,
}
impl Shared {
    fn publish(&self, generation: u64, update: impl FnOnce(&mut BleSnapshot)) {
        let mut state = self.state.lock().unwrap();
        if state.generation != generation {
            return;
        }
        update(&mut state);
        let _ = self.events.send(BleEvent::State(state.clone()));
    }
    fn next(&self) -> (u64, CancellationToken) {
        self.next_if(None).expect("unconditional generation")
    }
    fn next_if(&self, expected: Option<u64>) -> Result<(u64, CancellationToken)> {
        let mut old = self.cancel.lock().unwrap();
        let mut state = self.state.lock().unwrap();
        if expected.is_some_and(|expected| expected != state.generation) {
            return Err(BleError::Cancelled);
        }
        old.cancel();
        *old = CancellationToken::new();
        state.generation += 1;
        Ok((state.generation, old.clone()))
    }
}
struct Session {
    generation: u64,
    peripheral: Peripheral,
    command: Characteristic,
    notify: Characteristic,
    cancel: CancellationToken,
    worker: JoinHandle<()>,
    writes: Arc<Mutex<()>>,
    replies: broadcast::Sender<Vec<u8>>,
}
/// Keep this shared handle for the application's lifetime. Call disconnect on quit.
pub struct BleClient {
    adapters: Vec<Adapter>,
    shared: Arc<Shared>,
    session: Mutex<Option<Session>>,
    devices: StdMutex<HashMap<String, Peripheral>>,
}
impl Drop for BleClient {
    fn drop(&mut self) {
        self.shared.cancel.lock().unwrap().cancel();
    }
}

const OP_TIMEOUT: Duration = Duration::from_secs(10);
async fn operation<T>(
    cancel: &CancellationToken,
    label: &'static str,
    f: impl Future<Output = std::result::Result<T, btleplug::Error>>,
) -> Result<T> {
    tokio::select! { biased; _=cancel.cancelled()=>Err(BleError::Cancelled), r=timeout(OP_TIMEOUT,f)=>r.map_err(|_|BleError::Timeout(label))?.map_err(|e| {
        let detail = e.to_string();
        if detail.to_ascii_uppercase().contains("800704C7") {
            BleError::Native(format!("{label}: Windows 取消了蓝牙操作（0x800704C7），不一定是手动取消。请确认蓝牙已开启并唤醒键盘。"))
        } else { BleError::Native(format!("{label}: {detail}")) }
    }) }
}
fn characteristic_uuid(short: u16) -> Uuid {
    Uuid::from_u128(((short as u128) << 96) | 0x0000_1000_8000_0080_5f9b_34fb)
}
fn candidate_name(name: &str) -> bool {
    name.trim().to_ascii_lowercase().starts_with("ahakey")
}
async fn detach(session: Session) {
    session.cancel.cancel();
    let mut worker = session.worker;
    if timeout(Duration::from_secs(2), &mut worker).await.is_err() {
        worker.abort();
        let _ = worker.await;
    }
    let _ = timeout(
        Duration::from_secs(3),
        session.peripheral.unsubscribe(&session.notify),
    )
    .await;
    let _ = timeout(Duration::from_secs(3), session.peripheral.disconnect()).await;
}

impl BleClient {
    pub async fn new() -> Result<Arc<Self>> {
        let manager = timeout(OP_TIMEOUT, Manager::new())
            .await
            .map_err(|_| BleError::Timeout("create adapter manager"))??;
        let adapters = timeout(OP_TIMEOUT, manager.adapters())
            .await
            .map_err(|_| BleError::Timeout("list adapters"))??;
        if adapters.is_empty() {
            return Err(BleError::Native("No Bluetooth adapter is available".into()));
        }
        let (events, _) = broadcast::channel(64);
        Ok(Arc::new(Self {
            adapters,
            shared: Arc::new(Shared {
                state: StdMutex::new(BleSnapshot {
                    generation: 0,
                    phase: ConnectionPhase::Disconnected,
                    device: None,
                    status: None,
                    error: None,
                }),
                cancel: StdMutex::new(CancellationToken::new()),
                events,
            }),
            session: Mutex::new(None),
            devices: StdMutex::new(HashMap::new()),
        }))
    }
    pub fn subscribe(&self) -> broadcast::Receiver<BleEvent> {
        self.shared.events.subscribe()
    }
    pub fn status(&self) -> BleSnapshot {
        self.shared.state.lock().unwrap().clone()
    }

    /// Bounded discovery only. Advertising a matching name is not readiness proof.
    pub async fn scan(&self, duration: Duration) -> Result<Vec<DeviceInfo>> {
        let _gate = self.session.lock().await;
        let cancel = {
            let mut token = self.shared.cancel.lock().unwrap();
            if token.is_cancelled() {
                *token = CancellationToken::new();
            }
            token.clone()
        };
        let duration = duration.clamp(Duration::from_millis(100), Duration::from_secs(15));
        let mut discovered: Vec<DeviceInfo> = Vec::new();
        #[cfg(windows)]
        for peripheral in operation(
            &cancel,
            "list registered AhaKey devices",
            native_windows::registered(),
        )
        .await?
        {
            let properties = peripheral.properties().await?.unwrap_or_default();
            let id = peripheral.id();
            discovered.push(DeviceInfo {
                id: id.clone(),
                name: properties.local_name.unwrap_or_default(),
                rssi: None,
                is_candidate: true,
            });
            self.devices.lock().unwrap().insert(id, peripheral);
        }
        #[cfg(not(windows))]
        for adapter in &self.adapters {
            // Match the Windows "registered devices" semantics: peripherals that are
            // already paired or connected at the system level stop advertising, so
            // merge the backend's known-device source into bounded discovery.
            let known = operation(
                &cancel,
                "retrieve known peripherals",
                adapter.retrieve_peripherals(RetrievePeripheralsOptions {
                    identifiers: None,
                    services: Some(vec![
                        characteristic_uuid(0x7340),
                        characteristic_uuid(0x1812),
                    ]),
                }),
            )
            .await;
            let known = match known {
                Ok(known) => known,
                Err(BleError::Cancelled) => return Err(BleError::Cancelled),
                Err(_) => continue, // backend without a retrieval source: advertise-only
            };
            for peripheral in known {
                let Some(properties) =
                    operation(&cancel, "read known peripheral", peripheral.properties()).await?
                else {
                    continue;
                };
                let id = peripheral.id().to_string();
                let name = properties
                    .local_name
                    .unwrap_or_else(|| "Unnamed Bluetooth device".into());
                let is_candidate = candidate_name(&name)
                    || properties
                        .services
                        .iter()
                        .any(|u| *u == characteristic_uuid(0x7340));
                if !is_candidate || discovered.iter().any(|d| d.id == id) {
                    continue;
                }
                discovered.push(DeviceInfo {
                    id: id.clone(),
                    name,
                    rssi: properties.rssi,
                    is_candidate,
                });
                self.devices.lock().unwrap().insert(id, peripheral);
            }
        }
        for adapter in &self.adapters {
            operation(
                &cancel,
                "start scan",
                adapter.start_scan(ScanFilter::default()),
            )
            .await?;
            let cancelled = tokio::select! {_=cancel.cancelled()=>true,_=sleep(duration)=>false};
            let stop = timeout(OP_TIMEOUT, adapter.stop_scan()).await;
            if cancelled {
                return Err(BleError::Cancelled);
            }
            stop.map_err(|_| BleError::Timeout("stop scan"))??;
            for peripheral in operation(&cancel, "list peripherals", adapter.peripherals()).await? {
                let Some(properties) =
                    operation(&cancel, "read advertisement", peripheral.properties()).await?
                else {
                    continue;
                };
                let id = peripheral.id().to_string();
                let name = properties
                    .local_name
                    .unwrap_or_else(|| "Unnamed Bluetooth device".into());
                let is_candidate = candidate_name(&name)
                    || properties
                        .services
                        .iter()
                        .any(|u| *u == characteristic_uuid(0x7340));
                if !is_candidate {
                    continue;
                }
                if discovered.iter().any(|d| d.id == id) {
                    continue;
                }
                #[cfg(windows)]
                let peripheral = Peripheral::new(properties.address, name.clone(), properties.rssi);
                discovered.push(DeviceInfo {
                    id: id.clone(),
                    name,
                    rssi: properties.rssi,
                    is_candidate,
                });
                self.devices.lock().unwrap().insert(id, peripheral);
            }
        }
        discovered.sort_by(|a, b| {
            b.is_candidate
                .cmp(&a.is_candidate)
                .then_with(|| a.name.cmp(&b.name))
        });
        let _ = self
            .shared
            .events
            .send(BleEvent::Devices(discovered.clone()));
        Ok(discovered)
    }

    pub async fn connect(&self, id: &str) -> Result<()> {
        self.connect_if(id, None).await
    }
    async fn connect_if(&self, id: &str, expected: Option<u64>) -> Result<()> {
        let (generation, cancel) = self.shared.next_if(expected)?;
        let mut session = self.session.lock().await;
        if cancel.is_cancelled() {
            return Err(BleError::Cancelled);
        }
        if let Some(old) = session.take() {
            detach(old).await;
        }
        self.shared.publish(generation, |s| {
            s.phase = ConnectionPhase::Connecting;
            s.device = None;
            s.status = None;
            s.error = None;
        });
        let peripheral = self.devices.lock().unwrap().get(id).cloned();
        let Some(peripheral) = peripheral else {
            let error = BleError::Invalid(
                "Saved device not discovered; scan with the keyboard awake first".into(),
            );
            self.shared.publish(generation, |s| {
                s.phase = ConnectionPhase::Error;
                s.error = Some(error.to_string());
            });
            return Err(error);
        };
        let properties = match operation(&cancel, "read device", peripheral.properties()).await {
            Ok(properties) => properties,
            Err(error) => {
                self.shared.publish(generation, |s| {
                    s.phase = ConnectionPhase::Error;
                    s.error = Some(error.to_string());
                });
                return Err(error);
            }
        };
        let device = DeviceInfo {
            id: id.into(),
            name: properties
                .as_ref()
                .and_then(|p| p.local_name.clone())
                .unwrap_or_default(),
            rssi: properties.and_then(|p| p.rssi),
            is_candidate: true,
        };
        self.shared.publish(generation, |s| {
            s.phase = ConnectionPhase::Connecting;
            s.device = Some(device);
            s.status = None;
            s.error = None;
        });
        let result = self.attach(peripheral.clone(), generation, &cancel).await;
        match result {
            Ok(ready) => {
                *session = Some(ready);
                Ok(())
            }
            Err(error) => {
                cancel.cancel();
                let _ = timeout(Duration::from_secs(3), peripheral.disconnect()).await;
                self.shared.publish(generation, |s| {
                    s.phase = ConnectionPhase::Error;
                    s.status = None;
                    s.error = Some(error.to_string());
                });
                Err(error)
            }
        }
    }

    async fn attach(
        &self,
        peripheral: Peripheral,
        generation: u64,
        cancel: &CancellationToken,
    ) -> Result<Session> {
        operation(cancel, "connect", peripheral.connect()).await?;
        operation(cancel, "discover services", peripheral.discover_services()).await?;
        let chars = peripheral.characteristics();
        let find = |short| {
            chars
                .iter()
                .find(|c| c.uuid == characteristic_uuid(short))
                .cloned()
                .ok_or_else(|| {
                    BleError::Invalid(format!(
                        "Required AhaKey characteristic {short:04x} is missing"
                    ))
                })
        };
        let _data = find(0x7341)?;
        let command = find(0x7343)?;
        let notify = find(0x7344)?;
        if !command.properties.contains(CharPropFlags::WRITE) {
            return Err(BleError::Invalid(
                "7343 does not support acknowledged writes".into(),
            ));
        }
        if !notify
            .properties
            .intersects(CharPropFlags::NOTIFY | CharPropFlags::INDICATE)
        {
            return Err(BleError::Invalid(
                "7344 does not support notifications".into(),
            ));
        }
        let mut stream = operation(
            cancel,
            "create notification stream",
            peripheral.notifications(),
        )
        .await?;
        operation(
            cancel,
            "enable notifications",
            peripheral.subscribe(&notify),
        )
        .await?;
        operation(
            cancel,
            "query status",
            peripheral.write(&command, &protocol::QUERY_STATUS, WriteType::WithResponse),
        )
        .await?;
        let first = tokio::select! {biased;_=cancel.cancelled()=>Err(BleError::Cancelled), r=timeout(OP_TIMEOUT,async{
            while let Some(n)=stream.next().await{if n.uuid==notify.uuid{if let Some(s)=protocol::parse_status(&n.value){return Ok(s)}}}
            Err(BleError::Native("Notification stream closed before status response".into()))
        })=>r.map_err(|_|BleError::Timeout("await actual device status"))?}?;
        self.shared.publish(generation, |s| {
            s.phase = ConnectionPhase::Ready;
            s.status = Some(first);
            s.error = None;
        });
        let shared = self.shared.clone();
        let worker_cancel = cancel.clone();
        let worker_device = peripheral.clone();
        let notify_id = notify.uuid;
        let writes = Arc::new(Mutex::new(()));
        let worker_writes = writes.clone();
        let worker_command = command.clone();
        let (replies, _) = broadcast::channel(32);
        let worker_replies = replies.clone();
        let worker = tokio::spawn(async move {
            let mut check = tokio::time::interval(Duration::from_secs(3));
            let mut polls = 0;
            let mut last_status = tokio::time::Instant::now();
            let reason = loop {
                tokio::select! {biased;
                    _=worker_cancel.cancelled()=>break None,
                    n=stream.next()=>match n{Some(n)=>{if n.uuid==notify_id{let _=worker_replies.send(n.value.clone());if let Some(status)=protocol::parse_status(&n.value){last_status=tokio::time::Instant::now();shared.publish(generation,|s|s.status=Some(status));}}},None=>break Some("Device notification stream closed".to_owned())},
                    _=check.tick()=>{
                        if last_status.elapsed()>Duration::from_secs(45){break Some("Device stopped responding to status queries".into());}
                        match operation(&worker_cancel,"connection check",worker_device.is_connected()).await{Ok(true)=>{},Ok(false)=>break Some("Device disconnected".into()),Err(BleError::Cancelled)=>break None,Err(e)=>break Some(e.to_string())}
                        polls+=1;if polls%5==0 {
                            // try_lock avoids blocking notification consumption while a profile batch is writing.
                            if let Ok(_guard)=worker_writes.try_lock(){
                                match operation(&worker_cancel,"refresh status",worker_device.write(&worker_command,&protocol::QUERY_STATUS,WriteType::WithResponse)).await{Ok(())=>{},Err(BleError::Cancelled)=>break None,Err(e)=>break Some(e.to_string())}
                            }
                        }
                    }
                }
            };
            if let Some(reason) = reason {
                worker_cancel.cancel();
                shared.publish(generation, |s| {
                    s.phase = ConnectionPhase::Error;
                    s.status = None;
                    s.error = Some(reason)
                });
            }
        });
        Ok(Session {
            generation,
            peripheral,
            command,
            notify,
            cancel: cancel.clone(),
            worker,
            writes,
            replies,
        })
    }

    /// Invalidate in-flight work before waiting for the application's connection gate.
    /// A stale attempt must not connect after a manual disconnect or device switch.
    pub fn cancel_pending(&self) {
        self.shared.next();
    }

    /// One bounded attempt for the application's backoff supervisor. The generation
    /// is captured with user intent so a later disconnect also cancels queued work.
    pub async fn reconnect_once_if(&self, id: &str, generation: u64) -> Result<()> {
        if self.status().generation != generation {
            return Err(BleError::Cancelled);
        }
        self.scan(Duration::from_secs(3)).await?;
        self.connect_if(id, Some(generation)).await
    }

    /// Saved IDs are local OS identities. At most three attempts, with fresh scan.
    pub async fn reconnect(&self, id: &str) -> Result<()> {
        let mut generation = self.status().generation;
        self.scan(Duration::from_secs(3)).await?;
        let mut last = BleError::NotConnected;
        for attempt in 0..3 {
            match self.connect_if(id, Some(generation)).await {
                Ok(()) => return Ok(()),
                Err(BleError::Cancelled) => return Err(BleError::Cancelled),
                Err(e) => last = e,
            }
            // A failed attach cancels its worker token; generation is the external cancellation guard.
            generation += 1;
            if attempt < 2 {
                sleep(Duration::from_millis(400 * (attempt + 1))).await;
            }
            if self.status().generation != generation {
                return Err(BleError::Cancelled);
            }
        }
        Err(last)
    }
    pub async fn disconnect(&self) -> Result<()> {
        let (generation, _) = self.shared.next();
        let mut session = self.session.lock().await;
        if let Some(old) = session.take() {
            detach(old).await;
        }
        self.shared.publish(generation, |s| {
            s.phase = ConnectionPhase::Disconnected;
            s.device = None;
            s.status = None;
            s.error = None;
        });
        Ok(())
    }
    async fn write_batch(&self, frames: Vec<Vec<u8>>) -> Result<()> {
        let session = self.session.lock().await;
        let s = session.as_ref().ok_or(BleError::NotConnected)?;
        if self.status().phase != ConnectionPhase::Ready {
            return Err(BleError::NotConnected);
        }
        let _write_guard = s.writes.lock().await;
        for frame in frames {
            let result = operation(
                &s.cancel,
                "write command",
                s.peripheral
                    .write(&s.command, &frame, WriteType::WithResponse),
            )
            .await;
            if let Err(error) = result {
                // A live but inactive host may be denied configuration writes.
                // The connection supervisor owns link-loss detection; a command
                // rejection must not tear down a healthy secondary BLE link.
                return Err(error);
            }
            tokio::select! {biased;_=s.cancel.cancelled()=>return Err(BleError::Cancelled),_=sleep(Duration::from_millis(50))=>{}}
        }
        Ok(())
    }
    pub async fn query_status(&self) -> Result<()> {
        self.write_batch(vec![protocol::QUERY_STATUS.to_vec()])
            .await
    }
    async fn routing_request(
        &self,
        config: Option<&routing::Config>,
        generation: u64,
    ) -> Result<routing::Status> {
        use std::sync::atomic::{AtomicU16, Ordering};
        static NEXT_REQUEST: AtomicU16 = AtomicU16::new(1);
        let session = self.session.lock().await;
        let s = session.as_ref().ok_or(BleError::NotConnected)?;
        if generation != s.generation
            || self.status().phase != ConnectionPhase::Ready
            || self.status().generation != s.generation
        {
            return Err(BleError::NotConnected);
        }
        let _write_guard = s.writes.lock().await;
        let request = config.map(|_| NEXT_REQUEST.fetch_add(1, Ordering::Relaxed) & 0x3fff);
        let frame = match (config, request) {
            (Some(c), Some(id)) => c.frame(id)?,
            _ => routing::QUERY.to_vec(),
        };
        let mut replies = s.replies.subscribe();
        operation(
            &s.cancel,
            "routing command",
            s.peripheral
                .write(&s.command, &frame, WriteType::WithResponse),
        )
        .await?;
        let response = async {
            loop {
                let bytes = replies
                    .recv()
                    .await
                    .map_err(|e| BleError::Native(e.to_string()))?;
                if let Some(reply) = routing::parse(&bytes) {
                    if reply.request == request {
                        return routing::confirmed(reply, request, config);
                    }
                }
            }
        };
        tokio::select! { biased;
            _=s.cancel.cancelled()=>Err(BleError::Cancelled),
            result=timeout(Duration::from_secs(4),response)=>result.map_err(|_|BleError::Timeout("routing readback unavailable; firmware may not support it, no saved state confirmed"))?,
        }
    }
    pub async fn read_routing(&self) -> Result<routing::Status> {
        self.routing_request(None, self.status().generation).await
    }
    pub async fn set_routing(&self, config: &routing::Config) -> Result<routing::Status> {
        config.validate()?;
        // A fresh versioned readback is the capability gate. No legacy version guessing.
        let generation = self.status().generation;
        self.routing_request(None, generation).await?;
        self.routing_request(Some(config), generation).await
    }
    /// Completion means acknowledged GATT writes, not proof of persistent flash readback.
    pub async fn save_profiles(
        &self,
        profiles: &[ProfileConfig; 4],
        active_mode: u8,
        brightness: u8,
    ) -> Result<()> {
        self.write_batch(protocol::profile_frames(profiles, active_mode, brightness)?)
            .await
    }
    pub async fn save_keys(&self, mode: u8, keys: &[KeyConfig; 4]) -> Result<()> {
        self.write_batch(protocol::key_frames(mode, keys)?).await
    }
    pub async fn set_light_effect(&self, effect: u8) -> Result<()> {
        self.write_batch(vec![protocol::frame(0x91, &[effect])])
            .await
    }
    pub async fn set_ide_state(&self, state: u8) -> Result<()> {
        if state > 8 {
            return Err(BleError::Invalid("IDE state must be 0..8".into()));
        }
        self.write_batch(vec![protocol::frame(0x90, &[state])])
            .await
    }
    pub async fn set_work_mode(&self, mode: u8) -> Result<()> {
        if mode > 3 {
            return Err(BleError::Invalid("mode must be 0..3".into()));
        }
        self.write_batch(vec![protocol::frame(0x92, &[mode])]).await
    }
    pub async fn set_light_brightness(&self, brightness: u8) -> Result<()> {
        if !(1..=100).contains(&brightness) {
            return Err(BleError::Invalid("brightness must be 1..100".into()));
        }
        self.write_batch(vec![protocol::frame(0x85, &[brightness])])
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn candidate_filter_rejects_unrelated_and_unnamed_devices() {
        assert!(candidate_name("AhaKey Test"));
        assert!(candidate_name(" ahakey keyboard "));
        assert!(!candidate_name("Unnamed Bluetooth device"));
        assert!(!candidate_name("Mahakala speaker"));
    }
    #[test]
    fn bluetooth_base_uuid_uses_network_order() {
        assert_eq!(
            characteristic_uuid(0x7343).to_string(),
            "00007343-0000-1000-8000-00805f9b34fb"
        );
    }
    #[test]
    fn stale_generation_cannot_republish_ready() {
        let (events, _) = broadcast::channel(4);
        let s = Shared {
            state: StdMutex::new(BleSnapshot {
                generation: 0,
                phase: ConnectionPhase::Disconnected,
                device: None,
                status: None,
                error: None,
            }),
            cancel: StdMutex::new(CancellationToken::new()),
            events,
        };
        let (old, cancel) = s.next();
        let (current, _) = s.next();
        assert!(cancel.is_cancelled());
        assert!(matches!(s.next_if(Some(old)), Err(BleError::Cancelled)));
        assert_eq!(s.state.lock().unwrap().generation, current);
        s.publish(old, |s| s.phase = ConnectionPhase::Ready);
        assert_eq!(s.state.lock().unwrap().phase, ConnectionPhase::Disconnected);
        s.publish(current, |s| s.phase = ConnectionPhase::Connecting);
        assert_eq!(s.state.lock().unwrap().phase, ConnectionPhase::Connecting);
    }
    #[tokio::test]
    async fn cancellation_preempts_native_result() {
        let c = CancellationToken::new();
        c.cancel();
        assert!(matches!(
            operation(&c, "test", async { Ok::<_, btleplug::Error>(()) }).await,
            Err(BleError::Cancelled)
        ));
    }
}
