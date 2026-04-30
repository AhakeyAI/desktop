#include "psk_hid.h"
#include "hiddev.h"
#include "hidkbdservice.h"
#include "main.h"
static uint8_t data[64];

const uint8_t report_map_all[105] = {
    0x05,
    0x01, // USAGE_PAGE (Generic Desktop)
    0x09,
    0x06, // USAGE (Keyboard)
    0xa1,
    0x01, // COLLECTION (Application)
    0x85,
    1, // Report ID (8)
    0x05,
    0x07, //   USAGE_PAGE (Keyboard)
    0x19,
    0xe0, //   USAGE_MINIMUM (Keyboard LeftControl)
    0x29,
    0xe7, //   USAGE_MAXIMUM (Keyboard Right GUI)
    0x15,
    0x00, //   LOGICAL_MINIMUM (0)
    0x25,
    0x01, //   LOGICAL_MAXIMUM (1)
    0x75,
    0x01, //   REPORT_SIZE (1)
    0x95,
    0x08, //   REPORT_COUNT (8)
    0x81,
    0x02, //   INPUT (Data,Var,Abs)
    0x95,
    1, //   REPORT_COUNT (1)
    0x75,
    8, //   REPORT_SIZE (8)
    0x81,
    0x03, //   INPUT (Cnst,Var,Abs)

    0x95,
    0x05, //   REPORT_COUNT (5)
    0x75,
    0x01, //   REPORT_SIZE (1)
    0x05,
    0x08, //   USAGE_PAGE (LEDs)
    0x19,
    0x01, //   USAGE_MINIMUM (Num Lock)
    0x29,
    0x05, //   USAGE_MAXIMUM (Kana)
    0x91,
    0x02, //   OUTPUT (Data,Var,Abs)

    0x95,
    0x01, //   REPORT_COUNT (1)
    0x75,
    0x03, //   REPORT_SIZE (3)
    0x91,
    0x03, //   OUTPUT (Cnst,Var,Abs)

    // 0x95, 0x06, //   REPORT_COUNT (6)
    // 0x75, 0x08, //   REPORT_SIZE (8)
    // 0x15, 0x00, //   LOGICAL_MINIMUM (0)
    // 0x25, 0xFF, //   LOGICAL_MAXIMUM (255)
    // 0x05, 0x07, //   USAGE_PAGE (Keyboard)
    // 0x19, 0x00, //   USAGE_MINIMUM (Reserved (no event indicated))
    // 0x29, 0x65, //   USAGE_MAXIMUM (Keyboard Application)
    // 0x81, 0x00, //   INPUT (Data,Ary,Abs)

    0x05,
    0x07, //   Usage Page (Key Codes),
    0x95,
    0x78, //   Report Count (120),
    0x75,
    0x01, //   Report Size  (1),
    0x15,
    0x00, //   Logical Minimum (0),
    0x25,
    0x01, //   Logical Maximum (1),
    0x19,
    0x00, //   Usage Minimum (0),
    0x29,
    101, //   Usage Maximum (101),
    0x81,
    0x02, //   Input (Data, Variable, Absolute),

    0xc0, // END_COLLECTION

    // 0x05, 0x01, // USAGE_PAGE (Generic Desktop)
    // 0x09, 0x02, // USAGE (Mouse)
    // 0xa1, 0x01, // COLLECTION (Application)
    // 0x85, 0x02, // ??ID (2)
    // 0x09, 0x01, //   USAGE (Pointer)
    // 0xa1, 0x00, //   COLLECTION (Physical)
    // 0x05, 0x09, //     USAGE_PAGE (Button)
    // 0x19, 0x01, //     USAGE_MINIMUM (Button 1)
    // 0x29, 0x03, //     USAGE_MAXIMUM (Button 3)
    // 0x15, 0x00, //     LOGICAL_MINIMUM (0)
    // 0x25, 0x01, //     LOGICAL_MAXIMUM (1)
    // 0x95, 0x03, //     REPORT_COUNT (3)
    // 0x75, 0x01, //     REPORT_SIZE (1)
    // 0x81, 0x02, //     INPUT (Data,Var,Abs)
    // 0x95, 0x01, //     REPORT_COUNT (1)
    // 0x75, 0x05, //     REPORT_SIZE (5)
    // 0x81, 0x03, //     INPUT (Cnst,Var,Abs)
    // 0x05, 0x01, //     USAGE_PAGE (Generic Desktop)
    // 0x09, 0x30, //     USAGE (X)
    // 0x09, 0x31, //     USAGE (Y)
    // 0x09, 0x38, //     USAGE (Wheel)
    // 0x15, 0x81, //     LOGICAL_MINIMUM (-127)
    // 0x25, 0x7f, //     LOGICAL_MAXIMUM (127)
    // 0x75, 0x08, //     REPORT_SIZE (8)
    // 0x95, 0x03, //     REPORT_COUNT (3)
    // 0x81, 0x06, //     INPUT (Data,Var,Rel)
    // 0xc0,       //   END_COLLECTION
    // 0xc0,       // END_COLLECTION

    // 0x05, 0x0d,       // USAGE_PAGE (Digitizers)
    // 0x09, 0x04,       // USAGE (Touch Screen)
    // 0xa1, 0x01,       // COLLECTION (Application)
    // 0x85, 0x04,       // ??ID (4)
    // 0x09, 0x22,       //   USAGE (Finger)
    // 0xa1, 0x00,       //   COLLECTION (Physical)
    // 0x09, 0x42,       //     USAGE (Tip Switch)
    // 0x15, 0x00,       //     LOGICAL_MINIMUM (0)
    // 0x25, 0x01,       //     LOGICAL_MAXIMUM (1)
    // 0x75, 0x01,       //     REPORT_SIZE (1)
    // 0x95, 0x01,       //     REPORT_COUNT (1)
    // 0x81, 0x02,       //     INPUT (Data,Var,Abs)
    // 0x75, 0x07,       //     REPORT_SIZE (7)
    // 0x95, 0x01,       //     REPORT_COUNT (1)
    // 0x81, 0x03,       //     INPUT (Cnst,Var,Abs)
    // 0x05, 0x01,       //     USAGE_PAGE (Generic Desktop)
    // 0x09, 0x30,       //     USAGE (X)
    // 0x75, 0x10,       //     REPORT_SIZE (16)
    // 0x95, 0x01,       //     REPORT_COUNT (1)
    // 0x15, 0x00,       //     LOGICAL_MINIMUM (0)
    // 0x26, 0xff, 0x0f, //     LOGICAL_MAXIMUM (4095)
    // 0x35, 0x00,       //     PHYSICAL_MINIMUM (0)
    // 0x46, 0xff, 0x0f, //     PHYSICAL_MAXIMUM (4095)
    // 0x81, 0x02,       //     INPUT (Data,Var,Abs)
    // 0x09, 0x31,       //     USAGE (Y)
    // 0x95, 0x01,       //     REPORT_COUNT (1)
    // 0x75, 0x10,       //     REPORT_SIZE (16)
    // 0x15, 0x00,       //     LOGICAL_MINIMUM (0)
    // 0x26, 0xff, 0x0f, //     LOGICAL_MAXIMUM (4095)
    // 0x35, 0x00,       //     PHYSICAL_MINIMUM (0)
    // 0x46, 0xff, 0x0f, //     PHYSICAL_MAXIMUM (4095)
    // 0x81, 0x02,       //     INPUT (Data,Var,Abs)
    // 0xc0,             //   END_COLLECTION
    // 0xc0,             // END_COLLECTION

    0x05,
    0x0C, // 0   	GLOBAL_USAGE_PAGE(Consumer)
    0x09,
    0x01, // 2   	LOCAL_USAGE(	Consumer Control 	)
    0xA1,
    0x01, // 4   	MAIN_COLLECTION(Applicatior)
    0x85,
    0x05, // 6   	GLOBAL_REPORT_ID(5)
    0xA1,
    0x00, // 8   	MAIN_COLLECTION(Physical)
    0x09,
    0xE9, // 10  	LOCAL_USAGE(	Volume Increment 	)
    0x09,
    0xEA, // 12  	LOCAL_USAGE(	Volume Decrement 	)
    0x09,
    0xE2, // 14  	LOCAL_USAGE(	Mute 	)
    0x09,
    0xCD, // 16  	LOCAL_USAGE(	Play/Pause 	)
    0x35,
    0x00, // 18  	GLOBAL_PHYSICAL_MINIMUM(0)
    0x45,
    0x07, // 20  	GLOBAL_PHYSICAL_MAXIMUM(7)
    0x15,
    0x00, // 22  	GLOBAL_LOGICAL_MINIMUM(0)
    0x25,
    0x01, // 24  	GLOBAL_LOCAL_MAXIMUM(1)
    0x75,
    0x01, // 26  	GLOBAL_REPORT_SIZE(1)
    0x95,
    0x04, // 28  	GLOBAL_REPORT_COUNT(4)
    0x81,
    0x02, // 30  	MAIN_INPUT(data var absolute NoWrap linear
          // PreferredState NoNullPosition NonVolatile )	Input 0.4
    0x75,
    0x01, // 32  	GLOBAL_REPORT_SIZE(1)
    0x95,
    0x04, // 34  	GLOBAL_REPORT_COUNT(4)
    0x81,
    0x01, // 36  	MAIN_INPUT(const array absolute NoWrap linear
          // PreferredState NoNullPosition NonVolatile )	Input 1.0
    0xC0, // 38  	MAIN_COLLECTION_END
    0xC0, // 39  	MAIN_COLLECTION_END

    // 0x05, 0x01,       // USAGE_PAGE (Generic Desktop)
    // 0x15, 0x00,       // LOGICAL_MINIMUM (0)
    // 0x09, 0x04,       // USAGE (Joystick)
    // 0xa1, 0x01,       // COLLECTION (Application)
    // 0x85, 0x06,       // ??ID (6)
    // 0x05, 0x02,       //   USAGE_PAGE (Simulation Controls)
    // 0x09, 0xbb,       //   USAGE (Throttle)
    // 0x15, 0x81,       //   LOGICAL_MINIMUM (-127)
    // 0x25, 0x7f,       //   LOGICAL_MAXIMUM (127)
    // 0x75, 0x08,       //   REPORT_SIZE (8)
    // 0x95, 0x01,       //   REPORT_COUNT (1)
    // 0x81, 0x02,       //   INPUT (Data,Var,Abs)
    // 0x05, 0x01,       //   USAGE_PAGE (Generic Desktop)
    // 0x09, 0x01,       //   USAGE (Pointer)
    // 0xa1, 0x00,       //   COLLECTION (Physical)
    // 0x09, 0x30,       //     USAGE (X)
    // 0x09, 0x31,       //     USAGE (Y)
    // 0x95, 0x02,       //     REPORT_COUNT (2)
    // 0x81, 0x02,       //     INPUT (Data,Var,Abs)
    // 0xc0,             //   END_COLLECTION
    // 0x09, 0x39,       //   USAGE (Hat switch)
    // 0x15, 0x00,       //   LOGICAL_MINIMUM (0)
    // 0x25, 0x03,       //   LOGICAL_MAXIMUM (3)
    // 0x35, 0x00,       //   PHYSICAL_MINIMUM (0)
    // 0x46, 0x0e, 0x01, //   PHYSICAL_MAXIMUM (270)
    // 0x65, 0x14,       //   UNIT (Eng Rot:Angular Pos)
    // 0x75, 0x04,       //   REPORT_SIZE (4)
    // 0x95, 0x01,       //   REPORT_COUNT (1)
    // 0x81, 0x02,       //   INPUT (Data,Var,Abs)
    // 0x05, 0x09,       //   USAGE_PAGE (Button)
    // 0x19, 0x01,       //   USAGE_MINIMUM (Button 1)
    // 0x29, 0x04,       //   USAGE_MAXIMUM (Button 4)
    // 0x15, 0x00,       //   LOGICAL_MINIMUM (0)
    // 0x25, 0x01,       //   LOGICAL_MAXIMUM (1)
    // 0x75, 0x01,       //   REPORT_SIZE (1)
    // 0x95, 0x04,       //   REPORT_COUNT (4)
    // 0x55, 0x00,       //   UNIT_EXPONENT (0)
    // 0x65, 0x00,       //   UNIT (None)
    // 0x81, 0x02,       //   INPUT (Data,Var,Abs)
    // 0xc0,             // END_COLLECTION

    // 0x05,
    // 0x8c, /* USAGE_PAGE (ST Page) */
    // 0x09,
    // 0x01, /* USAGE (Demo Kit) */
    // 0xa1,
    // 0x01, /* COLLECTION (Application) */
    // 0x85,
    // 0x07, // 6   	GLOBAL_REPORT_ID(7)

    // // The Input report
    // 0x09,
    // 0x03, // USAGE ID - Vendor defined
    // 0x15,
    // 0x00, // LOGICAL_MINIMUM (0)
    // 0x26,
    // 0x00,
    // 0xFF, // LOGICAL_MAXIMUM (255)
    // 0x75,
    // 0x08, // REPORT_SIZE (8bit)
    // 0x95,
    // 64,   // REPORT_COUNT (64Byte)
    // 0x81,
    // 0x02, // INPUT (Data,Var,Abs)

    // // The Output report
    // 0x09, 0x04,                  // USAGE ID - Vendor defined
    // 0x15, 0x00,                  // LOGICAL_MINIMUM (0)
    // 0x26, 0x00, 0xFF,            // LOGICAL_MAXIMUM (255)
    // 0x75, 0x08,                  // REPORT_SIZE (8bit)
    // 0x95, CUSTOM_HID_EPOUT_SIZE, // REPORT_COUNT (64Byte)
    // 0x91, 0x02,                  // OUTPUT (Data,Var,Abs)

    // 0x05, 0x01, // USAGE_PAGE (Generic Desktop)
    // 0x09, 0x06, // USAGE (Keyboard)
    // 0xa1, 0x01, // COLLECTION (Application)
    // 0x85, 1,    // Report ID (8)
    // 0x05, 0x07, //   USAGE_PAGE (Keyboard)
    // 0x19, 0xe0, //   USAGE_MINIMUM (Keyboard LeftControl)
    // 0x29, 0xe7, //   USAGE_MAXIMUM (Keyboard Right GUI)
    // 0x15, 0x00, //   LOGICAL_MINIMUM (0)
    // 0x25, 0x01, //   LOGICAL_MAXIMUM (1)
    // 0x75, 0x01, //   REPORT_SIZE (1)
    // 0x95, 0x08, //   REPORT_COUNT (8)
    // 0x81, 0x02, //   INPUT (Data,Var,Abs)
    // 0x95, 0x01, //   REPORT_COUNT (1)
    // 0x75, 0x08, //   REPORT_SIZE (8)
    // 0x81, 0x03, //   INPUT (Cnst,Var,Abs)

    // 0x95, 0x05, //   REPORT_COUNT (5)
    // 0x75, 0x01, //   REPORT_SIZE (1)
    // 0x05, 0x08, //   USAGE_PAGE (LEDs)
    // 0x19, 0x01, //   USAGE_MINIMUM (Num Lock)
    // 0x29, 0x05, //   USAGE_MAXIMUM (Kana)
    // 0x91, 0x02, //   OUTPUT (Data,Var,Abs)

    // 0x95, 0x01, //   REPORT_COUNT (1)
    // 0x75, 0x03, //   REPORT_SIZE (3)
    // 0x91, 0x03, //   OUTPUT (Cnst,Var,Abs)

    // // 0x95, 0x06, //   REPORT_COUNT (6)
    // // 0x75, 0x08, //   REPORT_SIZE (8)
    // // 0x15, 0x00, //   LOGICAL_MINIMUM (0)
    // // 0x25, 0xFF, //   LOGICAL_MAXIMUM (255)
    // // 0x05, 0x07, //   USAGE_PAGE (Keyboard)
    // // 0x19, 0x00, //   USAGE_MINIMUM (Reserved (no event indicated))
    // // 0x29, 0x65, //   USAGE_MAXIMUM (Keyboard Application)
    // // 0x81, 0x00, //   INPUT (Data,Ary,Abs)

    // 0x05, 0x07, //   Usage Page (Key Codes),
    // 0x95, 0x78, //   Report Count (120),
    // 0x75, 0x01, //   Report Size  (1),
    // 0x15, 0x00, //   Logical Minimum (0),
    // 0x25, 0x01, //   Logical Maximum (1),
    // 0x19, 0x00, //   Usage Minimum (0),
    // 0x29, 120,  //   Usage Maximum (120),
    // 0x81, 0x02, //   Input (Data, Variable, Absolute),
    // 0xc0,       // END_COLLECTION

    // /* USER CODE END 0 */
    // 0xC0 /*     END_COLLECTION	             */

    // 0x05, 0x01, // Usage Pg (Generic Desktop)
    // 0x09, 0x06, // Usage (Keyboard)
    // 0xA1, 0x01, // Collection: (Application)
    //             //
    // 0x05, 0x07, // Usage Pg (Key Codes)
    // 0x19, 0xE0, // Usage Min (224)
    // 0x29, 0xE7, // Usage Max (231)
    // 0x15, 0x00, // Log Min (0)
    // 0x25, 0x01, // Log Max (1)
    //             //
    //             // Modifier byte
    // 0x75, 0x01, // Report Size (1)
    // 0x95, 0x08, // Report Count (8)
    // 0x81, 0x02, // Input: (Data, Variable, Absolute)
    //             //
    //             // Reserved byte
    // 0x95, 0x01, // Report Count (1)
    // 0x75, 0x08, // Report Size (8)
    // 0x81, 0x01, // Input: (Constant)
    //             //
    //             // LED report
    // 0x95, 0x05, // Report Count (5)
    // 0x75, 0x01, // Report Size (1)
    // 0x05, 0x08, // Usage Pg (LEDs)
    // 0x19, 0x01, // Usage Min (1)
    // 0x29, 0x05, // Usage Max (5)
    // 0x91, 0x02, // Output: (Data, Variable, Absolute)
    //             //
    //             // LED report padding
    // 0x95, 0x01, // Report Count (1)
    // 0x75, 0x03, // Report Size (3)
    // 0x91, 0x01, // Output: (Constant)
    //             //
    //             // Key arrays (6 bytes)
    // 0x95, 0x06, // Report Count (6)
    // 0x75, 0x08, // Report Size (8)
    // 0x15, 0x00, // Log Min (0)
    // 0x25, 0x65, // Log Max (101)
    // 0x05, 0x07, // Usage Pg (Key Codes)
    // 0x19, 0x00, // Usage Min (0)
    // 0x29, 0x65, // Usage Max (101)
    // 0x81, 0x00, // Input: (Data, Array)
    //             //
    // 0xC0        // End Collection
};
// uint8_t report_map_all_size = sizeof(report_map_all);

