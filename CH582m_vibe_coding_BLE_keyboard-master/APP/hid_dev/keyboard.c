#include "keyboard.h"
#include "main.h"

keyboard_buff               tkeyboard_buff;
keyboard_buff               tkeyboard_buff_last;
keyboard_state_t            keyboard_state;
struct keyboard_led_state_t keyboard_led_state;

#ifdef KEYBOARD_WITH_LWRB
lwrb_t  keyboard_command;
uint8_t keyboard_command_buff[COMMAND_SIZE];
#endif

const uint8_t board_non_shift[128]  = {0,  0,  0,  0,  0,  0,  0,  0,  0,  43, 40, 0,  0,  0,  0,  0,  0,  0,  0,
                                       0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  44, 0,  0,  0,  0,  0,
                                       0,  52, 0,  0,  0,  0,  54, 45, 55, 56, 39, 30, 31, 32, 33, 34, 35, 36, 37,
                                       38, 0,  51, 0,  46, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
                                       0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  47, 49, 48, 0,
                                       0,  53, 4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
                                       21, 22, 23, 24, 25, 26, 27, 28, 29, 0,  0,  0,  0,  0};
const uint8_t board_with_shift[128] = {0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
                                       0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  30, 52, 32, 33, 34,
                                       36, 0,  38, 39, 37, 46, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
                                       0,  51, 0,  54, 0,  55, 56, 31, 4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14,
                                       15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 0,  0,  0,  35,
                                       45, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
                                       0,  0,  0,  0,  0,  0,  0,  0,  0,  47, 49, 48, 53, 0};
const uint8_t board_keypad[128]     = {0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  88, 0,  0,  0,  0, 0, 0, 0, 0, 0, 0,  0,
                                       0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0, 0, 0, 0, 0, 85, 87,
                                       0, 86, 99, 84, 98, 89, 90, 91, 92, 93, 94, 95, 96, 97, 0, 0, 0, 0, 0, 0, 0,  0,
                                       0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0, 0, 0, 0, 0, 0,  0,
                                       0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0, 0, 0, 0, 0, 0,  0,
                                       0, 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0, 0, 0};
void          send_keyboard_data(void)
{
    // static uint32_t time_count;
    static uint8_t i, t;
    static uint8_t flag, lastsend;
    static uint8_t data[2];
    static uint8_t next_data[2];

    // time_count++;

#ifdef KEYBOARD_WITH_LWRB
    while (lwrb_get_full(&keyboard_command) >= 2 && data[0] != DELAY) {
        lwrb_read(&keyboard_command, (uint8_t *) data, 2);
        PRINT("read %02x, %02x\n", data[0], data[1]);
        switch (data[0]) {
            // case SET_SP:
            //     add_special_code((enum keyboard_sp_key)data[1], data[2]);
            //     break;
            // case SET_NOR:
            //     add_key_code(*((uint8_t *)(data + 1)), data[2]);
            //     break;
            // case SET_DELAY:
            //     delay_time = (data[1] << 8) | (data[2] & 0x00ff);
            //     break;

        case DOWN_KEY:
            keyboard_press_key_code_1(data[1], 1);
            PRINT("key_down %02x\n", data[1]);
            if (lwrb_peek(&keyboard_command, 0, (uint8_t *) next_data, 2) == 2) {
                if (data[1] == next_data[1] && next_data[0] == UP_KEY) {
                    data[0] = DELAY;
                    data[1] = 1;
                    PRINT("same key_up %02x\n", next_data[1]);
                }
                if (next_data[0] == UP_ALLKEY) {
                    data[0] = DELAY;
                    data[1] = 1;
                    PRINT("all key_up wait\n", next_data[1]);
                }
            }

            break;
        case UP_KEY:
            keyboard_press_key_code_1(data[1], 0);
            PRINT("key_up %02x\n", data[1]);
            if (lwrb_peek(&keyboard_command, 0, (uint8_t *) next_data, 2) == 2)
                if (data[1] == next_data[1] && next_data[0] == DOWN_KEY) {
                    data[0] = DELAY;
                    data[1] = 1;
                    PRINT("same key_down %02x\n", next_data[1]);
                }

            break;
        case DELAY:
            break;
        case UP_ALLKEY:
            tkeyboard_buff.special_key = 0;
            memset(tkeyboard_buff.keys, 0, sizeof(tkeyboard_buff.keys));
            memset(tkeyboard_buff.special_key_release_times, 0, sizeof(tkeyboard_buff.special_key_release_times));
            memset(tkeyboard_buff.keys_release_times, 0, sizeof(tkeyboard_buff.keys_release_times));
            PRINT("all key_up\n");
            break;
        }
    }
    if (data[0] == DELAY) {
        if (data[1])
            data[1]--;
        else
            data[0] = WAIT;
    }
#endif
    // PRINT("start_send\n");
    if (memcmp(&tkeyboard_buff_last, &tkeyboard_buff, keyboard_state.report_length) == 0) {
    } else {
        memcpy(&tkeyboard_buff_last, &tkeyboard_buff, keyboard_state.report_length);
        MY_USB_HID_SEND_REPORT(((uint8_t *) &tkeyboard_buff), keyboard_state.report_length);
    }
    if (keyboard_state.mode == SIX_KEY) {
        for (i = 0; i < 8; i++) {
            if (tkeyboard_buff.special_key_release_times[i] > 0) {
                tkeyboard_buff.special_key_release_times[i]--;
            }

            if (tkeyboard_buff.special_key_release_times[i] == 0) {
                tkeyboard_buff.special_key &= ~(0x01 << i);
            } else {
                flag = 0;
                tkeyboard_buff.special_key |= (0x01 << i);
            }
        }
        for (i = 0; i < 6; i++) {
            t = i;
            if (tkeyboard_buff.keys_release_times[i] > 0) {
                tkeyboard_buff.keys_release_times[i]--;
            }

            if (tkeyboard_buff.keys_release_times[i] == 0) {
                *(tkeyboard_buff.keys + i) = 0;
            } else {
                flag = 0;
            }
            while (t > 0 && tkeyboard_buff.keys_release_times[t - 1] == 0 && tkeyboard_buff.keys_release_times[t] != 0) {
                tkeyboard_buff.keys_release_times[t - 1] = tkeyboard_buff.keys_release_times[t];
                *(tkeyboard_buff.keys + t - 1)           = *(tkeyboard_buff.keys + t);
                tkeyboard_buff.keys_release_times[t]     = 0;
                *(tkeyboard_buff.keys + t)               = 0;
                t--;
            }
        }
    }
    // keyboard_state.send_ok = flag;
}

