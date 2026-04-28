#include "psk_multi_button.h"
#include "ips096_st7735.h"
#include "main.h"
#include "multi_button.h"
#include "psk_led.h"

#include "custom_control.h"
#include "keyboard.h"
#include "math.h"
#include "mouse.h"
#include "touch_screen.h"

uint8_t mode3_mode[TOTAL_KEY] = {0};
Button  keys__uz[TOTAL_KEY];
uint8_t key_scan_code = 0;

uint8_t key_read(para i);

uint8_t num_of_keys(void)
{
    uint8_t sum = 0;
    for (uint8_t i = 0; i < TOTAL_KEY; i++) {
        if (key_read(i) && i != 3)
            sum++;
    }
    return sum;
}

void set_mode(uint8_t mode)
{
    __LimitValue(mode, 0, 3);
    // mode default 2812 mode
    // mode 0 is override in key_power_callback, call func void update_claude_ws2812(void)
    const enum ws2812_mode_e m[4] = {WS2812_OFF, WS2812_RAINBOW_MOVE, WS2812_RAINBOW_WAVE_SLOW, WS2812_OFF};
    running_data.ws2812_mode      = m[mode];
    running_data.mode_data        = mode;
    LCD_CS_RESET;
    IPS_Clear(CYAN);
    char txt[15];
    sprintf(txt,
            "%1d.%02dV %d%% %c",
            running_data.v_bat / 100,
            running_data.v_bat % 100,
            running_data.power_persent,
            IS_CHAEGING ? 'C' : ' ');
    BACK_COLOR = IS_CHAEGING ? GREEN : CYAN;
    IPS_ShowString(8, 0, txt, MAGENTA);
    BACK_COLOR = CYAN;
    sprintf(txt, "%s", running_data.bt_connect_stat == 2 ? "OK" : "ing");
    IPS_ShowString(152 - 8 * strlen(txt), 0, txt, MAGENTA);
    for (int i = 0; i < LED_NUM; i++) {
        ws2812_list[i].hex = 0;
    }
    ws2812_list[mode * 2].hex     = 0xFF2464ff;
    ws2812_list[mode * 2 + 1].hex = 0xFF2464ff;
    if (mode < 3)
        for (int i = 0; i < 4; i++) {
            if (key_bund.user_key_desc[mode][i][0])
                IPS_ShowString_len(8, 16 + i * 16, key_bund.user_key_desc[mode][i], RED, 20);
            else
                IPS_ShowString(0, 16 + i * 16, "N/A", BLUE);
        }
    LCD_CS_SET;
}
void key_scan(void)
{
    static uint16_t j;
    static uint32_t pin[] = {GPIO_Pin_8, GPIO_Pin_3, GPIO_Pin_2, GPIO_Pin_1, GPIO_Pin_0};
    // static GPIO_TypeDef *port[] = {KEY4_GPIO_Port, KEY3_GPIO_Port,
    // KEY2_GPIO_Port, KEY1_GPIO_Port, KEY0_GPIO_Port}; key_scan_code = 0;
    for (j = 0; j < 1; j++) {
        key_scan_code <<= 1;
        key_scan_code += !GPIOA_ReadPortPin(pin[j]);
    }
    for (j; j < TOTAL_KEY; j++) {
        key_scan_code <<= 1;
        key_scan_code += !GPIOB_ReadPortPin(pin[j]);
    }
}
uint8_t key_read(para i)
{
    return (key_scan_code >> i) & 0x0001;
}
uint8_t key_comm[]
    = {0x74, 8, DOWN_KEY, HID_KEYBOARD_X, UP_KEY, HID_KEYBOARD_X, DOWN_KEY, HID_KEYBOARD_X, UP_KEY, HID_KEYBOARD_X};
uint8_t key_comm_898[] = {0x73, 3, 0xe0, 0xe1, HID_KEYBOARD_ESCAPE};

void prase_user_key(uint8_t *data, uint8_t len, uint8_t if_press)
{
    // for (uint8_t i = 0; i < min(data[1], len) + 2; i++)
    // {
    // 	PRINT("%02x ", data[i]);
    // }
    if (data[0] == 0x73) {
        for (int i = 0; i < min(data[1], len); i++) {
            keyboard_press_key_code_1(data[2 + i], if_press);
        }
    } else if (data[0] == 0x74) {
        if (if_press) {
            kbd_write_command_list(data + 2, min(data[1], len));
        }
    }
}
void user_defined_mode(uint8_t key_index, uint8_t if_press, uint8_t mode)
{
    __LimitValue(mode, 0, 2);
    __LimitValue(key_index, 0, 3);
    prase_user_key(key_bund.user_key_bind[mode][key_index], sizeof(key_bund.user_key_bind[mode][key_index]), if_press);
}
/**
 *
 * @brief : 按键回调函数, index 按键下标
 * @note  :
 * @param {void} *button
 */
void key44callback(void *button)
{
    uint32_t        index;
    PressEvent      btn_event_val;
    static uint32_t count = 0;
    btn_event_val         = get_button_event((struct Button *) button);
    index                 = ((struct Button *) button)->func_para;
    // PRINT("%d , %d\n", index, btn_event_val);
    // if (running_data.mode_data == 3 && btn_event_val == PRESS_DOWN)
    //     running_data.ws2812_mode = index;
    if (running_data.edit_flag == 1) {
        running_data.have_edit = 1;
        if (btn_event_val == PRESS_DOWN) {
            set_mode(index);
            running_data.mode_data = index;
        }
    } else if (running_data.edit_flag == 0) {
        if (running_data.mode_data < 3)
            user_defined_mode(index, !btn_event_val, running_data.mode_data);
        else {
        }
    }
    return;
}
void key_power_callback(void *button)
{
    uint32_t   index;
    PressEvent btn_event_val;
    btn_event_val = get_button_event((struct Button *) button);
    index         = ((struct Button *) button)->func_para;
    switch (btn_event_val) {
    case PRESS_DOWN: {
        break;
    }
    case PRESS_UP: {
        break;
    }
    case SINGLE_CLICK: {
        if (1) {
            running_data.edit_flag = 1;
            running_data.mode_data += 1;
            running_data.mode_data %= 4;
            running_data.have_edit               = 1;
            running_data.ws2812_mode_ignore_flag = 1;
            for (int i = 0; i < LED_NUM; i++) {
                ws2812_list[i].hex = 0;
            }
            set_mode(running_data.mode_data);
            tmos_start_task(mTaskID, MCT_MODE_END, MS1_TO_SYSTEM_TIME(1500));
        } else {
        }
        break;
    }
    case LONG_PRESS_START: {
        // if (running_data.have_edit == 0) {
        tmos_set_event(mTaskID, MCT_START_POWER_OFF);
        // }
        break;
    }
    }
}
void my_button_init(void)
{
    int8_t i;
    memset(keys__uz, 0, sizeof(keys__uz));
    key_scan_code = 0;
    for (i = 0; i < TOTAL_KEY; i++) {
        button_init(keys__uz + i, key_read, i);
        button_attach(keys__uz + i, PRESS_DOWN, key44callback);
        button_attach(keys__uz + i, PRESS_UP, key44callback);
        if (i == 4) {
            button_attach(keys__uz + i, PRESS_DOWN, key_power_callback);
            button_attach(keys__uz + i, PRESS_UP, key_power_callback);
            button_attach(keys__uz + i, LONG_PRESS_START, key_power_callback);
            button_attach(keys__uz + i, SINGLE_CLICK, key_power_callback);
        }
        button_start(keys__uz + i);
    }
}
