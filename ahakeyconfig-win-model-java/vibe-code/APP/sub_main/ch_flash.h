#ifndef __FLASH_H
#define __FLASH_H

#include "main.h"

void eeprom_read_data(uint16_t addr, uint8_t *data, uint16_t len);
void eeprom_write_data(uint16_t addr, uint8_t *data, uint16_t len);
#endif
