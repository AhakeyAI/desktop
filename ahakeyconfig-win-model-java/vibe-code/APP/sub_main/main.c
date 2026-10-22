#include "main.h"
#include "command_solve.h"
#include "img_cgr.h"
#include "pic.h"
#include "w25qxx.h"

const uint8_t  usb_name[]   = {0x4B, 0x6D, 0xD5, 0x8B};
tmosTaskID     mTaskID      = INVALID_TASK_ID;
data_in_fram_s data_in_fram = {0};
running_data_s running_data;

tmosEvents    MCT_ProcessEvent(tmosTaskID task_id, tmosEvents events);
const uint8_t defult_key_f18[]       = {0x73, 1, 0x6d};
const uint8_t defult_key_enter[]     = {0x73, 1, HID_KEYBOARD_RETURN};
const uint8_t defult_key_backspace[] = {0x73, 1, HID_KEYBOARD_DELETE};
const uint8_t defult_key_escape[]    = {0x73, 1, HID_KEYBOARD_ESCAPE};
const uint8_t defult_key_claude_no[] = {0x74,
                                        12,
                                        DOWN_KEY,
                                        HID_KEYBOARD_DOWN_ARROW,
                                        UP_KEY,
                                        HID_KEYBOARD_DOWN_ARROW,
                                        DOWN_KEY,
                                        HID_KEYBOARD_DOWN_ARROW,
                                        UP_KEY,
                                        HID_KEYBOARD_DOWN_ARROW,
                                        DOWN_KEY,
                                        HID_KEYBOARD_RETURN,
                                        UP_KEY,
                                        HID_KEYBOARD_RETURN};
const char *defult_name[USER_MODE_COUNT][USER_KEY_COUNT] = {
    {"Record", "Yes", "No", "Backspace"},
    {"Record", "Accept", "Reject", "Backspace"},
    {"Record", "Accept", "Reject", "Backspace"},
    {"N/A", "N/A", "N/A", "N/A"},
};
key_bund_s    key_bund;

#define WS2812_DEFAULT_BRIGHTNESS 35
#define WS2812_LEGACY_DEFAULT_BRIGHTNESS 20
#define WS2812_MAX_BRIGHTNESS     100

void set_mode(uint8_t mode);

static const uint8_t default_ai_light_mode[CL_STATE_COUNT] = {
    WS2812_WARNING_BLINK, // Notification
    WS2812_BREATHING,     // PermissionRequest
    WS2812_SINGLE_MOVE,   // PostToolUse
    WS2812_SINGLE_MOVE,   // PreToolUse
    WS2812_SINGLE_MOVE,   // SessionStart
    WS2812_MIDDLE_LIGHT,  // Stop
    WS2812_MIDDLE_LIGHT,  // TaskCompleted
    WS2812_TYPING_RIPPLE, // UserPromptSubmit
    WS2812_OFF,           // SessionEnd
};

static const uint8_t legacy_ai_light_mode[CL_STATE_COUNT] = {
    WS2812_WARNING_BLINK,
    WS2812_APPROVAL_WAIT,
    WS2812_COMET,
    WS2812_BLUE_THINKING,
    WS2812_PULSE_CENTER,
    WS2812_SCAN_BAR,
    WS2812_SUCCESS_SWEEP,
    WS2812_TYPING_RIPPLE,
    WS2812_OFF,
};

static void init_default_ai_light_modes(void)
{
    for (uint8_t mode = 0; mode < USER_MODE_COUNT; mode++)
        memcpy(key_bund.ai_light_mode[mode], default_ai_light_mode, sizeof(default_ai_light_mode));
}

static uint8_t ai_light_mode_matches(const uint8_t *table, const uint8_t *preset)
{
    return memcmp(table, preset, CL_STATE_COUNT) == 0;
}

static uint8_t keyboard_hid_ready(void)
{
    return running_data.hid_input_ready || usb_is_ready();
}

