//! Windows can retain an HID/GATT connection while the keyboard stops advertising.
//! Enumerate registered AhaKey devices and own their WinRT GATT handles directly.
use btleplug::{
    api::{
        BDAddr, CharPropFlags, Characteristic, PeripheralProperties, ValueNotification, WriteType,
    },
    Error, Result,
};
use futures::{stream, Stream};
use std::{
    collections::{BTreeSet, HashMap},
    future::IntoFuture,
    pin::Pin,
    sync::{Arc, Mutex},
};
use tokio::sync::broadcast;
use uuid::Uuid;
use windows::{
    core::Ref,
    Devices::{
        Bluetooth::{
            BluetoothCacheMode, BluetoothConnectionStatus, BluetoothLEDevice,
            GenericAttributeProfile::*,
        },
        Enumeration::DeviceInformation,
    },
    Foundation::TypedEventHandler,
    Storage::Streams::{DataReader, DataWriter},
};

#[derive(Clone)]
pub struct Peripheral {
    shared: Arc<Shared>,
}
struct Shared {
    address: BDAddr,
    name: String,
    rssi: Option<i16>,
    state: Mutex<State>,
    notifications: broadcast::Sender<ValueNotification>,
}
#[derive(Default)]
struct State {
    device: Option<BluetoothLEDevice>,
    services: Vec<GattDeviceService>,
    chars: HashMap<Uuid, (Characteristic, GattCharacteristic)>,
    tokens: HashMap<Uuid, i64>,
}
impl Drop for State {
    fn drop(&mut self) {
        for (uuid, token) in self.tokens.drain() {
            if let Some((_, c)) = self.chars.get(&uuid) {
                let _ = c.RemoveValueChanged(token);
            }
        }
        self.chars.clear();
        for service in self.services.drain(..) {
            let _ = service.Close();
        }
        if let Some(device) = self.device.take() {
            let _ = device.Close();
        }
    }
}
fn status(value: GattCommunicationStatus, operation: &str) -> Result<()> {
    if value == GattCommunicationStatus::Success {
        Ok(())
    } else {
        Err(Error::Other(format!("{operation}: {value:?}").into()))
    }
}
impl Peripheral {
    pub fn new(address: BDAddr, name: String, rssi: Option<i16>) -> Self {
        let (notifications, _) = broadcast::channel(64);
        Self {
            shared: Arc::new(Shared {
                address,
                name,
                rssi,
                state: Mutex::new(State::default()),
                notifications,
            }),
        }
    }
    pub fn id(&self) -> String {
        self.shared.address.to_string()
    }
    pub async fn properties(&self) -> Result<Option<PeripheralProperties>> {
        Ok(Some(PeripheralProperties {
            address: self.shared.address,
            local_name: Some(self.shared.name.clone()),
            rssi: self.shared.rssi,
            ..Default::default()
        }))
    }
    pub async fn connect(&self) -> Result<()> {
        let device = BluetoothLEDevice::FromBluetoothAddressAsync(self.shared.address.into())?
            .into_future()
            .await?;
        self.shared.state.lock().unwrap().device = Some(device);
        Ok(())
    }
    fn device(&self) -> Result<BluetoothLEDevice> {
        self.shared
            .state
            .lock()
            .unwrap()
            .device
            .clone()
            .ok_or(Error::NotConnected)
    }
    pub async fn is_connected(&self) -> Result<bool> {
        Ok(self.device()?.ConnectionStatus()? == BluetoothConnectionStatus::Connected)
    }
    pub async fn discover_services(&self) -> Result<()> {
        let result = self
            .device()?
            .GetGattServicesWithCacheModeAsync(BluetoothCacheMode::Uncached)?
            .into_future()
            .await?;
        status(result.Status()?, "discover services")?;
        // Store handles before await so cancellation/error cleanup closes every opened service.
        let services: Vec<_> = result.Services()?.into_iter().collect();
        self.shared.state.lock().unwrap().services = services.clone();
        for service in services {
            let service_uuid = Uuid::from_u128(service.Uuid()?.to_u128());
            if service_uuid != super::characteristic_uuid(0x7340) {
                continue;
            }
            let result = service
                .GetCharacteristicsWithCacheModeAsync(BluetoothCacheMode::Uncached)?
                .into_future()
                .await?;
            status(result.Status()?, "discover characteristics")?;
            for native in result.Characteristics()? {
                let uuid = Uuid::from_u128(native.Uuid()?.to_u128());
                let properties =
                    CharPropFlags::from_bits_truncate(native.CharacteristicProperties()?.0 as u8);
                let descriptor = Characteristic {
                    uuid,
                    service_uuid,
                    properties,
                    descriptors: BTreeSet::new(),
                };
                self.shared
                    .state
                    .lock()
                    .unwrap()
                    .chars
                    .insert(uuid, (descriptor, native));
            }
        }
        Ok(())
    }
    pub fn characteristics(&self) -> BTreeSet<Characteristic> {
        self.shared
            .state
            .lock()
            .unwrap()
            .chars
            .values()
            .map(|(c, _)| c.clone())
            .collect()
    }
    fn characteristic(&self, c: &Characteristic) -> Result<GattCharacteristic> {
        self.shared
            .state
            .lock()
            .unwrap()
            .chars
            .get(&c.uuid)
            .map(|(_, c)| c.clone())
            .ok_or(Error::DeviceNotFound)
    }
    pub async fn notifications(
        &self,
    ) -> Result<Pin<Box<dyn Stream<Item = ValueNotification> + Send>>> {
        Ok(Box::pin(stream::unfold(
            self.shared.notifications.subscribe(),
            |mut rx| async move {
                loop {
                    match rx.recv().await {
                        Ok(value) => return Some((value, rx)),
                        Err(broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(_) => return None,
                    }
                }
            },
        )))
    }
    pub async fn subscribe(&self, c: &Characteristic) -> Result<()> {
        let native = self.characteristic(c)?;
        let uuid = c.uuid;
        let service_uuid = c.service_uuid;
        let sender = self.shared.notifications.clone();
        let token = native.ValueChanged(&TypedEventHandler::new(
            move |_: Ref<GattCharacteristic>, args: Ref<GattValueChangedEventArgs>| {
                if let Ok(args) = args.ok() {
                    let buffer = args.CharacteristicValue()?;
                    if buffer.Length()? > 4096 {
                        return Ok(());
                    }
                    let reader = DataReader::FromBuffer(&buffer)?;
                    let mut value = vec![0; reader.UnconsumedBufferLength()? as usize];
                    reader.ReadBytes(&mut value)?;
                    let _ = sender.send(ValueNotification {
                        uuid,
                        service_uuid,
                        value,
                    });
                }
                Ok(())
            },
        ))?;
        self.shared
            .state
            .lock()
            .unwrap()
            .tokens
            .insert(c.uuid, token);
        let mode = if c.properties.contains(CharPropFlags::NOTIFY) {
            GattClientCharacteristicConfigurationDescriptorValue::Notify
        } else {
            GattClientCharacteristicConfigurationDescriptorValue::Indicate
        };
        let result = native
            .WriteClientCharacteristicConfigurationDescriptorAsync(mode)?
            .into_future()
            .await?;
        status(result, "enable notifications")
    }
    pub async fn unsubscribe(&self, c: &Characteristic) -> Result<()> {
        let native = self.characteristic(c)?;
        if let Some(token) = self.shared.state.lock().unwrap().tokens.remove(&c.uuid) {
            native.RemoveValueChanged(token)?;
        }
        let result = native
            .WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue::None,
            )?
            .into_future()
            .await?;
        status(result, "disable notifications")
    }
    pub async fn write(&self, c: &Characteristic, bytes: &[u8], mode: WriteType) -> Result<()> {
        let writer = DataWriter::new()?;
        writer.WriteBytes(bytes)?;
        let option = match mode {
            WriteType::WithResponse => GattWriteOption::WriteWithResponse,
            WriteType::WithoutResponse => GattWriteOption::WriteWithoutResponse,
        };
        let native = self.characteristic(c)?;
        // Request link encryption from Windows before writing protected firmware
        // commands. Opening a GATT handle is not evidence of an encrypted link.
        native.SetProtectionLevel(GattProtectionLevel::EncryptionRequired)?;
        let operation = native.WriteValueWithOptionAsync(&writer.DetachBuffer()?, option)?;
        let result = operation.into_future().await.map_err(|error| {
            if matches!(error.code().0 as u32, 0x8065000f | 0x80650005) {
                Error::Other("蓝牙链路未通过加密认证。请先在 Windows 蓝牙设置中完成 AhaKey 配对；刷写新固件后可能需要移除旧配对再重新添加。USB 配置与输入不依赖这条蓝牙连接。".into())
            } else {
                error.into()
            }
        })?;
        status(result, "write command")
    }
    pub async fn disconnect(&self) -> Result<()> {
        *self.shared.state.lock().unwrap() = State::default();
        Ok(())
    }
}

