//! macOS hardware probe: scan -> connect -> status query -> disconnect.
//! Run: cargo run --example probe --release
use ahakey_ble::BleClient;
use std::time::Duration;

#[tokio::main]
async fn main() -> ahakey_ble::Result<()> {
    let client = BleClient::new().await?;
    println!("[probe] scanning 5s ...");
    let secs: u64 = std::env::args()
        .nth(1)
        .and_then(|a| a.parse().ok())
        .unwrap_or(5)
        .clamp(1, 15);
    println!("[probe] scan window: {}s", secs);
    let devices = client.scan(Duration::from_secs(secs)).await?;
    for d in &devices {
        println!(
            "[scan] name={:?} rssi={:?} candidate={} id={}",
            d.name, d.rssi, d.is_candidate, d.id
        );
    }
    let Some(target) = devices.iter().find(|d| d.is_candidate).or(devices.first()) else {
        println!("[probe] no AhaKey device found");
        return Ok(());
    };
    println!("[probe] connecting to {:?} ...", target.name);
    client.connect(&target.id).await?;
    println!("[probe] connected, querying status ...");
    client.query_status().await?;
    tokio::time::sleep(Duration::from_millis(600)).await;
    let snap = client.status();
    println!("[probe] phase={:?}", snap.phase);
    match snap.status {
        Some(s) => println!(
            "[status] battery={}% signal={} fw={}.{} mode={} light_mode={} switch_state={} brightness={}",
            s.battery_level, s.signal, s.firmware_main, s.firmware_sub,
            s.work_mode, s.light_mode, s.switch_state, s.light_brightness
        ),
        None => println!("[status] <none>"),
    }
    client.disconnect().await?;
    println!("[probe] disconnected cleanly");
    Ok(())
}
