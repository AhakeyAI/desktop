/*
 * buzzerDriver.c
 *
 *  Created on: Feb 22, 2019
 *      Author: lukasz
 */
#include "main.h"
// #include "stdint.h"
#include "buzzerDriver.h"
#include "melody.h"
// #include "stdbool.h"
// // #include "mymath.h"
// #include "stdio.h"

#define CPU_FREQ  48000000
#define PRESCALER 1

music_state_s music_state;

u8 music_volume = 3;

/*
 * Buzzer driver init
 */
void buzzerDriverInit(void)
{
    GPIOAGPPCfg(DISABLE, RB_PIN_XT32K_IE);
    GPIOA_ResetBits(GPIO_Pin_10); // 配置PWM口 PA10
    GPIOA_ModeCfg(GPIO_Pin_10, GPIO_ModeOut_PP_5mA);
    TMR1_PWMInit(High_Level, PWM_Times_1);
    TMR1_PWMCycleCfg(6000);  // 周期 100us
    TMR1_Disable();
    TMR1_PWMActDataWidth(0); // 占空比 50%, 修改占空比必须暂时关闭定时器
    TMR1_PWMEnable();
    TMR1_Enable();
}

const uint32_t bibi__Melody1[]  = {NOTE_D6, 0, NOTE_D6, 0};
const uint32_t bibiDuration1[]  = {1, 1, 1, 1};
const uint32_t disc__Melody1[]  = {NOTE_D6, NOTE_D4, 0};
const uint32_t discDuration1[]  = {1, 6, 1};
const uint32_t p_off__Melody1[] = {NOTE_A6, 0};
const uint32_t p_offDuration1[] = {100, 1};

void start_music(int x)
{
    if (x == 0) {
        music_state.music_play = MUS_STOP;
        music_state.notes      = bibi__Melody1;
        music_state.durat      = bibiDuration1;
        music_state.note_sum   = ARRAY_SIZE(bibi__Melody1);
        music_state.note_curr  = 0;
        music_state.music_play = MUS_cus;
    } else if (x == 1) {
        music_state.music_play = MUS_STOP;
        music_state.notes      = disc__Melody1;
        music_state.durat      = discDuration1;
        music_state.note_sum   = ARRAY_SIZE(disc__Melody1);
        music_state.note_curr  = 0;
        music_state.music_play = MUS_cus;
    } else if (x == 3) {
        music_state.music_play = MUS_STOP;
        music_state.notes      = p_off__Melody1;
        music_state.durat      = p_offDuration1;
        music_state.note_sum   = ARRAY_SIZE(p_off__Melody1);
        music_state.note_curr  = 0;
        music_state.music_play = MUS_cus;
    } else if (x == 4) {
        music_state.music_play = MUS_STOP;
        // music_state.music_play = MUS_3;
    }
}

/*
 * 	Set new frequency
 *
 * 	args:
 * 	newFreq - new frequency in Hz.
 */
void buzzerSetNewFrequency(uint32_t newFreq)
{
    //	__ExecuteOnce(buzzerDriverInit());
    static uint32_t last_frc;
    if (last_frc == newFreq)
        return;
    last_frc          = newFreq;
    uint64_t tempFreq = newFreq;
    TMR1_Disable();
    // TMR1_PWMCycleCfg(6000);	  // 周期 100us
    // TMR1_PWMActDataWidth(10); // 占空比 50%, 修改占空比必须暂时关闭定时器

    if (newFreq != 0) {
        uint16_t tempNewValue = ((uint64_t) CPU_FREQ / PRESCALER) / tempFreq;
        // tempNewValue = 4999;
        // PRINT("arr %ld\n", tempNewValue);
        // setting new value
        // TIM1->ARR = (uint32_t)tempNewValue;
        // TIM1->CCR1 = (uint32_t)tempNewValue / music_volume;
        // TIM1->CCR1 = 10;
        TMR1_PWMCycleCfg(tempNewValue);                    // 周期 100us
        TMR1_PWMActDataWidth(tempNewValue / music_volume); // 占空比 50%, 修改占空比必须暂时关闭定时器
        TMR1_Enable();
        // TIM_SetAutoreload(TIM3, tempNewValue);
        // TIM_SetCompare2(TIM3, tempNewValue / music_volume);
    } else {
        TMR1_PWMActDataWidth(0); // 占空比 50%, 修改占空比必须暂时关闭定时器
        TMR1_Enable();
        // TIM_SetCompare2(TIM3, 0);

        // TIM1->CCR1 = 0;
    }
}
void buzzerSetNewFrequency2(uint32_t newFreq)
{
#if 0
	__ExecuteOnce(buzzerDriverInit());
	uint64_t tempFreq = newFreq;
	if(newFreq != 0){

	uint64_t tempNewValue = (uint64_t) CPU_FREQ / PRESCALER / tempFreq;

	// setting new value
	TIM12 ->ARR = (uint32_t)tempNewValue;
	TIM12 -> CCR2 = (uint32_t)tempNewValue/2;
	}
	else{
		TIM12 -> CCR2 = 0;
	}
#endif
}