// clang-format off
const uint8_t report_map_six_key[63] = {
    // 0x05, 0x01, // USAGE_PAGE (Generic Desktop)
    // 0x09, 0x06, // USAGE (Keyboard)
    // 0xa1, 0x01, // COLLECTION (Application)
    // 0x05, 0x07, //   USAGE_PAGE (Keyboard)
    // 0x19, 0xe0, //   USAGE_MINIMUM (Keyboard LeftControl)
    // 0x29, 0xe7, //   USAGE_MAXIMUM (Keyboard Right GUI)
    // 0x15, 0x00, //   LOGICAL_MINIMUM (0)
    // 0x25, 0x01, //   LOGICAL_MAXIMUM (1)
    // 0x75, 0x01, //   REPORT_SIZE (1)
    // 0x95, 0x08, //   REPORT_COUNT (8)
    // 0x81, 0x02, //   INPUT (Data,Var,Abs)
    // 0x95, 0x01, //   REPORT_COUNT (1)
    // 0x75, 0x08, //   REPORT_SIZE (8)
    // 0x81, 0x03, //   INPUT (Cnst,Var,Abs)
    // 0x95, 0x05, //   REPORT_COUNT (5)
    // 0x75, 0x01, //   REPORT_SIZE (1)
    // 0x05, 0x08, //   USAGE_PAGE (LEDs)
    // 0x19, 0x01, //   USAGE_MINIMUM (Num Lock)
    // 0x29, 0x05, //   USAGE_MAXIMUM (Kana)
    // 0x91, 0x02, //   OUTPUT (Data,Var,Abs)
    // 0x95, 0x01, //   REPORT_COUNT (1)
    // 0x75, 0x03, //   REPORT_SIZE (3)
    // 0x91, 0x03, //   OUTPUT (Cnst,Var,Abs)
    // 0x95, 0x06, //   REPORT_COUNT (6)
    // 0x75, 0x08, //   REPORT_SIZE (8)
    // 0x15, 0x00, //   LOGICAL_MINIMUM (0)
    // 0x25, 0x65, //   LOGICAL_MAXIMUM (101)
    // 0x05, 0x07, //   USAGE_PAGE (Keyboard)
    // 0x19, 0x00, //   USAGE_MINIMUM (Reserved (no event indicated))
    // 0x29, 0x65, //   USAGE_MAXIMUM (Keyboard Application)
    // 0x81, 0x00, //   INPUT (Data,Ary,Abs)
    // 0xc0        // END_COLLECTION

    0x05, 0x01, // Usage Pg (Generic Desktop)
    0x09, 0x06, // Usage (Keyboard)
    0xA1, 0x01, // Collection: (Application)
                //
    0x05, 0x07, // Usage Pg (Key Codes)
    0x19, 0xE0, // Usage Min (224)
    0x29, 0xE7, // Usage Max (231)
    0x15, 0x00, // Log Min (0)
    0x25, 0x01, // Log Max (1)
                //
                // Modifier byte
    0x75, 0x01, // Report Size (1)
    0x95, 0x08, // Report Count (8)
    0x81, 0x02, // Input: (Data, Variable, Absolute)
                //
                // Reserved byte
    0x95, 0x01, // Report Count (1)
    0x75, 0x08, // Report Size (8)
    0x81, 0x01, // Input: (Constant)
                //
                // LED report
    0x95, 0x05, // Report Count (5)
    0x75, 0x01, // Report Size (1)
    0x05, 0x08, // Usage Pg (LEDs)
    0x19, 0x01, // Usage Min (1)
    0x29, 0x05, // Usage Max (5)
    0x91, 0x02, // Output: (Data, Variable, Absolute)
                //
                // LED report padding
    0x95, 0x01, // Report Count (1)
    0x75, 0x03, // Report Size (3)
    0x91, 0x01, // Output: (Constant)
                //
                // Key arrays (6 bytes)
    0x95, 0x06, // Report Count (6)
    0x75, 0x08, // Report Size (8)
    0x15, 0x00, // Log Min (0)
    0x25, 0x6d, // Log Max (101)
    0x05, 0x07, // Usage Pg (Key Codes)
    0x19, 0x00, // Usage Min (0)
    0x29, 0x6d, // Usage Max (101)
    0x81, 0x00, // Input: (Data, Array)
                //
    0xC0        // End Collection

};
// clang-format on

