#[cfg(windows)]
#[tokio::main]
async fn main() -> Result<(), String> {
    use ahakey_ble::{routing::Config, usb_routing::UsbRouting};
    let args: Vec<_> = std::env::args().skip(1).collect();
    if !args.is_empty() && args != ["--use-usb"] {
        return Err(
            "Use no arguments to read; --use-usb explicitly saves up=USB, down=BLE A".into(),
        );
    }
    tokio::time::timeout(std::time::Duration::from_secs(15), async {
        let mut port = UsbRouting::open().await?;
        println!("USB device information: {:?}", port.device_status().await?);
        println!("USB routing before: {:?}", port.read().await?);
        if !args.is_empty() {
            println!(
                "USB routing save ACK: {:?}",
                port.apply(&Config {
                    mode: 1,
                    up: 2,
                    down: 0
                })
                .await?
            );
            println!("USB routing readback: {:?}", port.read().await?);
        }
        Ok(())
    })
    .await
    .map_err(|_| "USB operation timed out".to_owned())?
}
#[cfg(not(windows))]
fn main() {
    eprintln!("Windows vendor HID example only");
}
