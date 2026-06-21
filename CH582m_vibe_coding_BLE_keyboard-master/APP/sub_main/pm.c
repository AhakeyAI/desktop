/********************************** (C) COPYRIGHT
 ******************************** File Name          : main.c Author : WCH
 * Version            : V1.0.0
 * Date               : 2021/06/06
 * Description        : Main program body.
 *********************************************************************************
 * Copyright (c) 2021 Nanjing Qinheng Microelectronics Co., Ltd.
 * Attention: This software (modified or not) and binary are used for
 * microcontroller manufactured by Nanjing Qinheng Microelectronics.
 *******************************************************************************/

/*
 *@Note
 *low power, standby mode routine:
 *WKUP(PA0)
 *This routine demonstrates that WFI enters the standby mode, the rising edge of
 *the WKUP (PA0) pin exits the standby mode,Program reset after wake-up.
 *Note: In order to reduce power consumption as much as possible, it is
 *recommended to set the unused GPIO to pull-down mode.
 *
 */

#include "main.h"

/* Global define */

void power_reset(uint8_t data_to_save_in_reg)
{
    save_all_data_to_fram();
    SYS_ResetKeepBuf(data_to_save_in_reg);
    SYS_ResetExecute();
}
/* Global Variable */
// __HIGH_CODE
void power_deep_sleep(void) {}
