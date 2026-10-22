package com.example.ahakey.test;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.service.BleManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * 触发设备进入 USB ISP 模式(对应固件 0x9A 命令)。
 *
 * <p>流程:连 BLE → 发 0x9A → 设备 reset → WCHISP Studio 烧录。
 *
 * <p>运行:
 * <pre>
 *   mvn compile exec:java -Dexec.mainClass=com.example.ahakey.test.EnterBootTest
 * </pre>
 *
 * <p><b>注意</b>:执行后设备会 reset 进 BOOT 模式,跑前确认 WCHISP Studio 已打开准备烧录。
 * <p>救援:如果烧录失败,物理拔 USB → BOOT 引脚浮空 → 下次启动回 app。
 */
public class EnterBootTest {
    private static final Logger logger = LoggerFactory.getLogger(EnterBootTest.class);

    public static void main(String[] args) {
        CountDownLatch connectLatch = new CountDownLatch(1);

        BleManager ble = BleManager.fromEnvironment(new BleManager.BleCallback() {
            @Override
            public void onConnected() {
                logger.info("OK: connected to device");
                connectLatch.countDown();
            }

            @Override
            public void onDisconnected() {
                logger.warn("Device disconnected");
            }

            @Override
            public void onStatusReceived(DeviceStatus status) {
                // silent
            }

            @Override
            public void onError(String message) {
                logger.error("BLE error: {}", message);
            }
        });

        logger.info("Connecting BLE bridge...");
        ble.connect();

        boolean connected;
        try {
            connected = connectLatch.await(15, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.exit(1);
            return;
        }

        if (!connected) {
            logger.error("15s timeout, exit");
            System.exit(1);
        }

        // 等设备 BLE 稳定
        try {
            Thread.sleep(300);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // 确认操作
        logger.warn("==================================================");
        logger.warn("About to send 0x9A enterBoot command!");
        logger.warn("Device will reset into USB ISP mode in ~100ms");
        logger.warn("WCHISP Studio should be ready to flash");
        logger.warn("Press ENTER to continue (Ctrl+C to abort)...");
        logger.warn("==================================================");
        try {
            System.in.read();
        } catch (Exception e) {
            // ignore
        }

        try {
            ble.enterBoot();
            logger.info("OK: 0x9A sent. Device should reset now.");
            logger.info("Wait 2-3 seconds, then check WCHISP Studio for device");
        } catch (Exception e) {
            logger.error("enterBoot failed: {}", e.getMessage());
        }

        // 给点时间让 BLE 链路断开
        try {
            Thread.sleep(2000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        ble.disconnect();
        System.exit(0);
    }
}
