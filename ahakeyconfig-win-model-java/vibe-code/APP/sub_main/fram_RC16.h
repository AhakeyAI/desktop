#include "main.h"

void fram_init(void);
void fram_write(uint16_t addr, uint8_t *data, uint16_t len);
void fram_read(uint16_t addr, uint8_t *data, uint16_t len);
void save_all_data_to_fram(void);
void save_key_bound_data(void);