void keyboard_init(void)
{
    memset(&keyboard_state, 0X00, sizeof(keyboard_state));
    // if (running_data.mac_offset >= 5)
    {
        keyboard_state.mode             = SIX_KEY;
        keyboard_state.kbd_is_onereport = 1;
        keyboard_state.report_length    = 9;
        keyboard_state.report_pointer   = report_map_six_key;
        keyboard_state.desp_lenth       = sizeof(report_map_six_key);
    }
    // else
    // {
    //     keyboard_state.mode             = ALL_KEY;
    //     keyboard_state.kbd_is_onereport = 0;
    //     keyboard_state.report_length    = 18;
    //     keyboard_state.report_pointer   = report_map_all;
    //     keyboard_state.desp_lenth       = sizeof(report_map_all);
    // }
    memset(&tkeyboard_buff, 0X00, sizeof(tkeyboard_buff));
    memset(&tkeyboard_buff_last, 0X00, sizeof(tkeyboard_buff_last));
    tkeyboard_buff.report_id = 0x01;
#ifdef KEYBOARD_WITH_LWRB
    lwrb_init(&keyboard_command, (uint8_t *) keyboard_command_buff, COMMAND_SIZE);
#endif
}
void add_special_code(enum keyboard_sp_key k, int8_t reprot_times)
{
    if (keyboard_state.mode == SIX_KEY) {
        if (reprot_times) {
            tkeyboard_buff.special_key |= (0x01 << k);
        }
        // else
        //     tkeyboard_buff.special_key &= ~(0x01 << k);
        tkeyboard_buff.special_key_release_times[k] = reprot_times;
        return;
    } else if (keyboard_state.mode == ALL_KEY) {
        kbd_write_command(DOWN_KEY, k + 0xe0);
        kbd_write_command(DELAY, reprot_times);
        kbd_write_command(UP_KEY, k + 0xe0);
    }
}

void add_key_code(uint8_t k, int8_t reprot_times)
{
    if (keyboard_state.mode == SIX_KEY) {
        static uint8_t i;
        if (k == 0) {
            return;
        }
        // do a sort before delete or add key
        int t = 0;
        for (int i = 0; i < 6; i++) {
            t = i;

            if (tkeyboard_buff.keys_release_times[i] == 0) {
                *(tkeyboard_buff.keys + i) = 0;
            } else {
            }
            while (t > 0 && tkeyboard_buff.keys_release_times[t - 1] == 0 && tkeyboard_buff.keys_release_times[t] != 0) {
                tkeyboard_buff.keys_release_times[t - 1] = tkeyboard_buff.keys_release_times[t];
                *(tkeyboard_buff.keys + t - 1)           = *(tkeyboard_buff.keys + t);
                tkeyboard_buff.keys_release_times[t]     = 0;
                *(tkeyboard_buff.keys + t)               = 0;
                t--;
            }
        }

        for (i = 0; i < 6; i++) {
            if (*(tkeyboard_buff.keys + i) == k) {
                break;
            }

            if (tkeyboard_buff.keys_release_times[i] == 0) {
                break;
            }
        }
        if (i == 6) {
            return;
        }
        if (reprot_times) {
            *(tkeyboard_buff.keys + i) = k;
        }
        tkeyboard_buff.keys_release_times[i] = reprot_times;
        return;
    } else if (keyboard_state.mode == ALL_KEY) {
        kbd_write_command(DOWN_KEY, k);
        kbd_write_command(DELAY, reprot_times);
        kbd_write_command(UP_KEY, k);
    }
}
void kbd_write_command(uint8_t a, int8_t b)
{
    uint8_t data[2] = {a, b};
#ifdef KEYBOARD_WITH_LWRB
    lwrb_write(&keyboard_command, data, 2);
#else
#warning "Not support! ,wip"
#endif
}
void kbd_write_command_list(uint8_t *data, uint32_t len)
{
#ifdef KEYBOARD_WITH_LWRB
    if (len % 2 == 0 && len <= lwrb_get_free(&keyboard_command))
        lwrb_write(&keyboard_command, data, len);
#else
#warning "Not support! ,wip"
#endif
}

