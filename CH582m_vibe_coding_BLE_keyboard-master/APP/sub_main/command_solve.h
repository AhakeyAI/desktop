#ifndef __COMM_SOL_H
#define __COMM_SOL_H
#include "CONFIG.h"
#include "HAL.h"
#include "lwrb.h"

void receive_bytes(uint8_t *d, uint32_t len);
void command_process(uint8_t *d, uint32_t len);
void command_process_ok(void);
void command_data_buf_init(void);
void command_return(uint8_t id, uint8_t code);
void command_return_state(void);

extern lwrb_t   ble_data_lwrb;
extern uint8_t *command_data;
extern uint16_t command_len;
extern uint8_t  command_in_process;
#endif
