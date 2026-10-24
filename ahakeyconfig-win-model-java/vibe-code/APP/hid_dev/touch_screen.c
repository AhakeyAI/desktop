#include "touch_screen.h"

touch_inf  ttouch_inf;
touch_buff ttouch_buff;
// touch_buff ttouch_buff_last;
static int con_index;

void touch_init(void)
{
    memset(&ttouch_buff, 0X00, sizeof(ttouch_buff));
    ttouch_buff.report_id = 0x04;
    // memset(&ttouch_buff_last, 0X00, sizeof(ttouch_buff));
    touch_set_size(1920, 1080);
}

void send_touch_data(void)
{
    static uint8_t k;
    k = 0;
    if (ttouch_inf.continue_function) {
        touch_continue_function();
    }
    if (ttouch_inf.release < 0) {
        ttouch_buff.touch_flag = 1;
    } else if (ttouch_inf.release > 0) {
        ttouch_buff.touch_flag = 1;
        ttouch_inf.release--;
    } else if (ttouch_buff.touch_flag == 1) {
        k                      = 1;
        ttouch_buff.touch_flag = 0;
    }
    if (ttouch_buff.touch_flag || k != 0) {
        MY_USB_HID_SEND_REPORT((uint8_t *) &ttouch_buff, sizeof(ttouch_buff));
    }
}

void touch_set_size(uint16_t x, uint16_t y)
{
    ttouch_inf.x_max   = x;
    ttouch_inf.y_max   = y;
    ttouch_inf.x_scale = 4095.f / x;
    ttouch_inf.y_scale = 4095.f / y;
}
void touch_set_time(int16_t times_ms)
{
    if (times_ms > 0) {
        times_ms /= SEND_DELAY;
    }
    ttouch_inf.release = times_ms;
}
void touch_set_pos(uint16_t x, uint16_t y)
{
    // srand(HAL_GetTick());
    ttouch_buff.x = (uint16_t) ((x) *ttouch_inf.x_scale);
    ttouch_buff.y = (uint16_t) ((y) *ttouch_inf.y_scale);
}
void touch_set_continue_function(int8_t s)
{
    con_index                    = 0;
    ttouch_inf.continue_function = !!s;
}

__weak void touch_continue_function(void)
{
    if (con_index == 0) {
        touch_set_time(-1);
        touch_set_pos(1009, 802);
    } else if (con_index == 2) {
        touch_set_time(-1);
        touch_set_pos(801, 781);
    } else {
        touch_set_time(0);
    }
    con_index = (con_index + 1) % 4;
}
