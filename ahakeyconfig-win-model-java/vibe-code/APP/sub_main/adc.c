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
 *Internal temperature sensor routine:
 *Through the ADC channel 16, the output voltage value and temperature value of
 *the internal temperature sensor are collected.
 *
 */

#include "adc.h"
#include "main.h"
/* Global Variable */
s16 RoughCalib_Value = 0;

/*********************************************************************
 * @fn      BP_ADC_Init
 *
 * @brief   Initializes ADC collection.
 *
 * @return  none
 */
void BP_ADC_Init(void) {
  GPIOA_ModeCfg(GPIO_Pin_4, GPIO_ModeIN_Floating);
  ADC_ExtSingleChSampInit(SampleFreq_3_2, ADC_PGA_0);
  RoughCalib_Value = ADC_DataCalib_Rough(); // 用于计算ADC内部偏差，记录到全局变量
                                            // RoughCalib_Value中
  PRINT("adc cel =%d \n", RoughCalib_Value);
  PRINT("%s\n", __TIME__);
  ADC_ChannelCfg(CH_EXTIN_0);
}

/*********************************************************************
 * @fn      Get_ADC_Val
 *
 * @brief   Returns ADCx conversion result data.
 *
 * @param   ch - ADC channel.
 *            ADC_Channel_0 - ADC Channel0 selected.
 *            ADC_Channel_1 - ADC Channel1 selected.
 *            ADC_Channel_2 - ADC Channel2 selected.
 *            ADC_Channel_3 - ADC Channel3 selected.
 *            ADC_Channel_4 - ADC Channel4 selected.
 *            ADC_Channel_5 - ADC Channel5 selected.
 *            ADC_Channel_6 - ADC Channel6 selected.
 *            ADC_Channel_7 - ADC Channel7 selected.
 *            ADC_Channel_8 - ADC Channel8 selected.
 *            ADC_Channel_9 - ADC Channel9 selected.
 *            ADC_Channel_10 - ADC Channel10 selected.
 *            ADC_Channel_11 - ADC Channel11 selected.
 *            ADC_Channel_12 - ADC Channel12 selected.
 *            ADC_Channel_13 - ADC Channel13 selected.
 *            ADC_Channel_14 - ADC Channel14 selected.
 *            ADC_Channel_15 - ADC Channel15 selected.
 *            ADC_Channel_16 - ADC Channel16 selected.
 *            ADC_Channel_17 - ADC Channel17 selected.
 *
 * @return  none
 */
u16 Get_ADC_Val(u8 ch) {
  u16 val;

  val = ADC_ExcutSingleConver() + RoughCalib_Value;
  return val;
}

/*********************************************************************
 * @fn      Get_ADC_Average
 *
 * @brief   Returns ADCx conversion result average data.
 *
 * @param   ch - ADC channel.
 *            ADC_Channel_0 - ADC Channel0 selected.
 *            ADC_Channel_1 - ADC Channel1 selected.
 *            ADC_Channel_2 - ADC Channel2 selected.
 *            ADC_Channel_3 - ADC Channel3 selected.
 *            ADC_Channel_4 - ADC Channel4 selected.
 *            ADC_Channel_5 - ADC Channel5 selected.
 *            ADC_Channel_6 - ADC Channel6 selected.
 *            ADC_Channel_7 - ADC Channel7 selected.
 *            ADC_Channel_8 - ADC Channel8 selected.
 *            ADC_Channel_9 - ADC Channel9 selected.
 *            ADC_Channel_10 - ADC Channel10 selected.
 *            ADC_Channel_11 - ADC Channel11 selected.
 *            ADC_Channel_12 - ADC Channel12 selected.
 *            ADC_Channel_13 - ADC Channel13 selected.
 *            ADC_Channel_14 - ADC Channel14 selected.
 *            ADC_Channel_15 - ADC Channel15 selected.
 *            ADC_Channel_16 - ADC Channel16 selected.
 *            ADC_Channel_17 - ADC Channel17 selected.
 *
 * @return  val - The Data conversion value.
 */
u16 Get_ADC_Average(u8 ch, u8 times) {
  u32 temp_val = 0;
  u8 t;
  u16 val;

  for (t = 0; t < times; t++) {
    temp_val += Get_ADC_Val(ch);
    // Delay_Ms(5);
  }

  val = temp_val / times;

  return val;
}

/*********************************************************************
 * @fn      Get_ConversionVal
 *
 * @brief   Get Conversion Value.
 *
 * @param   val - Sampling value
 *
 * @return  val+Calibrattion_Val - Conversion Value.
 */
u16 Get_ConversionVal(s16 val) {
  if ((val + RoughCalib_Value) < 0)
    return 0;
  if ((RoughCalib_Value + val) > 4095)
    return 4095;
  return (val + RoughCalib_Value);
}
