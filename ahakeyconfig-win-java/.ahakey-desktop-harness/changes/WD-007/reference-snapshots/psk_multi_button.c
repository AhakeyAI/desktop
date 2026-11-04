#include "psk_multi_button.h"
#include "ips096_st7735.h"
#include "main.h"
#include "multi_button.h"
#include "psk_led.h"
#include "../sdk_bridge/ahakey_sdk_config.h"
#include "../sdk_bridge/ahakey_sdk_runtime.h"
#include "../services/device_lifecycle.h"
#include "../services/k1_restore_store.h"
#include "../services/restore_initialization.h"

#include "custom_control.h"
#include "keyboard.h"
#include "math.h"
#include "mouse.h"
#include "touch_screen.h"

#if defined(__GNUC__)
extern uint8_t restore_initialization_is_quarantined(void) __attribute__((weak));
static uint8_t input_control_restore_quarantined(void)
{
    return restore_initialization_is_quarantined && restore_initialization_is_quarantined();
}
#else
static uint8_t input_control_restore_quarantined(void)
{
    return restore_initialization_is_quarantined();
}
#endif

uint8_t mode3_mode[TOTAL_KEY] = {0};
Button  keys__uz[TOTAL_KEY];
uint8_t key_scan_code = 0;

uint8_t key_read(para i);

#define POWER_KEY_COMPLETE_TICKS (1500 / TICKS_INTERVAL)
#define INPUT_CONTROL_HOLD_TIMEOUT_TICKS (30000 / TICKS_INTERVAL)

#ifndef CP2_6_ONBOARDING_K1_PRODUCTION_JOURNEY
static void show_charge_status_icon(uint16_t x, uint16_t y, uint8_t charging)
{
    IPS_Fill(x, y, x + 15, y + 13, CYAN);
    if (!charging)
        return;

    IPS_DrawLine(x, y + 3, x + 10, y + 3, GREEN);
    IPS_DrawLine(x, y + 11, x + 10, y + 11, GREEN);
    IPS_DrawLine(x, y + 3, x, y + 11, GREEN);
    IPS_DrawLine(x + 10, y + 3, x + 10, y + 11, GREEN);
    IPS_Fill(x + 11, y + 6, x + 13, y + 8, GREEN);
    IPS_DrawLine(x + 6, y + 4, x + 3, y + 8, YELLOW);
    IPS_DrawLine(x + 3, y + 8, x + 6, y + 8, YELLOW);
    IPS_DrawLine(x + 6, y + 8, x + 4, y + 12, YELLOW);
}

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
    __LimitValue(mode, 0, USER_MODE_COUNT - 1);
    input_control_force_release_all(INPUT_CONTROL_RELEASE_MODE_CHANGE);
#if AHAKEY_SDK_ENABLE && AHAKEY_SDK_OVERRIDE_DISPLAY
    if (ahakey_sdk_display_is_owned()) {
        running_data.mode_data = mode;
        return;
    }
