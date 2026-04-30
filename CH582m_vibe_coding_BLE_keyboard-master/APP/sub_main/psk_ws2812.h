#ifndef __psk_ws2812_H
#define __psk_ws2812_H

#include "CONFIG.h"
#include "HAL.h"

// #define BIT_TRANSFER
// #define HAL_DMA_PWM_transfer
#define LL_DMA_PWM_transfer
#define LED_NUM 8

enum ws2812_mode_e {
    WS2812_OFF = 0x0, // all led black (off)
    WS2812_SINGLE_MOVE,
    WS2812_RAINBOW_MOVE,
    WS2812_RAINBOW_WAVE,
    WS2812_RAINBOW_WAVE_SLOW,
    WS2812_BREATHING,
    WS2812_MIDDLE_LIGHT,

};

#define ONE_PULSE   (49)  // 1 码计数个数 //90/59
#define ZERO_PULSE  (17)  // 0 码计数个数 //90/20
#define RESET_PULSE (250) // 80 复位电平个数（不能低于40）

// #define WS2812_ON  LL_GPIO_SetOutputPin(GPIOB, GPIO_Pin_4)
// #define WS2812_OFF LL_GPIO_ResetOutputPin(GPIOB, GPIO_Pin_4)
#define WS2812_POWER_ON
#define WS2812_POWER_OFF

typedef struct rgb_t_s
{
    uint8_t blue;
    uint8_t green;
    uint8_t red;
    uint8_t alpha;
} rgb_t;
typedef uint32_t size_tmp;
typedef union color_t_u {
    uint32_t hex;
    rgb_t    rgb;
} color_t;

typedef struct
{
    uint8_t  cur_bit;
    uint16_t cur_led;
    uint16_t reseting_time; // 0:not reset, min:80
    uint8_t  global_light;  // 0:no use,

    uint8_t ws2812_power_state;

    int zero_light_count;
} ws2812_state_t;
extern ws2812_state_t ws2812_state;
extern color_t        ws2812_list[LED_NUM];
extern uint16_t       get_current_bit(void);
extern void           calc_bit(uint16_t index);
extern void           tim5_ch3_ll_init(void);
void                  update_bit(uint16_t index);

extern void dma_tc_callback(void);
extern void tim5_ch3_ll_dma_init(void);
void        tim5_ch3_ll_dma_deinit(void);
void        change_2812_state(int x);
void        update_once(void);

void ws2812_display(enum ws2812_mode_e mode, uint32_t COLOR_HEX);
#endif