void keyboard_delay(int8_t reprot_times)
{
    kbd_write_command(DELAY, reprot_times);
}
void keyboard_press_sp_key(enum keyboard_sp_key k, int8_t reprot_times)
{
    kbd_write_command(DOWN_KEY, k + 0xe0);
    kbd_write_command(DELAY, reprot_times);
    kbd_write_command(UP_KEY, k + 0xe0);
}
void keyboard_press_key_code(uint8_t k, int8_t reprot_times)
{
    kbd_write_command(DOWN_KEY, k);
    kbd_write_command(DELAY, reprot_times);
    kbd_write_command(UP_KEY, k);
}
void keyboard_press_char(char a, int8_t reprot_times)
{
    if (board_non_shift[a]) {
        keyboard_press_key_code(board_non_shift[a], reprot_times);
    } else if (board_with_shift[a]) {
        kbd_write_command(DOWN_KEY, LEFT_SHIFT + 0xe0);
        keyboard_press_key_code(board_with_shift[a], reprot_times);
        kbd_write_command(UP_KEY, LEFT_SHIFT + 0xe0);
    }
}
void keyboard_press_keypad_char(char a, int8_t reprot_times)
{
    if (board_keypad[a]) {
        keyboard_press_key_code(board_keypad[a], reprot_times);
    }
}

void keyboard_press_str(char *s, int8_t time_ms)
{
    static uint8_t lastsend;
    static uint8_t totalsend;
    uint8_t        last, cur;
    if (time_ms > 0) {
        while (*s) {
            if (board_non_shift[*s]) {
                keyboard_press_key_code(board_non_shift[*s], 1);
            } else if (board_with_shift[*s]) {
                kbd_write_command(DOWN_KEY, LEFT_SHIFT + 0xe0);
                keyboard_press_key_code(board_with_shift[*s], 1);
                kbd_write_command(UP_KEY, LEFT_SHIFT + 0xe0);
            }
            keyboard_delay(time_ms);
            s++;
        }
    } else {
        while (*s) {
            if (totalsend == 6 || (lastsend == *s)) {
                totalsend = 0;
                keyboard_delay(1);
            }

            if (board_non_shift[*s]) {
                cur = 1;
                if (last != cur) {
                    totalsend = 0;
                    keyboard_delay(1);
                }

                keyboard_press_key_code(board_non_shift[*s], 1);
                totalsend++;
            } else if (board_with_shift[*s]) {
                totalsend++;
                cur = 2;

                if (last != cur) {
                    totalsend = 0;
                    keyboard_delay(1);
                }
                kbd_write_command(DOWN_KEY, LEFT_SHIFT + 0xe0);
                keyboard_press_key_code(board_with_shift[*s], 1);
                kbd_write_command(UP_KEY, LEFT_SHIFT + 0xe0);
            }

            last     = cur;
            lastsend = *s;
            s++;
        }
    }
}

void keyboard_press_sp_key_1(enum keyboard_sp_key k, int8_t if_press)
{
    if (keyboard_state.mode == SIX_KEY) {
        if (if_press) {
            if_press = -1;
        }
        // kbd_write_command(SET_SP, (int8_t)k, if_press);
        add_special_code(k, if_press);
    } else {
        if (if_press) {
            tkeyboard_buff.special_key |= (0x01 << k);
        } else
            tkeyboard_buff.special_key &= ~(0x01 << k);
    }
}
void keyboard_press_key_code_1(uint8_t k, int8_t if_press)
{
    if (k >= 0xe0 && k <= 0xe7) {
        keyboard_press_sp_key_1(k - 0xe0, if_press);
        return;
    }
    if (keyboard_state.mode == SIX_KEY) {
        if (if_press) {
            if_press = -1;
        }
        // kbd_write_command(SET_NOR, (int8_t)k, if_press);
        add_key_code(k, if_press);
    } else {
        if (if_press)
            tkeyboard_buff.keys[k / 8] |= (0x01 << (k % 8));
        else
            tkeyboard_buff.keys[k / 8] &= ~(0x01 << (k % 8));
    }
}
void keyboard_press_char_1(char a, int8_t if_press)
{
    if (board_non_shift[a]) {
        keyboard_press_key_code_1(board_non_shift[a], if_press);
    } else if (board_with_shift[a]) {
        keyboard_press_sp_key_1(LEFT_SHIFT, if_press);
        keyboard_press_key_code_1(board_with_shift[a], if_press);
    }
}