pub async fn registered() -> Result<Vec<Peripheral>> {
    let selector = BluetoothLEDevice::GetDeviceSelector()?;
    let devices = DeviceInformation::FindAllAsyncAqsFilter(&selector)?
        .into_future()
        .await?;
    let mut result = Vec::new();
    let devices: Vec<_> = devices.into_iter().collect();
    for info in devices {
        let name = info.Name()?.to_string();
        if !super::candidate_name(&name) {
            continue;
        }
        // Discovery must not open/Close aliases of a device used by an active
        // GATT session. The Windows BLE interface ID includes the remote address.
        let Some(address) = registered_address(&info.Id()?.to_string()) else {
            continue;
        };
        result.push(Peripheral::new(address, name, None));
    }
    Ok(result)
}

fn registered_address(id: &str) -> Option<BDAddr> {
    if !id.starts_with("BluetoothLE#BluetoothLE") {
        return None;
    }
    id.rsplit_once('-')?.1.parse().ok()
}

#[cfg(test)]
mod tests {
    #[test]
    fn reads_remote_address_without_opening_device_handles() {
        assert_eq!(
            super::registered_address("BluetoothLE#BluetoothLE00:11:22:33:44:55-aa:bb:cc:dd:ee:ff")
                .unwrap()
                .to_string(),
            "AA:BB:CC:DD:EE:FF"
        );
        assert!(
            super::registered_address("BluetoothLE#BluetoothLE00:11:22:33:44:55-invalid").is_none()
        );
        assert!(super::registered_address("other-aa:bb:cc:dd:ee:ff").is_none());
    }
}
