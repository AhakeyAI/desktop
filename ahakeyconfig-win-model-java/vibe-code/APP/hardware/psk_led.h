#ifndef _PSK_LED
#define _PSK_LED
#include "main.h"

#define PWMCycleCfg 6000

enum led_smooth {
    STEEP,        // 突变
    SMOOTH_ALL,   // 逐渐降低/升高亮度
    SMOOTH_DIM,   // 逐渐降低亮度(升高会突变)
    SMOOTH_LIGHT, // 逐渐升高亮度(降低会突变)
};
#define LED_TOTAL 1

// static GPIO_TypeDef *LED_IO[LED_TOTAL] = {LED_B_GPIO_Port, LED_R_GPIO_Port,
// LED_G_GPIO_Port, LED_BK_GPIO_Port}; static uint32_t LED_PIN[LED_TOTAL] =
// {LED_B_Pin, LED_R_Pin, LED_G_Pin, LED_BK_Pin};

void led_set_rgb(uint8_t r, uint8_t g, uint8_t b);
void led_set_mode(uint8_t led_n, enum led_smooth mode, uint8_t start_light);
void led_set_light(uint8_t led_n, uint8_t light);
void led_set_bk(uint8_t l);
/**
 * @brief : 每隔一段时间执行一次, 根据模式实现led亮度渐变
 */
void led_smooth_change_handle(void);
/**
 * @brief : 放在一个定时器里, 调用100次完成一个pwm周期
 */
void led_soft_pwm_handle(void);

#endif
