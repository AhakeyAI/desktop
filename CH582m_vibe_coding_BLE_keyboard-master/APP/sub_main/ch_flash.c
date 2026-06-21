#include "ch_flash.h"
#define Per_page_size          32
#define Eeprom_circle_max_size (EEPROM_BLOCK_SIZE * 4)
int                                 lastdata_pos        = 0;
int                                 lastdata_pos_per128 = 0;
__attribute__((aligned(4))) uint8_t TestBuf[128];

uint16_t addr_offset;
void     eeprom_read_data(uint16_t addr, uint8_t *data, uint16_t len)
{
    uint32_t tmp = 0;
    if (addr + len > Per_page_size) {
        PRINT("page too long\n");
        len = Per_page_size - addr;
    }
    for (addr_offset = 0; addr_offset < Eeprom_circle_max_size; addr_offset += Per_page_size) {
        EEPROM_READ(addr_offset, &tmp, sizeof(tmp));
        if (tmp == 0xFFFFFFFF)
            break;
    }
    if (addr_offset == 0) {
        memset(data, 0, len);
        PRINT("NO data\n");
    } else {
        addr_offset -= Per_page_size;
        EEPROM_READ(addr_offset + addr, data, len);
        PRINT("read %x, len %d\n", addr_offset + addr, len);
        addr_offset += Per_page_size;
    }
}
/**
 * @brief :
 * @note  :
 * @param {uint8_t} *dat
 */
void eeprom_write_data(uint16_t addr, uint8_t *data, uint16_t len)
{
    uint32_t tmp = 0;
    if (addr + len > Per_page_size) {
        PRINT("page too long\n");
        len = Per_page_size - addr;
    }

    if (addr_offset >= Eeprom_circle_max_size) {
        uint8_t s = EEPROM_ERASE(0, Eeprom_circle_max_size);
        PRINT("EEPROM_ERASE=%02x\n", s);
        addr_offset = 0;
    }
    EEPROM_WRITE(addr_offset + addr, data, len);
    PRINT("write %x, len %d\n", addr_offset + addr, len);
}
