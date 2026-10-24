#ifndef __adc
#define __adc

#include "main.h"
u16 Get_ADC_Average(u8 ch, u8 times);
#define read_vbat_adc() Get_ADC_Average(0, 2)
void BP_ADC_Init(void);

#endif