// void musicPlay()
//{
//	__ExecuteOnce(buzzerDriverInit());

//  TIM9 -> CR1 |= TIM_CR1_CEN;
//  TIM9 ->CCER |= TIM_CCER_CC4E;

//  int melodyCount = sizeof(melodySizes)/ sizeof(uint32_t);

//  for(int melodyIndex = 0; melodyIndex < melodyCount; melodyIndex++)
//  {
//	  for(int noteIndex = 0; noteIndex < melodySizes[melodyIndex];
//noteIndex++)
//  	  {
//	  	  buzzerSetNewFrequency(melody[melodyIndex][noteIndex]);
//	  	  HAL_Delay(noteDurations[melodyIndex][noteIndex] *
//melodySlowfactor[melodyIndex]);
//  	  }
//  }
//   TIM9 -> CR1 &= ~TIM_CR1_CEN;
//   TIM9 ->CCER &= ~TIM_CCER_CC4E;
//}
// 非堵塞
// void musicPlay()
// {
// 	__ExecuteOnce(buzzerDriverInit());
// 	__ExecuteOnce(TIM8 -> CR1 |= TIM_CR1_CEN);
// 	__ExecuteOnce(TIM8 ->CCER |= TIM_CCER_CC4E);
// //  TIM9 -> CR1 |= TIM_CR1_CEN;
// //  TIM9 ->CCER |= TIM_CCER_CC4E;
// 	static uint32_t cnt_=0;
// //  static int melodyCount = sizeof(melodySizes)/ sizeof(uint32_t);
// //	static int melodyIndex = 0;
// 	static int noteIndex = 0;
// 	if( noteIndex >= melodySizes[0]) noteIndex=0;
// 	if(cnt_++%(noteDurations[0][noteIndex] /** melodySlowfactor[0]*/)==0)
// 	{

// 		buzzerSetNewFrequency(melody[0][noteIndex]);

// 		noteIndex++;
// //			HAL_Delay(noteDurations[melodyIndex][noteIndex] *
// melodySlowfactor[melodyIndex]);

// 	}
// //	__ValueStep(melodyIndex,1,melodyCount);
// //   TIM9 -> CR1 &= ~TIM_CR1_CEN;
// //   TIM9 ->CCER &= ~TIM_CCER_CC4E;
// }
// void music2Play()//堵塞式
//{
//	__ExecuteOnce(buzzerDriverInit());
//	__ExecuteOnce(TIM8 -> CR1 |= TIM_CR1_CEN);
//	__ExecuteOnce(TIM8 ->CCER |= TIM_CCER_CC4E);
//  int melodyCount = sizeof(melodySizes2)/ sizeof(uint32_t);

//  for(int melodyIndex = 0; melodyIndex < melodyCount; melodyIndex++)
//  {
//	  for(int noteIndex = 0; noteIndex < melodySizes2[melodyIndex];
//noteIndex++)
//  	  {
//	  	  buzzerSetNewFrequency(melody2[melodyIndex][noteIndex]);
//	  	  delay_ms((u16)(noteDurations2[melodyIndex][noteIndex] *
//melodySlowfactor[melodyIndex]));
//  	  }
//  }

//}

void music3Play()
{
#if 0
	__ExecuteOnce(buzzerDriverInit());
	__ExecuteOnce(TIM9 -> CR1 |= TIM_CR1_CEN);
	__ExecuteOnce(TIM9 ->CCER |= TIM_CCER_CC4E);
	__ExecuteOnce(TIM12 -> CR1 |= TIM_CR1_CEN);
	__ExecuteOnce(TIM12 ->CCER |= TIM_CCER_CC4E);
	
	static uint32_t cnt_=0;
	static uint32_t cnt2_=0;
	
//  static int melodyCount = sizeof(melodySizes)/ sizeof(uint32_t);
//	static int melodyIndex = 0;
	static int noteIndex = 0;
	static int noteIndex2 = 0;
	
	if( noteIndex >= melodySizes3[0]) noteIndex=0;
	if( noteIndex2 >= melodySizes3_2[0]) noteIndex2=0;
	
	if(cnt_++%(noteDurations3[0][noteIndex] * melodySlowfactor[0])==0){
		buzzerSetNewFrequency(melody3twincle[0][noteIndex]);
		noteIndex++;
	}
	if(cnt2_++%(noteDurations3_2[0][noteIndex2] * melodySlowfactor[0])==0){
		buzzerSetNewFrequency2(melody3twincle2[0][noteIndex2]);
		noteIndex2++;
	}
//	__ValueStep(melodyIndex,1,melodyCount);
//   TIM9 -> CR1 &= ~TIM_CR1_CEN;
//   TIM9 ->CCER &= ~TIM_CCER_CC4E;
#endif
}