#endif
    // mode default 2812 mode
    // mode 0 is override in key_power_callback, call func void update_claude_ws2812(void)
    const enum ws2812_mode_e m[USER_MODE_COUNT] = {WS2812_OFF, WS2812_OFF, WS2812_OFF, WS2812_OFF};
    running_data.ws2812_mode      = m[mode];
    running_data.mode_data        = mode;
    running_data.pic_writing      = 0;
    running_data.pic_index        = 0;
    for (int i = 0; i < LED_NUM; i++) {
        ws2812_list[i].hex = 0;
    }
    uint8_t led_index = mode * 2;
    if (led_index + 1 < LED_NUM) {
        ws2812_list[led_index].hex     = 0x80102080;
        ws2812_list[led_index + 1].hex = 0x80102080;
    }
    render_normal_mode_scene(mode);
}
void render_normal_mode_scene(uint8_t mode)
{
    LCD_CS_RESET;
    IPS_Clear(CYAN);
    char txt[15];
    sprintf(txt, "%1d.%02dV %d%%", running_data.v_bat / 100, running_data.v_bat % 100, running_data.power_persent);
    BACK_COLOR = CYAN;
    IPS_ShowString(8, 0, txt, MAGENTA);
    show_charge_status_icon(88, 1, IS_CHAEGING);
    BACK_COLOR = CYAN;
    get_connection_status_text(txt);
    IPS_ShowString(152 - 8 * strlen(txt), 0, txt, MAGENTA);
    if (mode < USER_MODE_COUNT)
        for (int i = 0; i < USER_KEY_COUNT; i++) {
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
#endif
uint8_t key_comm[]
    = {0x74, 8, DOWN_KEY, HID_KEYBOARD_X, UP_KEY, HID_KEYBOARD_X, DOWN_KEY, HID_KEYBOARD_X, UP_KEY, HID_KEYBOARD_X};
uint8_t key_comm_898[] = {0x73, 3, 0xe0, 0xe1, HID_KEYBOARD_ESCAPE};

typedef enum {
    INPUT_CONTROL_EXECUTE_ONCE = 0,
    INPUT_CONTROL_HOLD_UNTIL_RELEASE,
} input_control_action_mode_t;

typedef struct {
    uint8_t                    *short_action;
    uint8_t                     short_len;
    uint8_t                    *long_action;
    uint8_t                     long_len;
    input_control_action_mode_t long_mode;
} input_control_policy_t;

typedef struct {
    uint8_t  pending;
    uint8_t  long_fired;
    uint8_t  hold_active;
    uint8_t *hold_action;
    uint8_t  hold_len;
} input_control_runtime_t;

static input_control_runtime_t s_input_control_runtime[USER_KEY_COUNT];
static void input_control_k1_finish(uint8_t transmit_release);
static struct {
    uint8_t active;
    uint8_t kind;
    uint8_t mode;
    uint8_t length;
    uint16_t usage;
    uint8_t action[K1_ROUTE_ACTION_MAX];
} s_k1_capture;

typedef struct {
    uint8_t baseline_ready;
    uint8_t last_position;
    uint8_t armed;
} side_switch_action_gate_runtime_t;

static side_switch_action_gate_runtime_t s_side_switch_action_gate;

static uint8_t input_control_actions_equal(const uint8_t *left, uint8_t left_len, const uint8_t *right, uint8_t right_len)
{
    if (left_len != right_len)
        return 0;
    return memcmp(left, right, left_len) == 0;
}

static void input_control_clear_runtime(input_control_runtime_t *runtime)
{
    memset(runtime, 0, sizeof(*runtime));
}

static void input_control_execute_once(uint8_t *action, uint8_t len)
{
    prase_user_key(action, len, 1);
    prase_user_key(action, len, 0);
}

void side_switch_action_gate_reset(void)
{
    memset(&s_side_switch_action_gate, 0, sizeof(s_side_switch_action_gate));
}

void side_switch_on_position_change(uint8_t new_state)
{
    side_switch_position_config_s *position;
    uint8_t action_len;

    if (!s_side_switch_action_gate.baseline_ready) {
        s_side_switch_action_gate.baseline_ready = 1;
        s_side_switch_action_gate.last_position = new_state;
        s_side_switch_action_gate.armed = (new_state < SIDE_SWITCH_POSITION_COUNT);
        return;
    }

    if (new_state == s_side_switch_action_gate.last_position)
        return;

    s_side_switch_action_gate.last_position = new_state;
    if (new_state >= SIDE_SWITCH_POSITION_COUNT) {
        s_side_switch_action_gate.armed = 1;
        return;
    }

    if (!s_side_switch_action_gate.armed) {
        s_side_switch_action_gate.armed = 1;
        return;
    }

    position = &key_bund.side_switch_config.position[new_state];
    if (position->bind_type != SIDE_SWITCH_BIND_CUSTOM)
        return;

    action_len = side_switch_actual_action_len(position->action);
    if (!action_len)
        return;

    input_control_execute_once(position->action, action_len);
}

static void input_control_release_runtime(input_control_runtime_t *runtime, input_control_release_reason_t reason)
{
    (void) reason;
    if (runtime->hold_active && runtime->hold_action)
        prase_user_key(runtime->hold_action, runtime->hold_len, 0);
    input_control_clear_runtime(runtime);
}

void input_control_force_release_all(input_control_release_reason_t reason)
{
    for (uint8_t i = 0; i < USER_KEY_COUNT; i++)
        input_control_release_runtime(&s_input_control_runtime[i], reason);
    if (reason == INPUT_CONTROL_RELEASE_RESTORE_RESET)
        input_control_k1_finish(1);
}

static void input_control_k1_finish(uint8_t transmit_release)
{
    if (!s_k1_capture.active) return;
    PRINT("[K1DIAG] finish transmit=%u kind=%u mode=%u usage=%04x len=%u\n",
          transmit_release, s_k1_capture.kind, s_k1_capture.mode,
          s_k1_capture.usage, s_k1_capture.length);
    if (transmit_release) {
        if (s_k1_capture.kind == K1_ROUTE_CONSUMER)
            keyboard_press_consumer_usage_1(s_k1_capture.usage, 0);
        else if (s_k1_capture.length)
            prase_user_key(s_k1_capture.action, s_k1_capture.length, 0);
    }
    memset(&s_k1_capture, 0, sizeof(s_k1_capture));
}

void input_control_k1_release_for_sleep(void) { input_control_k1_finish(1); }
void input_control_k1_clear_for_disconnect(void) { input_control_k1_finish(0); }

static void input_control_k1_route_event(PressEvent event)
{
    k1_route_t route;
    if (!k1_restore_store_read(running_data.mode_data, &route)) {
        PRINT("[K1DIAG] route_read_fail event=%u mode=%u capture=%u kind=%u usage=%04x\n",
              event, running_data.mode_data, s_k1_capture.active,
              s_k1_capture.kind, s_k1_capture.usage);
        if (event == PRESS_UP) input_control_k1_finish(0);
        return;
    }
    PRINT("[K1DIAG] route_read_ok event=%u mode=%u kind=%u usage=%04x capture=%u\n",
          event, running_data.mode_data, route.kind,
          (uint16_t)route.data[0] | ((uint16_t)route.data[1] << 8),
          s_k1_capture.active);
    if (event == PRESS_DOWN) {
        if (s_k1_capture.active) return;
        input_control_k1_finish(0);
        s_k1_capture.active = 1;
        s_k1_capture.kind = route.kind;
        s_k1_capture.mode = running_data.mode_data;
        s_k1_capture.length = route.length;
        if (route.kind == K1_ROUTE_CONSUMER) {
            s_k1_capture.usage = (uint16_t)route.data[0] | ((uint16_t)route.data[1] << 8);
            keyboard_press_consumer_usage_1(s_k1_capture.usage, 1);
        } else {
            memcpy(s_k1_capture.action, route.data, route.length);
            if (route.length) prase_user_key(s_k1_capture.action, route.length, 1);
        }
    } else if (event == PRESS_UP) {
        input_control_k1_finish(1);
    }
}

static void input_control_k1_diag_event(uint8_t event, uint8_t key_index)
{
#if defined(__GNUC__)
    extern uint32_t TMOS_GetSystemClock(void) __attribute__((weak));
#endif
    static uint32_t press_tick;
    uint32_t now = 0;

#if defined(__GNUC__)
    if (TMOS_GetSystemClock)
        now = TMOS_GetSystemClock();
#endif

    if (key_index != 0 || (event != PRESS_DOWN && event != PRESS_UP))
        return;

    if (event == PRESS_DOWN) {
        press_tick = now;
        PRINT("[K1DIAG] edge tick=%lu event=DOWN gpio=%u mode=%u onboarding=%u\n",
              (unsigned long)now, key_read(key_index), running_data.mode_data,
              running_data.voice_onboarding_visible);
    } else {
        PRINT("[K1DIAG] edge tick=%lu event=UP gpio=%u held_ticks=%lu mode=%u onboarding=%u\n",
              (unsigned long)now, key_read(key_index), (unsigned long)(now - press_tick),
              running_data.mode_data, running_data.voice_onboarding_visible);
    }
}

static void input_control_start_hold(input_control_runtime_t *runtime, uint8_t *action, uint8_t len)
{
    runtime->hold_action = action;
    runtime->hold_len    = len;
    runtime->hold_active = 1;
    prase_user_key(action, len, 1);
}

static void input_control_load_policy(uint8_t key_index, uint8_t mode, input_control_policy_t *policy)
{
    policy->short_action = key_bund.user_key_bind[mode][key_index];
    policy->short_len    = sizeof(key_bund.user_key_bind[mode][key_index]);
    policy->long_action  = key_bund.user_key_bind[mode][key_index];
    policy->long_len     = sizeof(key_bund.user_key_bind[mode][key_index]);
    policy->long_mode    = INPUT_CONTROL_EXECUTE_ONCE;
}

static void input_control_handle_distinct_event(uint8_t key_index, PressEvent event, uint16_t ticks,
                                                const input_control_policy_t *policy)
{
    input_control_runtime_t *runtime = &s_input_control_runtime[key_index];

    switch (event) {
    case PRESS_DOWN:
        input_control_release_runtime(runtime, INPUT_CONTROL_RELEASE_NORMAL);
        runtime->pending = 1;
        break;
    case LONG_PRESS_START:
        if (runtime->pending && !runtime->long_fired) {
            runtime->long_fired = 1;
            if (policy->long_mode == INPUT_CONTROL_HOLD_UNTIL_RELEASE)
                input_control_start_hold(runtime, policy->long_action, policy->long_len);
            else
                input_control_execute_once(policy->long_action, policy->long_len);
        }
        break;
    case LONG_PRESS_HOLD:
        if (runtime->hold_active && ticks >= INPUT_CONTROL_HOLD_TIMEOUT_TICKS)
            input_control_release_runtime(runtime, INPUT_CONTROL_RELEASE_TIMEOUT);
        break;
    case PRESS_UP:
        if (runtime->hold_active) {
            input_control_release_runtime(runtime, INPUT_CONTROL_RELEASE_NORMAL);
        } else if (runtime->long_fired) {
            input_control_clear_runtime(runtime);
        } else if (runtime->pending) {
            input_control_execute_once(policy->short_action, policy->short_len);
            input_control_clear_runtime(runtime);
        }
        break;
    default:
        break;
    }
}

static void input_control_handle_ordinary_key_event(uint8_t key_index, PressEvent event, uint16_t ticks)
{
    input_control_policy_t policy;

    if (key_index >= USER_KEY_COUNT || running_data.mode_data >= USER_MODE_COUNT)
        return;

    input_control_load_policy(key_index, running_data.mode_data, &policy);
    if (input_control_actions_equal(policy.short_action, policy.short_len, policy.long_action, policy.long_len)) {
        if (event == PRESS_DOWN || event == PRESS_UP)
            user_defined_mode(key_index, event == PRESS_DOWN, running_data.mode_data);
        return;
    }

    input_control_handle_distinct_event(key_index, event, ticks, &policy);
}

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
    __LimitValue(mode, 0, USER_MODE_COUNT - 1);
    if (key_index >= USER_KEY_COUNT)
        return;
    __LimitValue(key_index, 0, USER_KEY_COUNT - 1);
    prase_user_key(key_bund.user_key_bind[mode][key_index], sizeof(key_bund.user_key_bind[mode][key_index]), if_press);
}
/**
 *
 * @brief : key callback, index is key number
 * @note  :
 * @param {void} *button
 */
void key44callback(void *button)
{
    uint32_t        index;
    PressEvent      btn_event_val;
    static uint32_t count = 0;
    uint8_t         wake_from_standby;
    btn_event_val         = get_button_event((struct Button *) button);
    index                 = ((struct Button *) button)->func_para;
    input_control_k1_diag_event(btn_event_val, index);
    if (index < USER_KEY_COUNT && input_control_restore_quarantined()) {
        if (running_data.voice_onboarding_visible)
            PRINT("[VO] KEY key=%u event=%u prompt=%u quarantine=1 drop=1\n",
                  index, btn_event_val, running_data.voice_onboarding_prompt);
        return;
    }
    if (index < USER_KEY_COUNT && running_data.voice_onboarding_visible)
        PRINT("[VO] KEY key=%u event=%u prompt=%u quarantine=0\n",
              index, btn_event_val, running_data.voice_onboarding_prompt);
    // PRINT("%d , %d\n", index, btn_event_val);
    // if (running_data.mode_data == 3 && btn_event_val == PRESS_DOWN)
    //     running_data.ws2812_mode = index;
#if AHAKEY_SDK_ENABLE
    if (!running_data.voice_onboarding_visible && index < USER_KEY_COUNT) {
        if (btn_event_val == PRESS_DOWN) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_DOWN);
        } else if (btn_event_val == PRESS_UP) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_UP);
        } else if (btn_event_val == SINGLE_CLICK) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_SHORT);
        } else if (btn_event_val == DOUBLE_CLICK) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_DOUBLE);
        } else if (btn_event_val == LONG_PRESS_START) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_LONG);
        } else if (btn_event_val == LONG_PRESS_HOLD) {
            ahakey_sdk_emit_key_event(index + 1, AHAKEY_SDK_KEY_HOLD);
        }
    }