// uint8_t report_size = sizeof(report_map_all);

/**
 * @brief :ÔÚ usbd_customhid.c USBD_CUSTOM_HID_DataOut(...)
 * @param {uint8_t} rx_data
 */
void hid_rx_iqr(uint8_t rx_data[64])
{
    if (rx_data[0] == 0x01) // ¼üÅÌµÆ×´Ì¬
    {
        memcpy((uint8_t *) &keyboard_led_state, rx_data + 1, 1);
    } else {
        memcpy(data, rx_data, 64);
    }
}

void MY_USB_HID_SEND_REPORT(uint8_t *report, uint16_t len)
{
    if (keyboard_state.kbd_is_onereport == 1) {
        if (*report != 0x01)
            return;
        else {
            report++;
            len--;
        }
    }
    // if (running_data.bt_connect_stat == 2)
    {
        // if (running_data.usb_is_connected == 0) {
        if (1) {
            if (running_data.bt_connect_stat == 2) {
                HidDev_Report(HID_RPT_ID_KEY_IN, HID_REPORT_TYPE_INPUT, len, report);
            } else {
            }
        } else {
            // PRINT("21\n");
            // if (*report == 0x01)
            // u2dev_update_report(report + 1, len - 1);
            // PRINT("USB\n");
            // usb_EP1_send_report(report, len);
        }
    }
#ifdef USING_CUSTOM_HID
    // USBD_CUSTOM_HID_SendReport_FS((uint8_t *)report, (uint16_t)len);
    extern USBD_HandleTypeDef hUsbDeviceFS;
    USBD_CUSTOM_HID_SendReport(&hUsbDeviceFS, report, len);
#else
#endif
}