static void sanitize_key_bund_data(void)
{
    for (uint8_t mode = 0; mode < USER_MODE_COUNT; mode++) {
        for (uint8_t key = 0; key < USER_KEY_COUNT; key++) {
            if (key_bund.user_key_bind[mode][key][0] == 0xFF)
                memset(key_bund.user_key_bind[mode][key], 0, sizeof(key_bund.user_key_bind[mode][key]));
            if (key_bund.user_key_desc[mode][key][0] == 0xFF)
                memset(key_bund.user_key_desc[mode][key], 0, sizeof(key_bund.user_key_desc[mode][key]));
        }
        for (uint8_t i = 0; i < 3; i++) {
            if (key_bund.pic[mode][i] == 0xFFFF)
                key_bund.pic[mode][i] = 0;
        }
        uint8_t invalid_count = 0;
        uint8_t off_count     = 0;
        for (uint8_t state = 0; state < CL_STATE_COUNT; state++) {
            if (key_bund.ai_light_mode[mode][state] == 0xFF || key_bund.ai_light_mode[mode][state] > WS2812_APPROVAL_WAIT)
                invalid_count++;
            if (key_bund.ai_light_mode[mode][state] == WS2812_OFF)
                off_count++;
        }
        if (invalid_count == CL_STATE_COUNT || off_count == CL_STATE_COUNT ||
            ai_light_mode_matches(key_bund.ai_light_mode[mode], legacy_ai_light_mode)) {
            memcpy(key_bund.ai_light_mode[mode], default_ai_light_mode, sizeof(default_ai_light_mode));
        } else {
            for (uint8_t state = 0; state < CL_STATE_COUNT; state++) {
                if (key_bund.ai_light_mode[mode][state] == 0xFF || key_bund.ai_light_mode[mode][state] > WS2812_APPROVAL_WAIT)
                    key_bund.ai_light_mode[mode][state] = default_ai_light_mode[state];
            }
        }
    }
    if (key_bund.ws2812_brightness == 0 || key_bund.ws2812_brightness == 0xFF ||
        key_bund.ws2812_brightness == WS2812_LEGACY_DEFAULT_BRIGHTNESS || key_bund.ws2812_brightness > WS2812_MAX_BRIGHTNESS)
        key_bund.ws2812_brightness = WS2812_DEFAULT_BRIGHTNESS;
}

static void copy_default_key(uint8_t mode, uint8_t key, const uint8_t *data, uint8_t len)
{
    memcpy(key_bund.user_key_bind[mode][key], data, len);
    memcpy(key_bund.user_key_desc[mode][key], defult_name[mode][key], strlen(defult_name[mode][key]));
}

static void init_default_key_bund(void)
{
    memset(&key_bund, 0, sizeof(key_bund));
    key_bund.ws2812_brightness = WS2812_DEFAULT_BRIGHTNESS;
    init_default_ai_light_modes();

    copy_default_key(0, 0, defult_key_f18, sizeof(defult_key_f18));
    copy_default_key(0, 1, defult_key_enter, sizeof(defult_key_enter));
    copy_default_key(0, 2, defult_key_claude_no, sizeof(defult_key_claude_no));
    copy_default_key(0, 3, defult_key_backspace, sizeof(defult_key_backspace));
    copy_default_key(1, 0, defult_key_f18, sizeof(defult_key_f18));
    copy_default_key(1, 1, defult_key_enter, sizeof(defult_key_enter));
    copy_default_key(1, 2, defult_key_backspace, sizeof(defult_key_backspace));
    copy_default_key(1, 3, defult_key_backspace, sizeof(defult_key_backspace));

    copy_default_key(2, 0, defult_key_f18, sizeof(defult_key_f18));
    copy_default_key(2, 1, defult_key_enter, sizeof(defult_key_enter));
    copy_default_key(2, 2, defult_key_escape, sizeof(defult_key_escape));
    copy_default_key(2, 3, defult_key_backspace, sizeof(defult_key_backspace));
}

static void reset_ble_identity(void)
{
    PRINT("BLE reset: erase bonds and enter pairing blink\n");
    tmos_stop_task(mTaskID, MCT_BT_RESET_HOLD_CHECK);
    tmos_stop_task(mTaskID, MCT_POWER_OFF_buzz);
    running_data.power_off_prompt_mode  = 0;
    running_data.bt_reset_pairing_mode  = 1;
    running_data.bt_connect_stat        = 0;
    running_data.hid_input_ready        = 0;
    running_data.ws2812_mode_ignore_flag = 0;
    running_data.ws2812_mode             = WS2812_OFF;
    running_data.ws2812_single_color     = 0x102080;
    running_data.mac_offset              = (running_data.mac_offset + 1) % BLE_IDENTITY_COUNT;
    memset(data_in_fram.device_name, 0, sizeof(data_in_fram.device_name));
    set_mode(0);
    running_data.bt_reset_pairing_mode = 1;
    for (int i = 0; i < LED_NUM; i++) {
        ws2812_list[i].hex = 0x80102080;
        update_bit(i);
    }
    HidDev_SetParameter(HIDDEV_ERASE_ALLBONDS, 0, NULL);
    save_all_data_to_fram();
    DelayMs(800);
    power_reset(0);
}

