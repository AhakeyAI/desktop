#ifndef _MYKEY_H
#define _MYKEY_H

#include "main.h"
#include "multi_button.h"
#include "psk_led.h"

#include "custom_control.h"
#include "keyboard.h"
#include "math.h"
#include "mouse.h"
#include "touch_screen.h"

#define TOTAL_KEY 5
extern Button  keys[TOTAL_KEY];
extern uint8_t key_scan_code;
extern uint8_t mode_data;
extern uint8_t mode3_mode[TOTAL_KEY];
void           key_scan(void);
uint8_t        key_read(para i);
/**
 * @brief : 按键回调函数, index 按键下标
 * @note  :
 * @param {void} *button
 */
void key44callback(void *button);
void set_mode(uint8_t mode);
void my_button_init(void);
void prase_user_key(uint8_t *data, uint8_t len, uint8_t if_press);
#endif
