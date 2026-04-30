#include "CH58x_common.h"
void usb_EP2_send_report(uint8_t *report, uint8_t report_len);
void usb_EP1_send_report(uint8_t *report, uint8_t report_len);
void usb_set_desc(uint8_t *desc, uint8_t length);
void usb_set_name(uint8_t *desc, uint8_t length);
void usb_hid_kbd_init(void);

void usb_data_received(uint8_t *data, uint8_t len);
void usb_disconnect(void);
