#include "psk_ws2812.h"
#include "psk_ps.h"
#include "string.h"

__attribute__((aligned(4))) size_tmp ws2812_bittmp_all[24 * LED_NUM + RESET_PULSE] = {0};

// rgb
color_t ws2812_list[LED_NUM] = {
    0,
};
color_t        list_last[LED_NUM] = {0};
ws2812_state_t ws2812_state       = {0, 0, 0, 30};

// __HIGH_CODE
void update_bit(uint16_t index)
{
    static uint8_t last_global = 0;
    if (ws2812_list[index].hex == list_last[index].hex && last_global == ws2812_state.global_light) {
        return;
    } else {
        color_t   t = ws2812_list[index];
        uint16_t  tmp, tmpp_light;
        size_tmp *data_pos_ = ws2812_bittmp_all + 24 * index;

        list_last[index].hex = ws2812_list[index].hex;
        if (ws2812_state.cur_led == 0)
            last_global = ws2812_state.global_light;

        // PRINT("%d\n", index);

        // if (ws2812_state.global_light)
        // {
        //   tmpp_light = ws2812_state.global_light;
        // }
        // else
        if (t.rgb.alpha) {
            tmpp_light = (t.rgb.alpha * ws2812_state.global_light) >> 8;
        } else if (ws2812_state.global_light) {
            tmpp_light = ws2812_state.global_light;
        } else {
            goto no_set_light;
        }
        tmp = t.rgb.red;
        tmp = tmp * tmpp_light;
        tmp >>= 8;
        t.rgb.red = tmp;
        tmp       = t.rgb.blue;
        tmp       = tmp * tmpp_light;
        tmp >>= 8;
        t.rgb.blue = tmp;
        tmp        = t.rgb.green;
        tmp        = tmp * tmpp_light;
        tmp >>= 8;
        t.rgb.green = tmp;

    no_set_light:

        for (size_tmp *i = data_pos_ + 23; i >= data_pos_ + 16; i--) {
            *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
            t.hex >>= 1;
        }
        for (size_tmp *i = data_pos_ + 7; i >= data_pos_ + 0; i--) {
            *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
            t.hex >>= 1;
        }
        for (size_tmp *i = data_pos_ + 15; i >= data_pos_ + 8; i--) {
            *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
            t.hex >>= 1;
        }
    }
}
void force_update_bit(uint16_t index)
{
    color_t   t = ws2812_list[index];
    uint16_t  tmp, tmpp_light;
    size_tmp *data_pos_ = ws2812_bittmp_all + 24 * index;

    list_last[index].hex = ws2812_list[index].hex;

    if (ws2812_state.global_light) {
        tmpp_light = ws2812_state.global_light;
    } else if (t.rgb.alpha) {
        tmpp_light = t.rgb.alpha;
    } else {
        goto no_set_light;
    }
    tmp = t.rgb.red;
    tmp = tmp * tmpp_light;
    tmp >>= 8;
    t.rgb.red = tmp;
    tmp       = t.rgb.blue;
    tmp       = tmp * tmpp_light;
    tmp >>= 8;
    t.rgb.blue = tmp;
    tmp        = t.rgb.green;
    tmp        = tmp * tmpp_light;
    tmp >>= 8;
    t.rgb.green = tmp;

no_set_light:
    for (size_tmp *i = data_pos_ + 23; i >= data_pos_ + 16; i--) {
        *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
        t.hex >>= 1;
    }
    for (size_tmp *i = data_pos_ + 7; i >= data_pos_ + 0; i--) {
        *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
        t.hex >>= 1;
    }
    for (size_tmp *i = data_pos_ + 15; i >= data_pos_ + 8; i--) {
        *i = (t.hex) & (0x01) ? ONE_PULSE : ZERO_PULSE;
        t.hex >>= 1;
    }
}
#ifdef BIT_TRANSFER

