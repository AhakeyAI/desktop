#include "ble_init.h"
#include "config.h"
#include "main.h"
#include "math.h"
#include "stdio.h"

extern uint32_t Lib_Read_Flash(uint32_t addr, uint32_t num, uint32_t *pBuf);
extern uint32_t Lib_Write_Flash(uint32_t addr, uint32_t num, uint32_t *pBuf);

uint32_t Fram_Read_Flash(uint32_t addr, uint32_t num, uint32_t *pBuf)
{
    fram_read(addr, (uint8_t *) pBuf, num * 4);
    return 0;
}
uint32_t Fram_Write_Flash(uint32_t addr, uint32_t num, uint32_t *pBuf)
{
    // FLASH_Unlock_Fast();
    // FLASH_ErasePage_Fast(addr);
    // FLASH_ProgramPage_Fast(addr, pBuf);
    // FLASH_Lock_Fast();
    // Delay_Us(1);
    fram_write(addr, (uint8_t *) pBuf, num * 4);
    return 0;
}

uint8_t ble_name[][21] = {
    {'v', 'i', 'b', 'e', 0x20, 'c', 'o', 'd', 'e', 0x20, ',', ',', ',', ','}, // vibe code
};

#define APPEARANCE GAP_APPEARE_HID_DIGITIZER_TYABLET
// #define APPEARANCE 0x03C7
const uint8_t exter_scan_data[] = {
    0x05, // length of this data
    GAP_ADTYPE_SLAVE_CONN_INTERVAL_RANGE,
    LO_UINT16(DEFAULT_DESIRED_MIN_CONN_INTERVAL), // 100ms
    HI_UINT16(DEFAULT_DESIRED_MIN_CONN_INTERVAL),
    LO_UINT16(DEFAULT_DESIRED_MAX_CONN_INTERVAL), // 1s
    HI_UINT16(DEFAULT_DESIRED_MAX_CONN_INTERVAL),

    // service UUIDs
    0x05, // length of this data
    GAP_ADTYPE_16BIT_MORE,
    LO_UINT16(HID_SERV_UUID),
    HI_UINT16(HID_SERV_UUID),
    LO_UINT16(BATT_SERV_UUID),
    HI_UINT16(BATT_SERV_UUID),

    // Tx power level
    // 0x02, // length of this data
    // GAP_ADTYPE_POWER_LEVEL,
    // 0     // 0dBm
};
static uint8_t exter_advertData[] = {
    // flags
    0x02, // length of this data
    GAP_ADTYPE_FLAGS,
    GAP_ADTYPE_FLAGS_LIMITED | GAP_ADTYPE_FLAGS_BREDR_NOT_SUPPORTED,

    // appearance
    0x03, // length of this data
    GAP_ADTYPE_APPEARANCE,
    LO_UINT16(APPEARANCE),
    HI_UINT16(APPEARANCE),

    0x06,
    GAP_ADTYPE_MANUFACTURER_SPECIFIC,
    0x06,
    0x00,
    0x03,
    0x00,
    0x80,
};

