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
const uint8_t defult_key_0_0[] = {0x73, 1, 0x6d};
const uint8_t defult_key_0_1[] = {0x73, 1, HID_KEYBOARD_RETURN};
const uint8_t defult_key_0_2[] = {0x74,
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
const char   *defult_name[]    = {"Record", "Accept", "Reject", "Enter"};
key_bund_s    key_bund;

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
    running_data.mode_data  = data_in_fram._mode_data;
    uint32_t tmp            = 0;
    EEPROM_READ(EEPROM_BLOCK_SIZE * 4 + 1024, &tmp, sizeof(tmp));
    if (tmp == 0xFFFFFFFF) {
        memset(&key_bund, 0, sizeof(key_bund));
        memcpy(key_bund.user_key_bind[0][0], defult_key_0_0, sizeof(defult_key_0_0));
        memcpy(key_bund.user_key_bind[0][1], defult_key_0_1, sizeof(defult_key_0_1));
        memcpy(key_bund.user_key_bind[0][2], defult_key_0_2, sizeof(defult_key_0_2));
        memcpy(key_bund.user_key_bind[0][3], defult_key_0_1, sizeof(defult_key_0_1));
        for (int i = 0; i < 4; i++)
            memcpy(key_bund.user_key_desc[0][i], defult_name[i], strlen(defult_name[i]));
    } else {
        EEPROM_READ(EEPROM_BLOCK_SIZE * 4 + 1024, &key_bund, sizeof(key_bund));
    }
    //  ! devices_init
    //  --------------------------------------------------------------------
    // mouse_init();
    keyboard_init();
    // touch_init();
    // custom_init();
    void init_desp(void);
    init_desp();
    usb_set_name(usb_name, sizeof(usb_name));
    usb_set_desc(keyboard_state.report_pointer, keyboard_state.desp_lenth);
    usb_hid_kbd_init();

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
    running_data.power_off_timeout = 60 * 60;
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
    EEPROM_READ(EEPROM_BLOCK_SIZE * 4 + 1024, &tmp, sizeof(tmp));
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
        key_bund.pic[0][0] = 0;
        key_bund.pic[0][1] = ARRAY_SIZE(pic_dp);
        key_bund.pic[0][2] = 100;
        save_key_bound_data();
    }
    tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(100));
    running_data.ws2812_mode             = WS2812_OFF;
    running_data.ws2812_single_color     = 0x020a0ff;
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
        static int index_t_ = 0;
        tmos_start_task(mTaskID, MCT_test_event, MS1_TO_SYSTEM_TIME(10));
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
        if (running_data.v_bat > 450)
            ws2812_state.global_light = 90;
        else
            ws2812_state.global_light = 70;
        if (running_data.v_bat < 350 && running_data.v_bat > 325) {
            start_music(2);
        }
        if (running_data.v_bat < 325 && running_data.v_bat > 50) {
            ps("low_power\n");
            // POWER_OFF;
        }
        if (running_data.v_bat > 440) {
            running_data.power_off_timeout += 60;
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
        if (running_data.usb_is_connected == 0) {
            if (running_data.power_off_timeout) {
                running_data.power_off_timeout--;
            } else {
                tmos_set_event(mTaskID, MCT_START_POWER_OFF);
            }
        }
        return events ^ MCT_POWER_OFF_TIME_CHECK;
    }
    if (events & MCT_START_POWER_OFF) {
        start_music(3);
        running_data.ws2812_mode = 0xff;
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex = 0xffff0000;
        }
        tmos_start_task(mTaskID, MCT_POWER_OFF_buzz, MS1_TO_SYSTEM_TIME(500));
        tmos_stop_task(mTaskID, MCT_POWER_OFF_TIME_CHECK);
        return events ^ MCT_START_POWER_OFF;
    }
    if (events & MCT_POWER_OFF_buzz) {
        buzzerStop();
        POWER_OFF;
        return events ^ MCT_POWER_OFF_buzz;
    }
    if (events & MCT_WS2812_MODE) {
        tmos_start_task(mTaskID, MCT_WS2812_MODE, MS1_TO_SYSTEM_TIME(50));
        static uint8_t last_bt_stat = 1;
        static int8_t  prograss     = 0;
        if (last_bt_stat != running_data.bt_connect_stat && running_data.bt_connect_stat != 0) {
            last_bt_stat = running_data.bt_connect_stat;
            if (last_bt_stat == 2)
                prograss = 1;
            else if (last_bt_stat == 1)
                prograss = 19;
        }
        if (prograss <= 0 || prograss >= 20) {
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
                    ws2812_list[i].hex = 0xf030e6; // #f030e6
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
                uint8_t *d   = lwrb_get_linear_block_read_address(&ble_data_lwrb);
                uint16_t len = lwrb_get_linear_block_read_length(&ble_data_lwrb);
                W25QXX_Write_NoCheck(d, running_data.data_address, len);
                lwrb_skip(&ble_data_lwrb, len);
                running_data.data_address += len;
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
        if (running_data.charge_flag) {
            running_data.charge_flag = 0;
            LCD_CS_RESET;
            IPS_Clear(BLACK);
            IPS_show_single_color_pic(gImage_cgr, 36, 11, 88, 58, GREEN, BLACK);
            LCD_CS_SET;
            tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(1000));
            return events ^ MCT_PIC_DISPLAY;
        }
        if (running_data.pic_writing) {
            return events ^ MCT_PIC_DISPLAY;
        }
        if (!running_data.edit_flag && running_data.mode_data < 3 && key_bund.pic[running_data.mode_data][1] > 0) {
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
        if (running_data.mode_data == 0) {
            update_claude_ws2812();
        }
        return events ^ MCT_MODE_END;
    }

    return 0;
}

void update_claude_ws2812(void)
{
    if (running_data.mode_data != 0)
        return;
    switch (running_data.claude_state) {
    case CL_SessionStart: {
        running_data.ws2812_mode         = WS2812_MIDDLE_LIGHT;
        running_data.ws2812_single_color = 0xf02029;
    } break;
    case CL_PostToolUse:
    case CL_UserPromptSubmit: {
        running_data.ws2812_mode         = WS2812_SINGLE_MOVE;
        running_data.ws2812_single_color = 0xf02029;
    } break;
    case CL_PermissionRequest: {
        running_data.ws2812_mode         = WS2812_BREATHING;
        running_data.ws2812_single_color = 0xf02029;
    } break;
    case CL_PreToolUse: {
        running_data.ws2812_mode         = WS2812_SINGLE_MOVE;
        running_data.ws2812_single_color = 0x2050FF;
    } break;
    case CL_Stop: {
        running_data.ws2812_mode         = WS2812_MIDDLE_LIGHT;
        running_data.ws2812_single_color = 0xf02029;
    } break;
    case CL_SessionEnd: {
        running_data.ws2812_mode = WS2812_OFF;
    } break;
    }
    if (running_data.sw_state == 0) { // auto mode cover
        switch (running_data.claude_state) {
        case CL_PostToolUse:
        case CL_UserPromptSubmit: {
            running_data.ws2812_mode = WS2812_RAINBOW_MOVE;
        } break;
        case CL_PermissionRequest:
        case CL_PreToolUse: {
            running_data.ws2812_mode = WS2812_RAINBOW_WAVE;
        } break;
        }
    }
}
__INTERRUPT
__HIGH_CODE
void GPIOA_IRQHandler(void)
{
    GPIOA_ClearITFlagBit(GPIO_Pin_13);
    PRINT("cgr\n");
    running_data.charge_flag = 1;
    tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(0));
}
