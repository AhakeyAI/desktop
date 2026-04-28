#ifndef __MAIN_H
#define __MAIN_H
#ifndef min
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif
#include "psk_ps.h"

enum my_event_name_e {
    MCT_test_event           = (1 << 0),
    MCT_light_control        = (1 << 1),
    MCT_key_scan             = (1 << 2),
    MCT_START_POWER_OFF      = (1 << 3),
    MCT_adc_measure          = (1 << 4),
    MCT_light_reset          = (1 << 5),
    MCT_music_ticks          = (1 << 6),
    MCT_POWER_OFF_TIME_CHECK = (1 << 7),
    MCT_POWER_OFF_LOOP       = (1 << 8),
    MCT_POWER_OFF_buzz       = (1 << 9),
    MCT_WS2812_MODE          = (1 << 10),
    MCT_COMMAND_TODO         = (1 << 11),
    MCT_DATA_TODO            = (1 << 12),
    MCT_PIC_DISPLAY          = (1 << 13),
    MCT_MODE_END             = (1 << 14),

    MCT_NO_USE = (1 << 15),
};

#include "CONFIG.h"
#include "HAL.h"
#include "adc.h"
#include "fram_RC16.h"
#include "gpio.h"
#include "hiddev.h"
#include "hidkbd.h"
#include "ips096_st7735.h"
#include "pm.h"
#include "psk_ws2812.h"
#include "usb1_hid.h"
#define POWER_ON GPIOA_SetBits(GPIO_Pin_12)
#define POWER_OFF                     \
    {                                 \
        save_all_data_to_fram();      \
        GPIOA_ResetBits(GPIO_Pin_12); \
        while (1) {                   \
        }                             \
    }

enum music_flag {
    MUS_STOP = 0x01,
    MUS_1    = 0x02,
    MUS_2    = 0x04,
    MUS_3    = 0x08,
    MUS_cus  = 0x10

};
enum claude_state_e {
    CL_Notification,
    CL_PermissionRequest,
    CL_PostToolUse,
    CL_PreToolUse,
    CL_SessionStart,
    CL_Stop,
    CL_TaskCompleted,
    CL_UserPromptSubmit,
    CL_SessionEnd,
};
typedef struct
{
    uint8_t mac_offset;
    uint8_t mode_data; // mode
    uint8_t edit_flag; // 0 no, 1 edit mode 2 mac
    uint8_t have_edit;
    uint8_t tmp_mac;
    int     v_bat;
    uint8_t power_persent;
    uint8_t bt_connect_stat; // 0 no 1 connecting 2 ed

    uint8_t            usb_is_connected; // 0 ble, 1 usb
    enum ws2812_mode_e ws2812_mode;
    uint8_t            ws2812_mode_ignore_flag;
    uint32_t           ws2812_single_color;
    uint32_t           power_off_timeout;

    uint32_t data_address;
    uint32_t data_end_address; // not include
    uint8_t  pic_index;
    uint8_t  pic_writing;

    uint8_t charge_flag;

    uint8_t             sw_state;
    enum claude_state_e claude_state;
    uint8_t             have_update_custom_data;
} running_data_s;
// #pragma pack(1)
typedef struct
{
    uint8_t _mac_offset;
    uint8_t _mode_data;
    uint8_t _reserved[2];

    uint16_t GAP_APPEARE;

    uint8_t device_name[22]; // 21 in fact
    //----------------------------------------------------------------
} data_in_fram_s;
extern data_in_fram_s data_in_fram;
#define len_data_in_fram sizeof(data_in_fram_s)

typedef struct
{
    uint8_t  user_key_bind[3][4][100];
    uint8_t  user_key_desc[3][4][20];
    uint16_t pic[3][3];
} key_bund_s;
extern key_bund_s key_bund;
#define key_bund_s_len sizeof(key_bund_s)

void start_music(int x);
void power_deep_sleep(void);

#define IS_CHAEGING !GPIOA_ReadPortPin(GPIO_Pin_13)

// *notes; //
extern running_data_s running_data;
extern tmosTaskID     mTaskID;
// #include "ips096_st7735.h"
#include "buzzerDriver.h"
#include "psk_hid.h"
#include "psk_led.h"
#include "psk_multi_button.h"
#include "psk_ps.h"
#include "psk_ws2812.h"
void usb_desc_set(void);
void init_desp(void);

void update_claude_ws2812(void);

void sub_main(void);
void sub_main_1(void);
#endif