extern uint8_t attDeviceName[GAP_DEVICE_NAME_LEN];
uint8_t        scanRspData__[MAX_SCAN_RES_LEN];
uint16_t       scanRspData__len;
uint8_t        advertData__[MAX_SCAN_RES_LEN];
uint16_t       advertData__len;
#define NAME_IN_ADV
// #define NAME_IN_SCAN
extern uint32_t g_LLE_IRQLibHandlerLocation;
void            PSK_WCHBLE_Init(void)
{
    uint8_t *name_point = NULL;
    {
        uint8_t localMacAddr[6];
        char    txt[5];
        GetMACAddress(localMacAddr);
        sprintf(txt, "%02X%02X", localMacAddr[1], localMacAddr[0]);
        memcpy((ble_name[0]) + 10, txt, 4);
    }
    if (data_in_fram.GAP_APPEARE) {
        exter_advertData[5] = LO_UINT16(data_in_fram.GAP_APPEARE);
        exter_advertData[6] = HI_UINT16(data_in_fram.GAP_APPEARE);
    } else {
        data_in_fram.GAP_APPEARE = APPEARANCE;
    }
    PRINT("GAP_APPEARE = %04x\n", data_in_fram.GAP_APPEARE);
    if (data_in_fram.device_name[0]) {
        name_point = data_in_fram.device_name;
    }
    // ! prepaer_ble_scan_data
    {
        int i = 0;
        int t = running_data.mac_offset < (sizeof(ble_name) / sizeof(ble_name[0])) ? running_data.mac_offset : 0;
        if (name_point == NULL) {
            name_point = ble_name[t];
        }
        memcpy(attDeviceName, name_point, min(sizeof(ble_name[0]), GAP_DEVICE_NAME_LEN));
        {
            i = 0;
#ifdef NAME_IN_SCAN
            {
                for (i = 0; i < min(sizeof(ble_name[0]), GAP_DEVICE_NAME_LEN); i++) {
                    if (name_point[i])
                        scanRspData__[i + 2] = name_point[i];
                    else
                        break;
                }
                i++;
                scanRspData__[0] = i;
                scanRspData__[1] = GAP_ADTYPE_LOCAL_NAME_COMPLETE;
                i++;
                if (i >= MAX_SCAN_RES_LEN - sizeof(exter_scan_data)) {
                    i                = MAX_SCAN_RES_LEN - sizeof(exter_scan_data);
                    scanRspData__[0] = i - 1;
                    scanRspData__[1] = GAP_ADTYPE_LOCAL_NAME_SHORT;
                }
            }
#endif
            memcpy(scanRspData__ + i,
                   exter_scan_data,
                   min(min(MAX_SCAN_RES_LEN - sizeof(exter_scan_data), MAX_SCAN_RES_LEN - i), sizeof(exter_scan_data)));
            scanRspData__len = i + sizeof(exter_scan_data);
            // PRINT("scan LEN%d \n", scanRspData__len);
        }
        {
            i = 0;
#ifdef NAME_IN_ADV
            {
                for (i = 0; i < min(sizeof(ble_name[0]), GAP_DEVICE_NAME_LEN); i++) {
                    if (name_point[i])
                        advertData__[i + 2] = name_point[i];
                    else
                        break;
                }
                i++;
                advertData__[0] = i;
                advertData__[1] = GAP_ADTYPE_LOCAL_NAME_COMPLETE;
                i++;
                if (i >= MAX_SCAN_RES_LEN - sizeof(exter_advertData)) {
                    i               = MAX_SCAN_RES_LEN - sizeof(exter_advertData);
                    advertData__[0] = i - 1;
                    advertData__[1] = GAP_ADTYPE_LOCAL_NAME_SHORT;
                }
            }
#endif
            memcpy(advertData__ + i,
                   exter_advertData,
                   min(min(MAX_SCAN_RES_LEN - sizeof(exter_advertData), MAX_SCAN_RES_LEN - i),
                       sizeof(exter_advertData)));
            advertData__len = i + sizeof(exter_advertData);
            // PRINT("adv LEN%d \n", advertData__len);
        }
        // for (int i = 0; i < scanRspData__len; i++)
        //     PRINT("%02x ", scanRspData__[i]);
        // PRINT("\n");
        // for (int i = 0; i < advertData__len; i++)
        //     PRINT("%02x ", advertData__[i]);
        // PRINT("\n");
    }

    uint8_t     i;
    bleConfig_t cfg;
    if (tmos_memcmp(VER_LIB, VER_FILE, strlen(VER_FILE)) == FALSE) {
        PRINT("head file error...\n");
        while (1)
            ;
    }
    SysTick_Config(SysTick_LOAD_RELOAD_Msk);
    PFIC_DisableIRQ(SysTick_IRQn);

    tmos_memset(&cfg, 0, sizeof(bleConfig_t));
    cfg.MEMAddr    = (uint32_t) MEM_BUF;
    cfg.MEMLen     = (uint32_t) BLE_MEMHEAP_SIZE;
    cfg.BufMaxLen  = (uint32_t) BLE_BUFF_MAX_LEN;
    cfg.BufNumber  = (uint32_t) BLE_BUFF_NUM;
    cfg.TxNumEvent = (uint32_t) BLE_TX_NUM_EVENT;
    cfg.TxPower    = (uint32_t) BLE_TX_POWER;
#if (defined(BLE_SNV)) && (BLE_SNV == TRUE)
    cfg.SNVAddr      = (uint32_t) BLE_SNV_ADDR - running_data.mac_offset * 256;
    cfg.readFlashCB  = Lib_Read_Flash;
    cfg.writeFlashCB = Lib_Write_Flash;
    cfg.SNVBlock     = 256;
    cfg.SNVNum       = 1;
#endif
#if (CLK_OSC32K)
    cfg.SelRTCClock = (uint32_t) CLK_OSC32K;
#endif
    cfg.ConnectNumber = (PERIPHERAL_MAX_CONNECTION & 3) | (CENTRAL_MAX_CONNECTION << 2);
    cfg.srandCB       = SYS_GetSysTickCnt;
#if (defined TEM_SAMPLE) && (TEM_SAMPLE == TRUE)
    cfg.tsCB = HAL_GetInterTempValue; // 根据温度变化校准RF和内部RC( 大于7摄氏度 )
#if (CLK_OSC32K)
    cfg.rcCB = Lib_Calibration_LSI; // 内部32K时钟校准
#endif
#endif
#if (defined(HAL_SLEEP)) && (HAL_SLEEP == TRUE)
    cfg.WakeUpTime = WAKE_UP_RTC_MAX_TIME;
    cfg.sleepCB    = CH58X_LowPower; // 启用睡眠
#endif
#if defined(BLE_MAC)
    uint8_t localMacAddr[6];
    {
        GetMACAddress(localMacAddr);
        localMacAddr[3] += running_data.mac_offset;
        // PRINT("%d\n", running_data.mac_offset);
        // tmos_memcpy(MacAddr, localMacAddr, 6);
        PRINT("MAC address:");
        for (i = 0; i < 6; i++)
            if (i == 3)
                PRINT("%02x[+%1d] ", localMacAddr[i], running_data.mac_offset);
            else
                PRINT("%02x ", localMacAddr[i]);
        PRINT("\n");
    }

    for (i = 0; i < 6; i++) {
        cfg.MacAddr[i] = localMacAddr[i];
    }
#else
#error "NO MAC"
    {
        uint8_t MacAddr[6];
        FLASH_GetMACAddress(MacAddr);
        for (i = 0; i < 6; i++) {
            cfg.MacAddr[i] = MacAddr[i]; // Use chip mac address
        }
    }
#endif

    if (!cfg.MEMAddr || cfg.MEMLen < 4 * 1024) {
        while (1)
            ;
    }
    i = BLE_LibInit(&cfg);
    if (i) {
        PRINT("LIB init error code: %x ...\n", i);
        while (1)
            ;
    }
}
