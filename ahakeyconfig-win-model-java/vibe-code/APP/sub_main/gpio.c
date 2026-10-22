#include "main.h"

void GPIO_SINGLE_INIT(char port, uint32_t pin, GPIOModeTypeDef mode) {
  if (port == GPIOA)
    GPIOA_ModeCfg(pin, mode);
  if (port == GPIOB)
    GPIOB_ModeCfg(pin, mode);
}
