#include "main.h"

#define GPIOA            'A'
#define GPIOB            'B'
#define GPIOC            'C'
#define GPIO_Mode_Out_PP GPIO_ModeOut_PP_5mA
#define GPIO_Mode_IPU    GPIO_ModeIN_PU
#define GPIO_Mode_IPD    GPIO_ModeIN_PD

void GPIO_SINGLE_INIT(char port, uint32_t pin, GPIOModeTypeDef mode);

#define LL_GPIO_SetOutputPin(port, pin)   (port == 'A') ? GPIOA_SetBits(pin) : GPIOB_SetBits(pin);
#define LL_GPIO_ResetOutputPin(port, pin) (port == 'A') ? GPIOA_ResetBits(pin) : GPIOB_ResetBits(pin);

#define LL_GPIO_IsInputPinSet(port, pin)  (((port == 'A') ? GPIOA_ReadPortPin(pin) : GPIOB_ReadPortPin(pin)) > 0)