static void prepare_power_shutdown(void)
{
    running_data.power_shutdown_mode     = 1;
    running_data.power_off_prompt_mode   = 0;
    running_data.bt_reset_pairing_mode   = 0;
    running_data.ws2812_mode_ignore_flag = 1;
    running_data.ws2812_mode             = WS2812_OFF;
    running_data.charge_flag             = 0;
    buzzerStop();
    tmos_stop_task(mTaskID, MCT_PIC_DISPLAY);
    tmos_stop_task(mTaskID, MCT_WS2812_MODE);
    tmos_stop_task(mTaskID, MCT_POWER_OFF_TIME_CHECK);
    tmos_stop_task(mTaskID, MCT_music_ticks);
    ws2812_state.global_light = 1;
    for (int pass = 0; pass < 3; pass++) {
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex = 0;
            update_bit(i);
        }
        update_once();
        DelayMs(3);
    }
    update_once();
    DelayMs(3);
    change_2812_state(1);
    led_set_bk(0);
    LCD_CS_RESET;
    IPS_Clear(BLACK);
    LCD_CS_SET;
}


void sub_main_1(void)
{
    //  ! read last shutdown data
    //  --------------------------------------------------------------------
    // ps("\nR8_RESET_STATUS 0x%02X\n", R8_RESET_STATUS);

    // if ((R8_RESET_STATUS & RB_RESET_FLAG) == RST_FLAG_RPOR)
    // {
    //     ps("\nRST_FLAG_RPOR, POWER OFF");

    //     // POWER_OFF;
    // }
    //  ! power en
    //  --------------------------------------------------------------------
    GPIOA_SetBits(GPIO_Pin_11);
    GPIOA_ModeCfg(GPIO_Pin_11, GPIO_ModeOut_PP_5mA);
    fram_init();
    fram_read(0, &data_in_fram, sizeof(data_in_fram));
    running_data.mac_offset = data_in_fram._mac_offset;
    if (running_data.mac_offset >= BLE_IDENTITY_COUNT)
        running_data.mac_offset = 0;
    running_data.mode_data  = data_in_fram._mode_data;
    uint32_t tmp            = 0;
    EEPROM_READ(KEY_BUND_EEPROM_ADDR, &tmp, sizeof(tmp));
    if (tmp == 0xFFFFFFFF) {
        init_default_key_bund();
    } else {
        EEPROM_READ(KEY_BUND_EEPROM_ADDR, &key_bund, sizeof(key_bund));
        sanitize_key_bund_data();
    }
    //  ! devices_init
    //  --------------------------------------------------------------------
    // mouse_init();
    keyboard_init();
    // touch_init();
    // custom_init();
    void init_desp(void);
    init_desp();
    // USB HID is experimental on this hardware revision. Keep it disabled by
    // default so the keyboard can boot normally when USB D+/D- is not usable.
    // usb_set_name(usb_name, sizeof(usb_name));
    // usb_set_desc(keyboard_state.report_pointer, keyboard_state.desp_lenth);
    // usb_hid_kbd_init();

    // ! charging_detect
    // --------------------------------------------------------------------
    GPIOA_SetBits(GPIO_Pin_13);
    GPIOA_ModeCfg(GPIO_Pin_13, GPIO_ModeIN_PU);
    GPIOA_ITModeCfg(GPIO_Pin_13, GPIO_ITMode_FallEdge);
    PFIC_EnableIRQ(GPIO_A_IRQn);
    running_data.charge_flag = IS_CHAEGING;
    // ! usb_detect
    // --------------------------------------------------------------------
    GPIOA_SetBits(GPIO_Pin_14);
    GPIOA_ModeCfg(GPIO_Pin_14, GPIO_ModeIN_PD);
#define HAVE_VUSB !!GPIOA_ReadPortPin(GPIO_Pin_14)
    running_data.usb_is_connected = HAVE_VUSB;
    running_data.usb_hid_started  = 0;
    refresh_power_off_timeout();
    // ! BACK_LIGHT
    // --------------------------------------------------------------------
    GPIOPinRemap(DISABLE, RB_PIN_TMR0);
    GPIOA_ResetBits(GPIO_Pin_9);
    GPIOA_ModeCfg(GPIO_Pin_9, GPIO_ModeOut_PP_5mA);
    TMR0_PWMInit(High_Level, PWM_Times_1);
    TMR0_PWMCycleCfg(PWMCycleCfg);

    TMR0_Disable();
    TMR0_PWMActDataWidth(PWMCycleCfg - 1);
    TMR0_Enable();
    TMR0_PWMEnable();
    led_set_mode(0, SMOOTH_ALL, 0);
    led_set_bk(20);
}
void sw_state_change(uint8_t new)
{
    refresh_power_off_timeout();
    running_data.sw_state = new;
    command_return_state();
    // 0 up, 1 down 2 mid
    PRINT("sw to %d\n", new);
    update_claude_ws2812();
}
void read_sw_state(void)
{
    static int8_t last_state = -1;
    uint8_t       ret        = 0;
    GPIOB_SetBits(GPIO_Pin_5);
    ret += !!GPIOB_ReadPortPin(GPIO_Pin_4);
    GPIOB_ResetBits(GPIO_Pin_5);
    ret += !!GPIOB_ReadPortPin(GPIO_Pin_4);
    if (last_state != ret) {
        last_state = ret;
        sw_state_change(ret);
    }
}
void refresh_power_off_timeout(void)
{
    running_data.power_off_timeout = AUTO_POWER_OFF_TIMEOUT_SECONDS;
}
void sub_main(void)
{
    mTaskID = TMOS_ProcessEventRegister(MCT_ProcessEvent);
    tmos_start_task(mTaskID, MCT_light_control, MS1_TO_SYSTEM_TIME(50));
    tmos_start_task(mTaskID, MCT_test_event, MS1_TO_SYSTEM_TIME(100));
    tmos_start_task(mTaskID, MCT_POWER_OFF_TIME_CHECK, MS1_TO_SYSTEM_TIME(999));

    // ! POWER ON --------------------------------------------------------------------
    LL_GPIO_SetOutputPin(GPIOA, GPIO_Pin_12);
    GPIO_SINGLE_INIT(GPIOA, GPIO_Pin_12, GPIO_ModeOut_PP_5mA);
    // ! buzz --------------------------------------------------------------------
    // buzzerDriverInit();
    // buzzerSetNewFrequency(0);
    // tmos_start_task(mTaskID, MCT_music_ticks, MS1_TO_SYSTEM_TIME(20));
    // start_music(0);
    // ! SW --------------------------------------------------------------------
    GPIOB_ModeCfg(GPIO_Pin_5, GPIO_ModeOut_PP_5mA);
    GPIOB_ModeCfg(GPIO_Pin_4, GPIO_Mode_IPU);
    // ! key --------------------------------------------------------------------
    GPIOB_ModeCfg(GPIO_Pin_0 | GPIO_Pin_1 | GPIO_Pin_2 | GPIO_Pin_3, GPIO_ModeIN_PU);
    GPIOA_ModeCfg(GPIO_Pin_8, GPIO_ModeIN_PU);
    key_scan();
    my_button_init();
    tmos_start_task(mTaskID, MCT_key_scan, MS1_TO_SYSTEM_TIME(98));
    // ! hid_dev
    // --------------------------------------------------------------------
    // tmos_start_task(mTaskID, MCT_event_update, MS1_TO_SYSTEM_TIME(56));
    // ps("%s, %d\n", __FILE__, __LINE__);
    // ! adc --------------------------------------------------------------------
    BP_ADC_Init();
    uint16_t rawa_adc  = read_vbat_adc();
    running_data.v_bat = __Map(rawa_adc, 0, 2888, 0, 329);
    int p              = __Map(running_data.v_bat, 320, 415, 0, 100);
    __LimitValue(p, 0, 100);
    running_data.power_persent = p;
    tmos_start_task(mTaskID, MCT_adc_measure, MS1_TO_SYSTEM_TIME(50));
    // ! tim5_ch3_ll_dma_init  --------------------------------------------------------------------
    // ws2812_power_pin
    // GPIO_SINGLE_INIT(GPIOB, NO_PIN, GPIO_ModeOut_PP_5mA);
    WS2812_POWER_OFF;
    GPIOAGPPCfg(DISABLE, RB_PIN_XT32K_IE);
    tim5_ch3_ll_dma_init();
    change_2812_state(2);
    tmos_start_task(mTaskID, MCT_WS2812_MODE, 100);
    // ! GD25Q256 1 --------------------------------------------------------------------
    GPIOB_SetBits(GPIO_Pin_12); // cs
    GPIOB_ModeCfg(GPIO_Pin_12, GPIO_ModeOut_PP_5mA);
    command_data_buf_init();
    // ! ips --------------------------------------------------------------------
    GPIOB_SetBits(GPIO_Pin_17); // cs
    GPIOB_ModeCfg(GPIO_Pin_17, GPIO_ModeOut_PP_5mA);
    GPIOB_SetBits(GPIO_Pin_9); // RST
    GPIOB_ModeCfg(GPIO_Pin_9, GPIO_ModeOut_PP_5mA);
    GPIOB_SetBits(GPIO_Pin_16); // RST
    GPIOB_ModeCfg(GPIO_Pin_16, GPIO_ModeOut_PP_5mA);

    GPIOPinRemap(ENABLE, RB_PIN_SPI0);
    GPIOB_ModeCfg(GPIO_Pin_13 | GPIO_Pin_14, GPIO_ModeOut_PP_5mA);
    GPIOB_ModeCfg(GPIO_Pin_15, GPIO_ModeIN_PD);
    SPI0_MasterDefInit();
    SPI0_CLKCfg(2);

    RST_RESET;
    DelayMs(5);
    RST_SET;
    DelayMs(1);
    LCD_CS_RESET;
    IPS_Init();
    IPS_Clear(CYAN);
    if (running_data.mode_data >= USER_MODE_COUNT)
        running_data.mode_data = 0;
    set_mode(running_data.mode_data);
    LCD_CS_SET;
    // ! GD25Q256 2 --------------------------------------------------------------------
    W25QXX_Init();
    {
        char *p = nor_flash_get_manufacturary_name();
        if (p) {
            PRINT("flash %s\n", p);
        } else {
            PRINT("unknown flash %02x\n", NOR_FLASH_GET_MANUFACTURARID(nor_flash_id));
        }
        uint32_t size = nor_flash_get_size();
        PRINT("flash size %d Mbytes\n", size / 1024 / 1024);
        PRINT("max_pic_size %d\n", nor_flash_get_size() / 7 / 4096);
    }
    uint32_t tmp = 0;
    EEPROM_READ(KEY_BUND_EEPROM_ADDR, &tmp, sizeof(tmp));
    if (tmp == 0xFFFFFFFF) {
        for (int i = 0; i < ARRAY_SIZE(pic_dp); i++) {
            for (int j = i * 7; j < i * 7 + 7; j++) {
                uint16_t sector = j;
                PRINT("size %d, address %p, se %d\n", 4096, sector * 4096, sector);
                W25QXX_Erase_Sector(sector);
            }
            uint32_t add    = i * 4096 * 7;
            uint32_t remain = 25600;
            uint32_t send   = 0;
            while (remain > 0) {
                int len = remain > 1024 ? 1024 : remain;
                W25QXX_Write_NoCheck(&(pic_dp[i][send]), add, len);
                add += len;
                send += len;
                remain -= len;
            }
        }
        key_bund.pic[0][0] = PIC_MODE0_START;
        key_bund.pic[0][1] = PIC_MODE0_COUNT;
        key_bund.pic[0][2] = 100;
        key_bund.pic[1][0] = PIC_MODE1_START;
        key_bund.pic[1][1] = PIC_MODE1_COUNT;
        key_bund.pic[1][2] = 100;
        key_bund.pic[2][0] = PIC_MODE2_START;
        key_bund.pic[2][1] = PIC_MODE2_COUNT;
        key_bund.pic[2][2] = 100;
        save_key_bound_data();
    }
    tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(100));
    running_data.ws2812_mode             = WS2812_OFF;
    running_data.ws2812_single_color     = 0x0102080;
    running_data.have_update_custom_data = 0;
    running_data.claude_state            = CL_SessionEnd; // defaule CL_SessionEnd
}
tmosEvents MCT_ProcessEvent(tmosTaskID task_id, tmosEvents events)
{
    uint8_t *msgPtr;
    char     txt[18];
    if (events & SYS_EVENT_MSG) {
        msgPtr = tmos_msg_receive(task_id);
        if (msgPtr) {
            /* De-allocate */
            tmos_msg_deallocate(msgPtr);
        }
        return events ^ SYS_EVENT_MSG;
    }
    if (events & MCT_test_event) {
        if (running_data.bt_connect_stat == 2 && !running_data.hid_input_ready) {
            uint8_t empty_key_report[HID_KEYBOARD_IN_RPT_LEN] = {0};
            if (HidDev_Report(0, HID_REPORT_TYPE_INPUT, sizeof(empty_key_report), empty_key_report) == SUCCESS) {
                running_data.hid_input_ready = 1;
            } else {
                tmos_start_task(mTaskID, MCT_test_event, MS1_TO_SYSTEM_TIME(500));
            }
        }
        return events ^ MCT_test_event;
    }
    if (events & MCT_light_control) {
        tmos_start_task(mTaskID, MCT_light_control, MS1_TO_SYSTEM_TIME(10));
        led_smooth_change_handle();
        return events ^ MCT_light_control;
    }
    if (events & MCT_key_scan) {
        static uint8_t t = 0;
        if (t++ > 5) {
            t = 0;
            read_sw_state();
        }
        key_scan();
        send_keyboard_data();
        button_ticks();
        tmos_start_task(mTaskID, MCT_key_scan, MS1_TO_SYSTEM_TIME(3));

        return events ^ MCT_key_scan;
    }
    if (events & MCT_adc_measure) {
        tmos_start_task(mTaskID, MCT_adc_measure, MS1_TO_SYSTEM_TIME(60 * 1000));
        uint16_t rawa_adc  = read_vbat_adc();
        running_data.v_bat = __Map(rawa_adc, 0, 2888, 0, 329);
        int p              = __Map(running_data.v_bat, 320, 415, 0, 100);
        __LimitValue(p, 0, 100);
        running_data.power_persent = p;
        __LimitValue(running_data.power_persent, 0, 100);
        ps("adc %d\n", rawa_adc);
        ps("%% %d\n", running_data.power_persent);
        // if (tx_tmp <= (int)(__Map(3.4f, 0, 3.07f, 0, 3033)))
        //     running_data.low_power_flag = 1;
        ws2812_state.global_light = key_bund.ws2812_brightness;
        if (running_data.v_bat < 350 && running_data.v_bat > 325) {
            start_music(2);
        }
        if (running_data.v_bat < 325 && running_data.v_bat > 50) {
            ps("low_power\n");
            // POWER_OFF;
        }
        ps("vbat = ");
        ps("%1d.%02dV", running_data.v_bat / 100, running_data.v_bat % 100);
        ps("\n");
        return events ^ MCT_adc_measure;
    }
    if (events & MCT_music_ticks) {
        tmos_start_task(mTaskID, MCT_music_ticks, MS1_TO_SYSTEM_TIME(20));
        music_ticks();
        return events ^ MCT_music_ticks;
    }
    if (events & MCT_POWER_OFF_TIME_CHECK) {
        tmos_start_task(mTaskID, MCT_POWER_OFF_TIME_CHECK, MS1_TO_SYSTEM_TIME(1000));
        ps("pfc %2d:%02ds\n", running_data.power_off_timeout / 60, running_data.power_off_timeout % 60);
        static uint8_t last_usb_ready = 0;
        static uint8_t last_usb_debug = 0xff;
        static uint8_t last_charge    = 0xff;
        uint8_t        usb_now        = HAVE_VUSB;
        if (!usb_now && running_data.usb_hid_started) {
            usb_disconnect();
        }
        if (usb_now && !running_data.usb_hid_started) {
            running_data.usb_hid_started = 1;
            usb_set_name(usb_name, sizeof(usb_name));
            usb_set_desc(keyboard_state.report_pointer, keyboard_state.desp_lenth);
            usb_hid_kbd_init();
        }
        uint8_t        usb_ready_now  = usb_is_ready();
        uint8_t        usb_debug_now  = usb_debug_state();
        uint8_t        charge_now     = IS_CHAEGING;
        if (last_charge == 0xff)
            last_charge = charge_now;
        if (running_data.usb_is_connected != usb_now || last_usb_ready != usb_ready_now || last_usb_debug != usb_debug_now ||
            last_charge != charge_now) {
            char usb_txt[4];
            running_data.usb_is_connected = usb_now;
            last_usb_ready                 = usb_ready_now;
            last_usb_debug                 = usb_debug_now;
            last_charge                    = charge_now;
            running_data.charge_flag       = 0;
            set_mode(running_data.mode_data);
            LCD_CS_RESET;
            if (usb_is_ready()) {
                sprintf(usb_txt, "HID");
            } else {
                sprintf(usb_txt, "%s", running_data.hid_input_ready ? "OK" : "ing");
            }
            BACK_COLOR = CYAN;
            IPS_ShowString(128, 0, "   ", MAGENTA);
            IPS_ShowString(152 - 8 * strlen(usb_txt), 0, usb_txt, MAGENTA);
        }
        if (running_data.usb_is_connected == 0) {
            if (running_data.power_off_timeout) {
                running_data.power_off_timeout--;
            } else {
                tmos_set_event(mTaskID, MCT_POWER_OFF_buzz);
            }
        }
        return events ^ MCT_POWER_OFF_TIME_CHECK;
    }
    if (events & MCT_BT_RESET_HOLD_CHECK) {
        if (key_read(4))
            tmos_set_event(mTaskID, MCT_BT_RESET);
        return events ^ MCT_BT_RESET_HOLD_CHECK;
    }
    if (events & MCT_BT_RESET) {
        reset_ble_identity();
        return events & ~(MCT_BT_RESET | MCT_START_POWER_OFF | MCT_POWER_OFF_buzz);
    }
    if (events & MCT_START_POWER_OFF) {
        start_music(3);
        running_data.power_off_prompt_mode = 1;
        running_data.ws2812_mode = 0xff;
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex = 0xA0800000;
        }
        tmos_stop_task(mTaskID, MCT_POWER_OFF_TIME_CHECK);
        return events ^ MCT_START_POWER_OFF;
    }
    if (events & MCT_POWER_OFF_buzz) {
        prepare_power_shutdown();
        POWER_OFF;
        return events ^ MCT_POWER_OFF_buzz;
    }
    if (events & MCT_WS2812_MODE) {
        tmos_start_task(mTaskID, MCT_WS2812_MODE, MS1_TO_SYSTEM_TIME(50));
        static uint8_t last_bt_stat = 1;
        static int8_t  prograss     = 0;
        static uint8_t bt_pair_tick = 0;
        if (last_bt_stat != running_data.bt_connect_stat && running_data.bt_connect_stat != 0) {
            last_bt_stat = running_data.bt_connect_stat;
            if (last_bt_stat == 2)
                prograss = 1;
            else if (last_bt_stat == 1)
                prograss = 19;
        }
        if (keyboard_hid_ready()) {
            running_data.bt_reset_pairing_mode = 0;
        }
        if (running_data.power_off_prompt_mode && !running_data.bt_reset_pairing_mode) {
            for (int i = 0; i < LED_NUM; i++) {
                ws2812_list[i].hex = 0xA0800000;
            }
        } else if (!keyboard_hid_ready()) {
            uint8_t on = (bt_pair_tick % 16) < 8;
            for (int i = 0; i < LED_NUM; i++) {
                if (on)
                    ws2812_list[i].hex = 0x80102080;
                else
                    ws2812_list[i].hex = 0x40000008;
            }
            bt_pair_tick++;
        } else if (prograss <= 0 || prograss >= 20) {
            if (running_data.ws2812_mode_ignore_flag == 0) {
                ws2812_display(running_data.ws2812_mode, running_data.ws2812_single_color);
            }
        } else {
            if (last_bt_stat == 2)
                prograss++;
            else
                prograss--;
            for (int i = 0; i < LED_NUM; i++) {
                if (i > prograss / 2)
                    ws2812_list[i].hex = 0;
                else
                    ws2812_list[i].hex = 0x50102050;
            }
        }
        for (int i = 0; i < LED_NUM; i++)
            update_bit(i);
        return events ^ MCT_WS2812_MODE;
    }
    if (events & MCT_COMMAND_TODO) {
        if (command_data && command_len > 0) {
            command_process(command_data, command_len);
            command_process_ok();
        }
        command_in_process = 0;
        return events ^ MCT_COMMAND_TODO;
    }
    if (events & MCT_DATA_TODO) {
        if (running_data.data_address < running_data.data_end_address) {
            if (0 < lwrb_get_full(&ble_data_lwrb)) {
                uint8_t *d         = lwrb_get_linear_block_read_address(&ble_data_lwrb);
                uint16_t read_len = lwrb_get_linear_block_read_length(&ble_data_lwrb);
                uint32_t remain   = running_data.data_end_address - running_data.data_address;
                uint16_t write_len = read_len > remain ? remain : read_len;
                if (write_len > 0) {
                    W25QXX_Write_NoCheck(d, running_data.data_address, write_len);
                    running_data.data_address += write_len;
                }
                lwrb_skip(&ble_data_lwrb, read_len);
                if (0 < lwrb_get_full(&ble_data_lwrb)) {
                    tmos_set_event(mTaskID, MCT_DATA_TODO);
                }
                if (running_data.data_address >= running_data.data_end_address) {
                    command_return(0x81, 0);
                    if (running_data.data_end_address % 4096 == 1024) {
                        running_data.pic_writing = 0;
                        tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(200));
                    }
                }
            }
        }
        return events ^ MCT_DATA_TODO;
    }
    if (events & MCT_PIC_DISPLAY) {
        if (running_data.power_shutdown_mode) {
            return events ^ MCT_PIC_DISPLAY;
        }
        if (running_data.charge_flag) {
            running_data.charge_flag = 0;
            LCD_CS_RESET;
            set_mode(running_data.mode_data);
            LCD_CS_SET;
            tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(1000));
            return events ^ MCT_PIC_DISPLAY;
        }
        if (running_data.pic_writing) {
            return events ^ MCT_PIC_DISPLAY;
        }
        if (!running_data.edit_flag && running_data.mode_data < USER_MODE_COUNT && key_bund.pic[running_data.mode_data][1] > 0) {
            if (running_data.pic_index >= key_bund.pic[running_data.mode_data][1])
                running_data.pic_index = 0;
            __attribute__((aligned(4))) uint8_t tmp_d[3658];

            uint16_t remain  = 160 * 80 * 2;
            uint32_t address = (key_bund.pic[running_data.mode_data][0] + running_data.pic_index) * 4096 * 7;
            LCD_CS_RESET;
            IPS_Addr_Set(0, 0, IPS_W - 1, IPS_H - 1);
            LCD_CS_SET;
            while (remain > 0) {
                uint16_t this_len = remain > 3658 ? 3658 : remain;
                W25QXX_Read_start(address);
                SPI0_MasterDMARecv(tmp_d, this_len);
                W25QXX_Read_end();
                LCD_CS_RESET;
                SPI0_MasterDMATrans(tmp_d, this_len);
                LCD_CS_SET;
                remain -= this_len;
                address += this_len;
            }
            running_data.pic_index++;
            if (key_bund.pic[running_data.mode_data][1] > 1) {
                if (key_bund.pic[running_data.mode_data][2] > 0) {
                    tmos_start_task(mTaskID,
                                    MCT_PIC_DISPLAY,
                                    MS1_TO_SYSTEM_TIME(key_bund.pic[running_data.mode_data][2]));
                }
            }
        }
        return events ^ MCT_PIC_DISPLAY;
    }
    if (events & MCT_MODE_END) {
        running_data.edit_flag               = 0;
        running_data.ws2812_mode_ignore_flag = 0;
        tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
        update_claude_ws2812();
        return events ^ MCT_MODE_END;
    }

    return 0;
}

void update_claude_ws2812(void)
{
    if (running_data.mode_data >= USER_MODE_COUNT || running_data.claude_state >= CL_STATE_COUNT)
        return;

    running_data.ws2812_mode_ignore_flag = 0;
    running_data.ws2812_single_color     = 0x102080;

    uint8_t mode = key_bund.ai_light_mode[running_data.mode_data][running_data.claude_state];
    if (mode > WS2812_APPROVAL_WAIT)
        mode = default_ai_light_mode[running_data.claude_state];
    running_data.ws2812_mode = (enum ws2812_mode_e) mode;
}
__INTERRUPT
__HIGH_CODE
void GPIOA_IRQHandler(void)
{
    GPIOA_ClearITFlagBit(GPIO_Pin_13);
    if (running_data.power_shutdown_mode)
        return;
    PRINT("cgr\n");
    running_data.charge_flag = 1;
    tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(0));
}