// 非堵塞
//  void music4Play()
//  {
//  	__ExecuteOnce(buzzerDriverInit());
//  	__ExecuteOnce(TIM14->CR1 |= TIM_CR1_CEN);
//  	__ExecuteOnce(TIM14->CCER |= TIM_CCER_CC4E);
//  	//  TIM9 -> CR1 |= TIM_CR1_CEN;
//  	//  TIM9 ->CCER |= TIM_CCER_CC4E;
//  	static uint32_t cnt_ = 0;
//  	//  static int melodyCount = sizeof(melodySizes)/ sizeof(uint32_t);
//  	//	static int melodyIndex = 0;
//  	static int noteIndex = 0;
//  	if (noteIndex >= melodySizes4[0])
//  		noteIndex = 0;

// 	buzzerSetNewFrequency(melody4[0][noteIndex]);

// 	if (cnt_++ % (noteDurations4[0][noteIndex] * (melodySlowfactor[0] - 7))
// == 0)
// 	{
// 		noteIndex++;
// 		//		if(noteIndex%8==2)
// 		//			buzzer_flag=1;
// 	}
// }

/*
非堵塞
定时调用music5_ticks
通过标志位music5_play_flag来控制播放的开始
置位music5_play_flag，可以非堵塞地播放一遍提示音
播放完之后函数自动将标志位清零

音效：诺基亚关机？
*/
// char music5_play_flag = 0;
// void music5_ticks()
// {
// 	static uint32_t cnt_ = 0;
// 	static int noteIndex = 0;
// 	if (!music5_play_flag)
// 		return;
// 	if (noteIndex >= melodySizes5[0])
// 	{
// 		music5_play_flag = 0;
// 		noteIndex = 0;
// 		cnt_ = 0;
// 		return;
// 	}
// 	buzzerSetNewFrequency(melody5[0][noteIndex]);
// 	if (cnt_++ % ((noteDurations5[0][noteIndex] * (melodySlowfactor[0] - 4))
// / 2) == 0)
// 	{
// 		noteIndex++;
// 		//		if(noteIndex%8==2)
// 		//			buzzer_flag=1;
// 	}
// }
// char music5_1_play_flag = 0;
// /*
// 音效：诺基亚开机？
// */
// void music5_1_ticks()
// {
// 	static uint32_t cnt_ = 0;
// 	static int noteIndex = 0;
// 	if (!music5_1_play_flag)
// 		return;
// 	if (noteIndex >= melodySizes5_1[0])
// 	{
// 		music5_1_play_flag = 0;
// 		noteIndex = 0;
// 		cnt_ = 0;
// 		return;
// 	}
// 	buzzerSetNewFrequency(melody5_1[0][noteIndex]);
// 	if (cnt_++ % ((noteDurations5_1[0][noteIndex] * (melodySlowfactor[0] -
// 4)) / 2) == 0)
// 	{
// 		noteIndex++;
// 		//		if(noteIndex%8==2)
// 		//			buzzer_flag=1;
// 	}
// }
// /*
// 音效：dd dddd dd dddd？
// */
// char music6_play_flag = 0;
// void music6_ticks()
// {
// 	static uint32_t cnt_ = 0;
// 	static int noteIndex = 0;
// 	if (!music6_play_flag)
// 		return;
// 	if (noteIndex >= melodySizes6[0])
// 	{
// 		music6_play_flag = 0;
// 		noteIndex = 0;
// 		cnt_ = 0;
// 		return;
// 	}
// 	buzzerSetNewFrequency(melody6[0][noteIndex]);
// 	if (cnt_++ % ((noteDurations6[0][noteIndex] * (melodySlowfactor[0] - 7))
// / 2) == 0)
// 	{
// 		noteIndex++;
// 		//		if(noteIndex%8==2)
// 		//			buzzer_flag=1;
// 	}
// }

void music_ticks(void)
{
    if (music_state.music_play & MUS_STOP) {
        music_state.music_play = 0;
    } else if (music_state.music_play & MUS_cus) {
        static int cnt_ = 0;
        if (music_state.note_curr >= music_state.note_sum) {
            music_state.music_play &= ~MUS_cus;
            music_state.note_curr = 0;
            cnt_                  = 0;
            // return;
        } else {
            buzzerSetNewFrequency(music_state.notes[music_state.note_curr]);
            // PRINT("note: %d, %d,%d\n", music_state.note_curr,
            // music_state.notes[music_state.note_curr],
            // music_state.durat[music_state.note_curr]);
            if (cnt_++ >= ((music_state.durat[music_state.note_curr] * (15 - 4)) / 2)) {
                cnt_ = 0;
                music_state.note_curr++;
            }
        }
    }
    // 	music5_ticks();
    // 	music5_1_ticks();
    // 	music6_ticks();
}
void buzzerStop(void)
{
    music_state.music_play = 0;
    buzzerSetNewFrequency(0);
}