#ifndef _PSK_HID
#define _PSK_HID

#define SEND_DELAY 5
#define __weak
#define KEYBOARD_WITH_LWRB
// #define MOUSE_USING_PID

// #define USING_CUSTOM_HID

#include "CONFIG.h"
// #include "usb_device.h"
#include "string.h"
void hid_rx_iqr(uint8_t rx_data[64]);
void MY_USB_HID_SEND_REPORT(uint8_t *report, uint16_t len);
#ifdef USING_CUSTOM_HID
#include "usbd_customhid.h"
#endif

extern const uint8_t report_map_all[105];
extern const uint8_t report_map_six_key[63];

extern uint8_t rf_send_data[66];

#include "custom_control.h"
#include "keyboard.h"
#include "mouse.h"
#include "touch_screen.h"
#endif
