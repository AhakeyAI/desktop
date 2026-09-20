use crate::{protocol, CloudError, SecretToken};
use futures_util::{SinkExt, StreamExt};
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Condvar, Mutex,
    },
    time::Duration,
};
use tokio::{
    sync::mpsc,
    task::JoinHandle,
    time::{timeout, Instant},
};
use tokio_tungstenite::{
    connect_async_with_config,
    tungstenite::{
        client::IntoClientRequest, http::HeaderValue, protocol::WebSocketConfig, Message,
    },
};
use tokio_util::sync::CancellationToken;

pub const ENDPOINT: &str = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async";
const QUEUE_PACKETS: usize = 80; // At most sixteen seconds of 200 ms audio, never silently dropped.
const MAX_SAMPLES: usize = 16000 * 300;

#[derive(Debug, Clone)]
pub struct CloudConfig {
    pub app_id: String,
    pub resource_id: String,
}
impl Default for CloudConfig {
    fn default() -> Self {
        Self {
            app_id: String::new(),
            resource_id: "volc.bigasr.sauc.duration".into(),
        }
    }
}
impl CloudConfig {
    fn validate(&self) -> Result<(), CloudError> {
        for value in [&self.app_id, &self.resource_id] {
            if value.is_empty() || value.len() > 256 || !value.bytes().all(|b| b.is_ascii_graphic())
            {
                return Err(CloudError::InvalidConfig);
            }
        }
        Ok(())
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CloudEvent {
    Partial(String),
    Final(String),
    Error(CloudError),
}
enum Input {
    Audio(Vec<i16>),
    Finish,
}
type Callback = Arc<dyn Fn(CloudEvent) + Send + Sync>;
struct Shared {
    cancellation: CancellationToken,
    callback_gate: Mutex<CallbackGate>,
    callback_idle: Condvar,
    done: AtomicBool,
    failure: Mutex<Option<CloudError>>,
}
struct CallbackGate {
    enabled: bool,
    executing: Option<std::thread::ThreadId>,
}
impl Shared {
    fn emit(&self, callback: &Callback, event: CloudEvent) {
        let mut gate = self.callback_gate.lock().unwrap_or_else(|p| p.into_inner());
        if !gate.enabled {
            return;
        }
        if matches!(&event, CloudEvent::Final(_) | CloudEvent::Error(_)) {
            gate.enabled = false;
        }
        gate.executing = Some(std::thread::current().id());
        drop(gate);
        // Do not hold the gate while invoking user code: final handlers can safely
        // drop/cancel their own session. Other threads wait for this callback to exit.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| callback(event)));
        let mut gate = self.callback_gate.lock().unwrap_or_else(|p| p.into_inner());
        gate.executing = None;
        self.callback_idle.notify_all();
        drop(gate);
        if let Err(panic) = result {
            std::panic::resume_unwind(panic);
        }
    }
    fn cancel(&self) {
        let mut gate = self.callback_gate.lock().unwrap_or_else(|p| p.into_inner());
        gate.enabled = false;
        self.cancellation.cancel();
        while gate
            .executing
            .is_some_and(|id| id != std::thread::current().id())
        {
            gate = self
                .callback_idle
                .wait(gate)
                .unwrap_or_else(|p| p.into_inner());
        }
    }
    fn fail(&self, error: CloudError) {
        *self.failure.lock().unwrap_or_else(|p| p.into_inner()) = Some(error);
        self.cancellation.cancel();
    }
    fn cancellation_error(&self) -> CloudError {
        self.failure
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .clone()
            .unwrap_or(CloudError::Cancelled)
    }
}

/// An explicit cloud recording. Construction starts a connection only after validating settings.
/// Caller supplies 16 kHz mono audio; no microphone or credentials are loaded implicitly.
/// Callbacks should enqueue quickly; cancelling or dropping the session from a callback is safe.
pub struct CloudSession {
    input: mpsc::Sender<Input>,
    accepting: Mutex<bool>,
    shared: Arc<Shared>,
    task: Option<JoinHandle<Result<(), CloudError>>>,
}
impl CloudSession {
    /// Requires an entered Tokio runtime. The fixed endpoint cannot be redirected through settings.
    pub fn start(
        config: CloudConfig,
        token: SecretToken,
        callback: impl Fn(CloudEvent) + Send + Sync + 'static,
    ) -> Result<Self, CloudError> {
        Self::start_at(
            config,
            token,
            Arc::new(callback),
            ENDPOINT,
            Limits::default(),
        )
    }
    fn start_at(
        config: CloudConfig,
        token: SecretToken,
        callback: Callback,
        endpoint: &str,
        limits: Limits,
    ) -> Result<Self, CloudError> {
        config.validate()?;
        let runtime = tokio::runtime::Handle::try_current().map_err(|_| CloudError::Connection)?;
        let (input, receiver) = mpsc::channel(QUEUE_PACKETS);
        let shared = Arc::new(Shared {
            cancellation: CancellationToken::new(),
            callback_gate: Mutex::new(CallbackGate {
                enabled: true,
                executing: None,
            }),
            callback_idle: Condvar::new(),
            done: AtomicBool::new(false),
            failure: Mutex::new(None),
        });
        let worker_shared = shared.clone();
        let endpoint = endpoint.to_owned();
        let task = runtime.spawn(async move {
            let result = run(
                config,
                token,
                receiver,
                &worker_shared,
                &callback,
                &endpoint,
                limits,
            )
            .await;
            if let Err(error) = &result {
                if *error != CloudError::Cancelled {
                    worker_shared.emit(&callback, CloudEvent::Error(error.clone()));
                }
            }
            worker_shared.done.store(true, Ordering::Release);
            result
        });
        Ok(Self {
            input,
            accepting: Mutex::new(true),
            shared,
            task: Some(task),
        })
    }
    /// Nonblocking bounded enqueue suitable for a microphone callback. No audio is silently dropped.
    pub fn try_send_pcm16(&self, pcm: &[i16]) -> Result<(), CloudError> {
        if pcm.is_empty() || pcm.len() > 3200 {
            return Err(CloudError::InvalidAudio);
        }
        let accepting = self.accepting.lock().unwrap_or_else(|p| p.into_inner());
        if !*accepting
            || self.shared.done.load(Ordering::Acquire)
            || self.shared.cancellation.is_cancelled()
        {
            return Err(CloudError::Ended);
        }
        self.input
            .try_send(Input::Audio(pcm.to_vec()))
            .map_err(|e| match e {
                mpsc::error::TrySendError::Full(_) => {
                    self.shared.fail(CloudError::QueueFull);
                    CloudError::QueueFull
                }
                mpsc::error::TrySendError::Closed(_) => CloudError::Ended,
            })
    }
    /// Queues end-of-audio after earlier audio. Repeated calls are harmless; no further audio is accepted.
    pub async fn finish(&self) -> Result<(), CloudError> {
        {
            let mut accepting = self.accepting.lock().unwrap_or_else(|p| p.into_inner());
            if !*accepting {
                return Ok(());
            }
            *accepting = false;
        }
        tokio::select! {biased;
            _=self.shared.cancellation.cancelled()=>Err(self.shared.cancellation_error()),
            result=timeout(Duration::from_secs(10),self.input.send(Input::Finish))=>match result {
                Ok(Ok(()))=>Ok(()),Ok(Err(_))=>Err(CloudError::Ended),Err(_)=>{self.shared.fail(CloudError::Timeout);Err(CloudError::Timeout)}
            }
        }
    }
    /// Suppresses future callbacks and interrupts connect, send, receive and final-result waits.
    pub fn cancel(&self) {
        self.shared.cancel();
    }
    pub fn is_finished(&self) -> bool {
        self.shared.done.load(Ordering::Acquire)
    }
    pub async fn wait(mut self) -> Result<(), CloudError> {
        self.task
            .take()
            .ok_or(CloudError::Ended)?
            .await
            .map_err(|_| CloudError::Connection)?
    }
}
impl Drop for CloudSession {
    fn drop(&mut self) {
        self.shared.cancel();
    }
}

#[derive(Clone, Copy)]
struct Limits {
    connect: Duration,
    send: Duration,
    final_result: Duration,
    recording: Duration,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            connect: Duration::from_secs(15),
            send: Duration::from_secs(10),
            final_result: Duration::from_secs(20),
            recording: Duration::from_secs(300),
        }
    }
}
async fn run(
    config: CloudConfig,
    token: SecretToken,
    mut input: mpsc::Receiver<Input>,
    shared: &Shared,
    callback: &Callback,
    endpoint: &str,
    limits: Limits,
) -> Result<(), CloudError> {
    let mut request = endpoint
        .into_client_request()
        .map_err(|_| CloudError::InvalidConfig)?;
    for (name, value) in [
        ("X-Api-App-Key", config.app_id.as_str()),
        ("X-Api-Access-Key", token.expose()),
        ("X-Api-Resource-Id", config.resource_id.as_str()),
    ] {
        let mut header = HeaderValue::from_str(value).map_err(|_| CloudError::InvalidConfig)?;
        header.set_sensitive(true);
        request.headers_mut().insert(name, header);
    }
    request.headers_mut().insert(
        "X-Api-Connect-Id",
        HeaderValue::from_str(&uuid::Uuid::new_v4().to_string())
            .map_err(|_| CloudError::InvalidConfig)?,
    );
    let ws_config = WebSocketConfig::default()
        .max_message_size(Some(protocol::MAX_FRAME_BYTES))
        .max_frame_size(Some(protocol::MAX_FRAME_BYTES));
    let (mut socket, _) = tokio::select! {biased;
        _=shared.cancellation.cancelled()=>return Err(shared.cancellation_error()),
        result=timeout(limits.connect,connect_async_with_config(request,Some(ws_config),false))=>result.map_err(|_|CloudError::Timeout)?.map_err(|_|CloudError::Connection)?
    };
    drop(token);
    tokio::select! {biased;
        _=shared.cancellation.cancelled()=>return Err(shared.cancellation_error()),
        result=timeout(limits.send,socket.send(Message::Binary(protocol::configuration()?.into())))=>result.map_err(|_|CloudError::Timeout)?.map_err(|_|CloudError::Connection)?
    }
    let mut deadline = Instant::now() + limits.recording;
    let mut finishing = false;
    let mut samples = 0;
    loop {
        tokio::select! {biased;
            _=shared.cancellation.cancelled()=>return Err(shared.cancellation_error()),
            _=tokio::time::sleep_until(deadline)=>return Err(if finishing {CloudError::Timeout} else {CloudError::RecordingLimit}),
            message=socket.next()=>match message {
                Some(Ok(Message::Binary(bytes)))=>{
                    let result=protocol::parse(&bytes)?;
                    if result.is_final {
                        shared.emit(callback,CloudEvent::Final(result.text));
                        return Ok(());
                    }
                    if !result.text.is_empty() {shared.emit(callback,CloudEvent::Partial(result.text));}
                },
                Some(Ok(Message::Ping(bytes)))=>{
                    tokio::select! {biased;
                        _=shared.cancellation.cancelled()=>return Err(shared.cancellation_error()),
                        result=timeout(limits.send,socket.send(Message::Pong(bytes)))=>result.map_err(|_|CloudError::Timeout)?.map_err(|_|CloudError::Connection)?
                    }
                },
                Some(Ok(Message::Pong(_)))=>{},
                Some(Ok(Message::Close(_)))|None=>return Err(CloudError::Connection),
                Some(Err(_))=>return Err(CloudError::Connection),
                _=>return Err(CloudError::Protocol),
            },
            item=input.recv(),if !finishing=>{
                let (pcm,last)=match item {Some(Input::Audio(pcm))=>(pcm,false),Some(Input::Finish)|None=>(Vec::new(),true)};
                samples+=pcm.len(); if samples>MAX_SAMPLES {return Err(CloudError::RecordingLimit);}
                tokio::select! {biased;
                    _=shared.cancellation.cancelled()=>return Err(shared.cancellation_error()),
                    result=timeout(limits.send,socket.send(Message::Binary(protocol::audio(&pcm,last)?.into())))=>result.map_err(|_|CloudError::Timeout)?.map_err(|_|CloudError::Connection)?
                }
                if last {finishing=true;deadline=Instant::now()+limits.final_result;}
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;
    use tokio_tungstenite::{
        accept_async, accept_hdr_async,
        tungstenite::{
            handshake::server::{Request, Response},
            protocol::frame::{
                coding::{Data, OpCode},
                Frame,
            },
        },
    };
    fn config() -> CloudConfig {
        CloudConfig {
            app_id: "fake-app".into(),
            ..Default::default()
        }
    }
    fn token() -> SecretToken {
        SecretToken::new("fake-mock-token").unwrap()
    }
    fn capture() -> (Arc<Mutex<Vec<CloudEvent>>>, Callback) {
        let events = Arc::new(Mutex::new(Vec::new()));
        let copy = events.clone();
        (
            events,
            Arc::new(move |event| copy.lock().unwrap().push(event)),
        )
    }
    async fn listener() -> (TcpListener, String) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!("ws://{}/asr", listener.local_addr().unwrap());
        (listener, endpoint)
    }
    #[tokio::test]
    #[allow(clippy::result_large_err)] // Third-party handshake callback fixes the error response type.
    async fn mock_fragmented_partial_final_headers_and_wire_audio() {
        let (listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let server = tokio::spawn(async move {
            let (tcp, _) = listener.accept().await.unwrap();
            let mut ws = accept_hdr_async(tcp, |request: &Request, response: Response| {
                assert_eq!(request.headers()["X-Api-App-Key"], "fake-app");
                assert_eq!(request.headers()["X-Api-Access-Key"], "fake-mock-token");
                assert_eq!(
                    request.headers()["X-Api-Resource-Id"],
                    "volc.bigasr.sauc.duration"
                );
                assert!(uuid::Uuid::parse_str(
                    request.headers()["X-Api-Connect-Id"].to_str().unwrap()
                )
                .is_ok());
                Ok(response)
            })
            .await
            .unwrap();
            assert_eq!(
                ws.next().await.unwrap().unwrap(),
                Message::Binary(protocol::configuration().unwrap().into())
            );
            assert_eq!(
                ws.next().await.unwrap().unwrap(),
                Message::Binary(protocol::audio(&[1, -2, 3], false).unwrap().into())
            );
            let partial = protocol::response("hello", 1, 1);
            let split = partial.len() / 2;
            ws.send(Message::Frame(Frame::message(
                partial[..split].to_vec(),
                OpCode::Data(Data::Binary),
                false,
            )))
            .await
            .unwrap();
            ws.send(Message::Frame(Frame::message(
                partial[split..].to_vec(),
                OpCode::Data(Data::Continue),
                true,
            )))
            .await
            .unwrap();
            assert_eq!(
                ws.next().await.unwrap().unwrap(),
                Message::Binary(protocol::audio(&[], true).unwrap().into())
            );
            ws.feed(Message::Binary(
                protocol::response("hello world", 3, -2).into(),
            ))
            .await
            .unwrap();
            ws.feed(Message::Binary(
                protocol::response("duplicate final", 3, -3).into(),
            ))
            .await
            .unwrap();
            ws.flush().await.unwrap();
        });
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, Limits::default())
                .unwrap();
        session.try_send_pcm16(&[1, -2, 3]).unwrap();
        session.finish().await.unwrap();
        session.finish().await.unwrap();
        assert_eq!(session.try_send_pcm16(&[4]), Err(CloudError::Ended));
        timeout(Duration::from_secs(5), session.wait())
            .await
            .unwrap()
            .unwrap();
        server.await.unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            vec![
                CloudEvent::Partial("hello".into()),
                CloudEvent::Final("hello world".into())
            ]
        );
    }
    #[tokio::test]
    async fn cancellation_interrupts_handshake_and_suppresses_callbacks() {
        let (listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, Limits::default())
                .unwrap();
        let (_tcp, _) = listener.accept().await.unwrap();
        session.cancel();
        assert_eq!(
            timeout(Duration::from_secs(1), session.wait())
                .await
                .unwrap(),
            Err(CloudError::Cancelled)
        );
        assert!(events.lock().unwrap().is_empty());
    }
    #[tokio::test]
    async fn stalled_final_response_times_out_once() {
        let (listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let server = tokio::spawn(async move {
            let (tcp, _) = listener.accept().await.unwrap();
            let mut ws = accept_async(tcp).await.unwrap();
            ws.next().await.unwrap().unwrap();
            ws.next().await.unwrap().unwrap();
            // Wait for client timeout to close the connection, without inventing a final.
            let _ = ws.next().await;
        });
        let limits = Limits {
            final_result: Duration::from_millis(40),
            ..Limits::default()
        };
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, limits).unwrap();
        session.finish().await.unwrap();
        assert_eq!(
            timeout(Duration::from_secs(2), session.wait())
                .await
                .unwrap(),
            Err(CloudError::Timeout)
        );
        server.await.unwrap();
        assert_eq!(
            *events.lock().unwrap(),
            vec![CloudEvent::Error(CloudError::Timeout)]
        );
    }
    #[tokio::test]
    async fn stalled_handshake_has_a_deadline() {
        let (listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let limits = Limits {
            connect: Duration::from_millis(40),
            ..Limits::default()
        };
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, limits).unwrap();
        let (_tcp, _) = listener.accept().await.unwrap();
        assert_eq!(
            timeout(Duration::from_secs(2), session.wait())
                .await
                .unwrap(),
            Err(CloudError::Timeout)
        );
        assert_eq!(
            *events.lock().unwrap(),
            vec![CloudEvent::Error(CloudError::Timeout)]
        );
    }
    #[tokio::test]
    async fn bounded_queue_fails_instead_of_dropping_audio() {
        let (_listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, Limits::default())
                .unwrap();
        for _ in 0..QUEUE_PACKETS {
            session.try_send_pcm16(&[1; 3200]).unwrap();
        }
        assert_eq!(session.try_send_pcm16(&[2]), Err(CloudError::QueueFull));
        assert_eq!(session.wait().await, Err(CloudError::QueueFull));
        assert_eq!(
            *events.lock().unwrap(),
            vec![CloudEvent::Error(CloudError::QueueFull)]
        );
    }
    #[tokio::test]
    async fn invalid_settings_never_start_a_session() {
        let (_, callback) = capture();
        assert!(matches!(
            CloudSession::start_at(
                CloudConfig::default(),
                token(),
                callback,
                ENDPOINT,
                Limits::default()
            ),
            Err(CloudError::InvalidConfig)
        ));
    }
    #[tokio::test]
    async fn cancelled_live_session_emits_no_late_final() {
        let (listener, endpoint) = listener().await;
        let (events, callback) = capture();
        let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
        let (send_tx, send_rx) = tokio::sync::oneshot::channel();
        let server = tokio::spawn(async move {
            let (tcp, _) = listener.accept().await.unwrap();
            let mut ws = accept_async(tcp).await.unwrap();
            ws.next().await.unwrap().unwrap();
            ready_tx.send(()).unwrap();
            send_rx.await.unwrap();
            let _ = ws
                .send(Message::Binary(
                    protocol::response("late secret text", 3, -1).into(),
                ))
                .await;
        });
        let session =
            CloudSession::start_at(config(), token(), callback, &endpoint, Limits::default())
                .unwrap();
        ready_rx.await.unwrap();
        session.cancel();
        send_tx.send(()).unwrap();
        assert_eq!(session.wait().await, Err(CloudError::Cancelled));
        server.await.unwrap();
        assert!(events.lock().unwrap().is_empty());
    }
    fn shared_gate() -> Arc<Shared> {
        Arc::new(Shared {
            cancellation: CancellationToken::new(),
            callback_gate: Mutex::new(CallbackGate {
                enabled: true,
                executing: None,
            }),
            callback_idle: Condvar::new(),
            done: AtomicBool::new(false),
            failure: Mutex::new(None),
        })
    }
    #[test]
    fn callback_can_cancel_its_own_session_without_deadlock() {
        let shared = shared_gate();
        let callback_shared = shared.clone();
        let calls = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let callback_calls = calls.clone();
        let callback: Callback = Arc::new(move |_| {
            callback_calls.fetch_add(1, Ordering::SeqCst);
            callback_shared.cancel();
        });
        shared.emit(&callback, CloudEvent::Partial("first".into()));
        shared.emit(&callback, CloudEvent::Final("must not appear".into()));
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn cross_thread_cancel_waits_for_an_active_callback() {
        let shared = shared_gate();
        let (entered_tx, entered_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let release_rx = Mutex::new(release_rx);
        let callback: Callback = Arc::new(move |_| {
            entered_tx.send(()).unwrap();
            release_rx.lock().unwrap().recv().unwrap();
        });
        let worker_shared = shared.clone();
        let worker = std::thread::spawn(move || {
            worker_shared.emit(&callback, CloudEvent::Partial("in flight".into()))
        });
        entered_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        let (cancelled_tx, cancelled_rx) = std::sync::mpsc::channel();
        let canceller = std::thread::spawn(move || {
            shared.cancel();
            cancelled_tx.send(()).unwrap();
        });
        assert!(cancelled_rx
            .recv_timeout(Duration::from_millis(20))
            .is_err());
        release_tx.send(()).unwrap();
        cancelled_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        worker.join().unwrap();
        canceller.join().unwrap();
    }
}
