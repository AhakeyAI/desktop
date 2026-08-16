package com.example.ahakey.firmware;

import java.nio.file.Path;

/**
 * Generates the documented WCHISPStudio CH57x/CH59x command-line configuration.
 * DataFlash is deliberately preserved for an ordinary firmware update.
 */
public final class WchIspConfig {
    private WchIspConfig() {}

    public static String forCh582(Path firmwareHex) {
        String path = firmwareHex.toAbsolutePath().normalize().toString();
        return """
            [Public]
            MCUName=CH582
            bMCULine=6
            bMCUType=130
            DataFlashFile=.
            swzUserFile1=%s
            swzUserFile2=.
            swzUserFile3=.
            swzUserFile4=.
            swzUserFile5=.
            DataFlashFileSel=0
            IsUserFile1Sel=1
            IsUserFile2Sel=0
            IsUserFile3Sel=0
            IsUserFile4Sel=0
            IsUserFile5Sel=0

            [CH57x-58xUICfg]
            bDnInterType=0
            Baud=115200
            DwnldCfgPin=PB22
            BootPinNum=1
            WProtectAddr=.
            IsCodeProtect=1
            IsRSTAsInputPin=0
            ExtRSTPinSel=.
            ExtRSTPinSelNum=1
            IndependentWDGEn=0
            IsSerialNoBtnDwnld=0
            IsClearDataFlash=0
            IsEraseAllCFlash=1
            IsAfterDownRest=0
            bVerifyType=0
            """.formatted(path);
    }
}
