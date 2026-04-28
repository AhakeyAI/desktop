/********************************** (C) COPYRIGHT
 ******************************** File Name          : main.c Author : WCH
 * Version            : V1.0
 * Date               : 2020/08/06
 * Description        : 蓝牙键盘应用主函数及任务系统初始化
 *********************************************************************************
 * Copyright (c) 2021 Nanjing Qinheng Microelectronics Co., Ltd.
 * Attention: This software (modified or not) and binary are used for
 * microcontroller manufactured by Nanjing Qinheng Microelectronics.
 *******************************************************************************/

/******************************************************************************/
/* 头文件包含 */
#include "CONFIG.h"
#include "HAL.h"
#include "hiddev.h"
#include "hidkbd.h"

/*********************************************************************
 * GLOBAL TYPEDEFS
 */
__attribute__((aligned(4))) uint32_t MEM_BUF[BLE_MEMHEAP_SIZE / 4];

#if (defined(BLE_MAC)) && (BLE_MAC == TRUE)
const uint8_t MacAddr[6] = {0x84, 0xC2, 0xE4, 0x03, 0x02, 0x02};
#endif

/*********************************************************************
 * @fn      Main_Circulation
 *
 * @brief   主循环
 *
 * @return  none
 */
__HIGH_CODE
__attribute__((noinline)) void Main_Circulation()
{
    while (1) {
        TMOS_SystemProcess();
    }
}

/*********************************************************************
 * @fn      main
 *
 * @brief   主函数
 *
 * @return  none
 */
int main(void)
{
#if (defined(DCDC_ENABLE)) && (DCDC_ENABLE == TRUE)
    PWR_DCDCCfg(ENABLE);
#endif
    SetSysClock(CLK_SOURCE_PLL_60MHz);
#if (defined(HAL_SLEEP)) && (HAL_SLEEP == TRUE)
    GPIOA_ModeCfg(GPIO_Pin_All, GPIO_ModeIN_PU);
    GPIOB_ModeCfg(GPIO_Pin_All, GPIO_ModeIN_PU);
#endif
#ifdef DEBUG
    GPIOPinRemap(ENABLE, RB_PIN_UART3);
    GPIOB_SetBits(bTXD3_);
    GPIOB_ModeCfg(bTXD3_, GPIO_ModeOut_PP_5mA);
    // GPIOA_SetBits(bTXD3);
    // GPIOA_ModeCfg(bTXD3, GPIO_ModeOut_PP_5mA);
    //    UART3_DefInit();
    UART3_BaudRateCfg(460800);
    R8_UART3_FCR = (2 << 6) | RB_FCR_TX_FIFO_CLR | RB_FCR_RX_FIFO_CLR | RB_FCR_FIFO_EN; // FIFO打开，触发点4字节
    R8_UART3_LCR = RB_LCR_WORD_SZ;
    R8_UART3_IER = RB_IER_TXD_EN;
    R8_UART3_DIV = 1;
#endif
    PRINT("start.%s\n", __TIME__);
    PRINT("%s\n", VER_LIB);
    sub_main_1();
    // CH58X_BLEInit();
    PSK_WCHBLE_Init();

    HAL_Init();
    GAPRole_PeripheralInit();
    HidDev_Init();
    HidEmu_Init();

    sub_main();
    PRINT("ALL init ok\n");
    Main_Circulation();
}

/******************************** endfile @ main ******************************/