void tim5_ch3_ll_init(void)
{
    LL_TIM_CC_EnableChannel(TIM5, LL_TIM_CHANNEL_CH3);
    LL_TIM_EnableIT_UPDATE(TIM5);
    LL_TIM_EnableCounter(TIM5);
}
uint16_t get_current_bit(void)
{
    uint16_t tmp = 0;
    if (ws2812_state.reseting_time) {
        tmp = 0;
        ws2812_state.reseting_time--;
    }
    // else if (ws2812_state.cur_bit > 23)
    // {
    //   tmp = 0;
    // }
    else {
        // if (ws2812_state.cur_bit == 0 && ws2812_state.cur_led == 0)
        if (ws2812_state.cur_bit == 0) {
            TIM5->CCR3 = 0x0;
            LL_TIM_DisableCounter(TIM5);
            calc_bit(ws2812_state.cur_led);
            LL_TIM_EnableCounter(TIM5);
        }
        tmp = ws2812_bittmp[ws2812_state.cur_bit];
        ws2812_state.cur_bit++;
        if (ws2812_state.cur_bit == 24) {
            ws2812_state.cur_bit = 0;
            // ws2812_state.reseting_time = 2;
            ws2812_state.cur_led++;

            if (ws2812_state.cur_led >= LED_NUM) {
                ws2812_state.cur_led       = 0;
                ws2812_state.reseting_time = RESET_PULSE;
            }
            // else
            // {
            //   calc_bit(ws2812_state.cur_led);
            // }
        }
    }
    return tmp;
}

#endif
#ifdef HAL_DMA_PWM_transfer

void tim5_ch3_hal_dma_init(void)
{
    HAL_TIM_PWM_Start_DMA(&htim5, TIM_CHANNEL_3, (uint32_t *) ws2812_bittmp, sizeof(ws2812_bittmp) / sizeof(size_tmp));
}

// PWM DMA ?????????????
void HAL_TIM_PWM_PulseFinishedCallback(TIM_HandleTypeDef *htim)
{
    if (htim == &htim5) {
        TIM5->CCR3 = 0x0;
        HAL_TIM_PWM_Stop_DMA(&htim5, TIM_CHANNEL_3);
        // LL_TIM_DisableCounter(TIM5);
        if (ws2812_state.reseting_time) {
            if (ws2812_state.reseting_time > 0) {
                ws2812_state.reseting_time--;
                memset(ws2812_bittmp, 0x0, sizeof(ws2812_bittmp));
            }
        } else {
            calc_bit(ws2812_state.cur_led);
            ws2812_state.cur_led++;
            if (ws2812_state.cur_led >= LED_NUM) {
                ws2812_state.cur_led       = 0;
                ws2812_state.reseting_time = RESET_PULSE / 24 + 1;
            }
        }
        // LL_TIM_EnableCounter(TIM5);
        HAL_TIM_PWM_Start_DMA(&htim5,
                              TIM_CHANNEL_3,
                              (uint32_t *) ws2812_bittmp,
                              sizeof(ws2812_bittmp) / sizeof(size_tmp));
    }
}

#endif
#ifdef LL_DMA_PWM_transfer
void tim5_ch3_ll_dma_init(void)
{
    for (int i = 0; i < LED_NUM; i++) {
        force_update_bit(i);
    }
    GPIOA_ModeCfg(GPIO_Pin_11, GPIO_ModeOut_PP_5mA);
    GPIOPinRemap(DISABLE, RB_PIN_TMR2);

    TMR2_PWMCycleCfg(75); // ?? 1.25us
                          // TMR2
                          // calc_bit(0);
    TMR2_PWMInit(High_Level, PWM_Times_1);

    TMR2_DMACfg(ENABLE,
                (uint16_t) (uint32_t) &ws2812_bittmp_all[0],
                (uint16_t) (uint32_t) &ws2812_bittmp_all[24 * LED_NUM + RESET_PULSE - 1],
                Mode_Single);
    TMR2_PWMEnable();
    TMR2_Enable();

    TMR2_ClearITFlag(TMR1_2_IT_DMA_END);
    // TMR2_ITCfg(ENABLE, TMR1_2_IT_DMA_END);
    // PFIC_EnableIRQ(TMR2_IRQn);

    // TMR2_ClearITFlag(TMR1_2_IT_DMA_END);

    // PFIC_EnableIRQ(TMR2_IRQn);

    // TMR2_ITCfg(ENABLE, TMR1_2_IT_DMA_END);

    // TMR3_TimerInit(360000 / 2);
    // TMR3_ITCfg(ENABLE, TMR0_3_IT_CYC_END);
    // PFIC_EnableIRQ(TMR3_IRQn);
}
void update_once(void)
{
    TMR2_ClearITFlag(TMR1_2_IT_DMA_END);
    TMR2_DMACfg(DISABLE,
                (uint16_t) (uint32_t) &ws2812_bittmp_all[0],
                (uint16_t) (uint32_t) &ws2812_bittmp_all[35],
                Mode_Single);

    TMR2_DMACfg(ENABLE,
                (uint16_t) (uint32_t) &ws2812_bittmp_all[0],
                (uint16_t) (uint32_t) &ws2812_bittmp_all[24 * LED_NUM + RESET_PULSE - 1],
                Mode_Single);
    TMR2_PWMEnable();
    TMR2_Enable();
}
__INTERRUPT
__HIGH_CODE
void TMR2_IRQHandler(void)
{
    if (TMR2_GetITFlag(TMR1_2_IT_DMA_END)) {
        TMR2_ClearITFlag(TMR1_2_IT_DMA_END);
    }
}
void tim5_ch3_ll_dma_deinit(void)
{
    TMR2_DMACfg(DISABLE,
                (uint16_t) (uint32_t) &ws2812_bittmp_all[0],
                (uint16_t) (uint32_t) &ws2812_bittmp_all[35],
                Mode_Single);
    WS2812_OFF;
}