#endif
    if (btn_event_val == PRESS_DOWN) {
        wake_from_standby = device_lifecycle_quiet_active() || device_lifecycle_sleep_active();
        refresh_power_off_timeout();
        device_lifecycle_on_local_input_activity();
        if (wake_from_standby) {
            if (!device_lifecycle_connection_scene_active())
                set_mode(running_data.mode_data);
            tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
        }
    }
    if (index < USER_KEY_COUNT && voice_onboarding_handle_key(index, btn_event_val))
        return;
    if (index == 0 && running_data.edit_flag == 0) {
        uint8_t route_usable = k1_restore_store_is_usable();
        if (btn_event_val == PRESS_DOWN || btn_event_val == PRESS_UP)
            PRINT("[K1DIAG] dispatch event=%u branch=stored_route usable=%u mode=%u capture=%u kind=%u usage=%04x\n",
                  btn_event_val, route_usable, running_data.mode_data,
                  s_k1_capture.active, s_k1_capture.kind, s_k1_capture.usage);
        if (route_usable) input_control_k1_route_event(btn_event_val);
        else if (btn_event_val == PRESS_UP) {
            PRINT("[K1DIAG] dispatch_release_skipped reason=store_unusable capture=%u kind=%u usage=%04x\n",
                  s_k1_capture.active, s_k1_capture.kind, s_k1_capture.usage);
            input_control_k1_finish(0);
        }
        return;
    }
    if (index == 0 && voice_onboarding_mac_consumer_voice_active()) {
        if (btn_event_val == PRESS_DOWN || btn_event_val == PRESS_UP)
            keyboard_press_consumer_usage_1(0x00CF, btn_event_val == PRESS_DOWN);
        return;
    }
    if (running_data.edit_flag == 1) {
        running_data.have_edit = 1;
        if (btn_event_val == PRESS_DOWN) {
            if (index < USER_MODE_COUNT)
                set_mode(index);
        }
    } else if (running_data.edit_flag == 0) {
#if AHAKEY_SDK_ENABLE && AHAKEY_SDK_OVERRIDE_KEYS
        (void) count;
#else
        input_control_handle_ordinary_key_event(index, btn_event_val, ((struct Button *) button)->ticks);
#endif
    }
    return;
}
#ifndef CP2_6_ONBOARDING_K1_PRODUCTION_JOURNEY
void key_power_callback(void *button)
{
    struct Button *btn = (struct Button *) button;
    PressEvent     btn_event_val;
    static uint8_t power_key_long_press;
    static uint8_t power_key_bt_reset_done;
    static uint8_t power_key_wake_only;
    static uint8_t power_key_skip_click;
    btn_event_val = get_button_event(btn);
    switch (btn_event_val) {
    case PRESS_DOWN: {
        device_lifecycle_power_action_t action = device_lifecycle_on_power_press(key_read(3), HAVE_VUSB);
        device_lifecycle_on_local_input_activity();
        power_key_wake_only = action == DEVICE_LIFECYCLE_POWER_WAKE_ONLY ||
                              action == DEVICE_LIFECYCLE_POWER_FAKE_OFF_NOTICE;
        if (power_key_wake_only)
            power_key_skip_click = 1;
        if (action == DEVICE_LIFECYCLE_POWER_FAKE_OFF_NOTICE) {
            tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
            break;
        }
        if (running_data.power_shutdown_mode && !device_lifecycle_usb_fake_off_active()) {
            resume_usb_fake_off_work();
            break;
        }
        power_key_long_press    = 0;
        power_key_bt_reset_done = 0;
        refresh_power_off_timeout();
        break;
    }
    case PRESS_UP: {
        tmos_stop_task(mTaskID, MCT_BT_RESET_HOLD_CHECK);
        device_lifecycle_power_action_t action = device_lifecycle_on_power_release();
        if (power_key_long_press && !power_key_bt_reset_done) {
            if (action == DEVICE_LIFECYCLE_POWER_FORGET_COMPLETE) {
                power_key_bt_reset_done = 1;
                tmos_set_event(mTaskID, MCT_BT_RESET);
            } else if (action == DEVICE_LIFECYCLE_POWER_SHUTDOWN_COMPLETE) {
                tmos_set_event(mTaskID, MCT_POWER_OFF_buzz);
            }
        }
        if (!power_key_long_press)
            running_data.power_off_prompt_mode = 0;
        power_key_long_press    = 0;
        power_key_bt_reset_done = 0;
        power_key_wake_only     = 0;
        break;
    }
    case SINGLE_CLICK: {
        if (power_key_skip_click) {
            power_key_skip_click = 0;
        } else if (!power_key_wake_only && !device_lifecycle_usb_fake_off_active()) {
            if (input_control_restore_quarantined()) break;
            running_data.edit_flag = 1;
            running_data.mode_data += 1;
            running_data.mode_data %= USER_MODE_COUNT;
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
        device_lifecycle_power_action_t action;
        power_key_long_press = 1;
        action = device_lifecycle_on_power_long_start(key_read(3), HAVE_VUSB);
        if (action == DEVICE_LIFECYCLE_POWER_FORGET_COMMIT) {
            running_data.bt_reset_pairing_mode   = 1;
            running_data.power_off_prompt_mode   = 0;
            running_data.ws2812_mode_ignore_flag = 0;
            for (int i = 0; i < LED_NUM; i++)
                ws2812_list[i].hex = 0x80102080;
            tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
        } else if (action == DEVICE_LIFECYCLE_POWER_SHUTDOWN_COMMIT) {
            tmos_set_event(mTaskID, MCT_START_POWER_OFF);
        } else if (action == DEVICE_LIFECYCLE_POWER_WAKE_ONLY) {
            power_key_wake_only = 1;
            tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
        }
        break;
    }
    case LONG_PRESS_HOLD: {
        if (!power_key_bt_reset_done && btn->ticks >= POWER_KEY_COMPLETE_TICKS) {
            device_lifecycle_power_action_t action =
                device_lifecycle_on_power_hold_elapsed(btn->ticks * TICKS_INTERVAL, key_read(3), HAVE_VUSB);
            if (action == DEVICE_LIFECYCLE_POWER_FORGET_COMPLETE) {
                power_key_bt_reset_done = 1;
                tmos_set_event(mTaskID, MCT_BT_RESET);
            } else if (action == DEVICE_LIFECYCLE_POWER_SHUTDOWN_COMPLETE) {
                power_key_bt_reset_done = 1;
                tmos_set_event(mTaskID, MCT_POWER_OFF_buzz);
            }
        }
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
        if (i < USER_KEY_COUNT) {
            button_attach(keys__uz + i, LONG_PRESS_START, key44callback);
            button_attach(keys__uz + i, LONG_PRESS_HOLD, key44callback);
        }
#if AHAKEY_SDK_ENABLE
        if (i < USER_KEY_COUNT) {
            button_attach(keys__uz + i, SINGLE_CLICK, key44callback);
            button_attach(keys__uz + i, DOUBLE_CLICK, key44callback);
        }
#endif
        if (i == 4) {
            button_attach(keys__uz + i, PRESS_DOWN, key_power_callback);
            button_attach(keys__uz + i, PRESS_UP, key_power_callback);
            button_attach(keys__uz + i, LONG_PRESS_START, key_power_callback);
            button_attach(keys__uz + i, LONG_PRESS_HOLD, key_power_callback);
            button_attach(keys__uz + i, SINGLE_CLICK, key_power_callback);
        }
        button_start(keys__uz + i);
    }
}
#endif
