package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WchIspConfigTest {
    @Test
    void normalFirmwareUpdateTargetsCh582AndPreservesDataFlash() {
        String config = WchIspConfig.forCh582(Path.of("firmware.hex"));
        assertTrue(config.contains("MCUName=CH582"));
        assertTrue(config.contains("bMCULine=6"));
        assertTrue(config.contains("bMCUType=130"));
        assertTrue(config.contains("IsClearDataFlash=0"));
        assertTrue(config.contains("[CH57x-58xUICfg]"));
        assertFalse(config.contains("[CH57x-59xUICfg]"));
        assertTrue(config.contains("IsEraseAllCFlash=1"));
        assertFalse(config.contains("IsClearCodeFlash"));
        assertTrue(config.contains("swzUserFile5=."));
        assertTrue(config.contains("IsUserFile5Sel=0"));
        assertTrue(config.contains("IsAfterDownRest=0"));
        assertFalse(config.contains("IsAfterDownReset"));
        assertTrue(config.contains("IsRSTAsInputPin=0"));
        assertTrue(config.contains("ExtRSTPinSel=."));
        assertTrue(config.contains("ExtRSTPinSelNum=1"));
        assertTrue(config.contains("IndependentWDGEn=0"));
        assertTrue(config.contains("IsSerialNoBtnDwnld=0"));
        assertTrue(config.contains("bVerifyType=0"));
    }

    @Test
    void documentedExitCodesAreMapped() {
        assertEquals("未找到处于下载模式的设备", WchIspExitCodes.describe(5));
        assertEquals("校验失败", WchIspExitCodes.describe(14));
    }
}