void change_2812_state(int x)
{
    if (ws2812_state.ws2812_power_state != x) {
        if (x == 0 || x == 1) {
            if (ws2812_state.ws2812_power_state == 2) {
                WS2812_POWER_OFF;
                // PRINT("L_OFF\n");
                tim5_ch3_ll_dma_deinit();
                TMR2_PWMDisable();
                TMR2_Disable();
                TMR2_PWMActDataWidth(0);
            }
        }
        if (x == 2) {
            WS2812_POWER_ON;
            TMR2_PWMEnable();
            TMR2_Enable();
            // PRINT("L_ON\n");
            // tim5_ch3_ll_dma_init();
            TMR2_DMACfg(ENABLE,
                        (uint16_t) (uint32_t) &ws2812_bittmp_all[0],
                        (uint16_t) (uint32_t) &ws2812_bittmp_all[24 * LED_NUM + RESET_PULSE - 1],
                        Mode_LOOP);
        }
    }
    ws2812_state.ws2812_power_state = x;
    // PRINT("ws%d\n", ws2812_state.ws2812_power_state);
}

__attribute__((interrupt("WCH-Interrupt-fast"))) __attribute__((section(".highcode"))) void TMR3_IRQHandler(
    void) // TMR0 ????
{
    if (TMR3_GetITFlag(TMR0_3_IT_CYC_END)) {
        TMR3_ClearITFlag(TMR0_3_IT_CYC_END); // ??????
        update_bit(ws2812_state.cur_led);
        ws2812_state.cur_led++;
        if (ws2812_state.cur_led >= LED_NUM) {
            if (ws2812_state.zero_light_count >= LED_NUM) {
                change_2812_state(1);
            } else {
                change_2812_state(2);
            }
            ws2812_state.zero_light_count = 0;
            ws2812_state.cur_led          = 0;
        }
    }
}

#endif
void ws2812_display(enum ws2812_mode_e mode, uint32_t COLOR_HEX)
{
    static uint8_t led_position = 0;
    static int8_t  direction    = 1; // 1 = forward, -1 = backward

    switch (mode) {
    case WS2812_OFF:
        // Turn off all LEDs
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex = 0;
        }
        break;

    case WS2812_SINGLE_MOVE:
        // Clear all LEDs first
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex = 0;
        }

        // Set main LED at full brightness
        // #define COLOR_HEX 0xff3333
        ws2812_list[led_position].hex       = COLOR_HEX;
        ws2812_list[led_position].rgb.alpha = 255;

        // Set adjacent LEDs at 60% brightness
        if (led_position > 0) {
            ws2812_list[led_position - 1].hex       = COLOR_HEX;
            ws2812_list[led_position - 1].rgb.alpha = 100; // 60% of 255
        }
        if (led_position < LED_NUM - 1) {
            ws2812_list[led_position + 1].hex       = COLOR_HEX;
            ws2812_list[led_position + 1].rgb.alpha = 100; // 60% of 255
        }

        // Set LEDs 2 positions away at 30% brightness
        if (led_position > 1) {
            ws2812_list[led_position - 2].hex       = COLOR_HEX;
            ws2812_list[led_position - 2].rgb.alpha = 30; // 30% of 255
        }
        if (led_position < LED_NUM - 2) {
            ws2812_list[led_position + 2].hex       = COLOR_HEX;
            ws2812_list[led_position + 2].rgb.alpha = 30; // 30% of 255
        }

        // Update position for next iteration
        led_position += direction;

        // Bounce back when reaching the end
        if (led_position >= LED_NUM - 1) {
            led_position = LED_NUM - 1;
            direction    = -1;
        } else if (led_position <= 0) {
            led_position = 0;
            direction    = 1;
        }
        break;

    case WS2812_RAINBOW_WAVE:
    case WS2812_RAINBOW_WAVE_SLOW:
    case WS2812_RAINBOW_MOVE: {
        static uint8_t hue_offset = 0;

        // Create rainbow wave across all LEDs
        for (int i = 0; i < LED_NUM; i++) {
            // Calculate hue for this LED (0-255 range)
            // Spread rainbow across LEDs and add time-based offset for animation
            uint8_t hue = (i * 256 / LED_NUM + hue_offset) & 0xFF;

            // Simple HSV to RGB conversion (S=255, V=255)
            uint8_t region    = hue / 43; // 0-5
            uint8_t remainder = (hue - (region * 43)) * 6;

            uint8_t r = 0, g = 0, b = 0;

            switch (region) {
            case 0:
                r = 255;
                g = remainder;
                b = 0;
                break;
            case 1:
                r = 255 - remainder;
                g = 255;
                b = 0;
                break;
            case 2:
                r = 0;
                g = 255;
                b = remainder;
                break;
            case 3:
                r = 0;
                g = 255 - remainder;
                b = 255;
                break;
            case 4:
                r = remainder;
                g = 0;
                b = 255;
                break;
            default:
                r = 255;
                g = 0;
                b = 255 - remainder;
                break;
            }

            ws2812_list[i].rgb.red   = r;
            ws2812_list[i].rgb.green = g;
            ws2812_list[i].rgb.blue  = b;
            ws2812_list[i].rgb.alpha = 255; // Slightly dimmed for smoother look
        }

        // Advance the wave animation
        if (mode == WS2812_RAINBOW_WAVE_SLOW)
            hue_offset -= 2;
        else
            hue_offset -= 10;
        if (mode == WS2812_RAINBOW_MOVE) {
            for (int i = 0; i < LED_NUM; i++)
                ws2812_list[i].rgb.alpha = 1;
            ws2812_list[led_position].rgb.alpha = 255;

            if (led_position > 0) {
                ws2812_list[led_position - 1].rgb.alpha = 100; // 60% of 255
            }
            if (led_position < LED_NUM - 1) {
                ws2812_list[led_position + 1].rgb.alpha = 100; // 60% of 255
            }

            // Set LEDs 2 positions away at 30% brightness
            if (led_position > 1) {
                ws2812_list[led_position - 2].rgb.alpha = 30; // 30% of 255
            }
            if (led_position < LED_NUM - 2) {
                ws2812_list[led_position + 2].rgb.alpha = 30; // 30% of 255
            }

            // Update position for next iteration
            led_position += direction;

            // Bounce back when reaching the end
            if (led_position >= LED_NUM - 1) {
                led_position = LED_NUM - 1;
                direction    = -1;
            } else if (led_position <= 0) {
                led_position = 0;
                direction    = 1;
            }
        }
    } break;

    case WS2812_BREATHING: {
        static uint8_t brightness = 0;
        static int8_t  fade_dir   = 1; // 1 = fade in, -1 = fade out

                                       // Define breathing color (soft blue)
        // #define COLOR_HEX 0x3264ff

        // Set all LEDs to the same color with current brightness
        for (int i = 0; i < LED_NUM; i++) {
            ws2812_list[i].hex       = COLOR_HEX;
            ws2812_list[i].rgb.alpha = brightness;
        }

        // Update brightness for breathing effect
        brightness += fade_dir * 8;

        // Reverse direction at min/max brightness
        if (brightness >= 250) {
            brightness = 250;
            fade_dir   = -1;
        } else if (brightness <= 50) {
            brightness = 50;
            fade_dir   = 1;
        }
    } break;
    case WS2812_MIDDLE_LIGHT: {
        const uint8_t light[4] = {1, 30, 130, 255};
        for (int i = 0; i < LED_NUM / 2; i++) {
            ws2812_list[i].hex                     = COLOR_HEX;
            ws2812_list[i].rgb.alpha               = light[i];
            ws2812_list[LED_NUM - 1 - i].hex       = COLOR_HEX;
            ws2812_list[LED_NUM - 1 - i].rgb.alpha = light[i];
        }

    } break;

    default:
        break;
    }
}
