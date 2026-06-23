#ifndef __ST7735_H_
#define __ST7735_H_

#include "CONFIG.h"
// #include "spi.h"

// #define HAL_SPI_Transmit(a, b, c, d) LL_MY_TRANSMIT(b, c)
// #define ST7735_SPI hspi1

// #define CS_L LL_GPIO_ResetOutputPin(TFT_CS_GPIO_Port, TFT_CS_Pin);
// #define CS_H LL_GPIO_SetOutputPin(TFT_CS_GPIO_Port, TFT_CS_Pin);

// #define RS_L LL_GPIO_ResetOutputPin(TFT_RS_GPIO_Port, TFT_RS_Pin);
// #define RS_H LL_GPIO_SetOutputPin(TFT_RS_GPIO_Port, TFT_RS_Pin);

// #define RST_L LL_GPIO_ResetOutputPin(TFT_RST_GPIO_Port, TFT_RST_Pin);
// #define RST_H LL_GPIO_SetOutputPin(TFT_RST_GPIO_Port, TFT_RST_Pin);

// #define CS_RESET LL_GPIO_ResetOutputPin(GPIOB, LL_GPIO_PIN_2)
// #define CS_SET LL_GPIO_SetOutputPin(GPIOB, LL_GPIO_PIN_2)
#define CS_RESET
#define CS_SET

#define LCD_CS_RESET   GPIOB_ResetBits(GPIO_Pin_17)
#define LCD_CS_SET     GPIOB_SetBits(GPIO_Pin_17)

#define RS_RESET       GPIOB_ResetBits(GPIO_Pin_16)
#define RS_SET         GPIOB_SetBits(GPIO_Pin_16)

#define RST_RESET      GPIOB_ResetBits(GPIO_Pin_9)
#define RST_SET        GPIOB_SetBits(GPIO_Pin_9)

#define USE_HORIZONTAL 3 // ���ú�������������ʾ 0��1Ϊ���� 2��3Ϊ����

#if USE_HORIZONTAL == 0 || USE_HORIZONTAL == 1
#define IPS_W 80
#define IPS_H 160

#else
#define IPS_W 160
#define IPS_H 80
#endif

extern uint16_t BACK_COLOR;
// ������ɫ
#define WHITE      0xFFFF
#define BLACK      0x0000
#define BLUE       0x001F
#define BRED       0XF81F
#define GRED       0XFFE0
#define GBLUE      0X07FF
#define RED        0xF800
#define MAGENTA    0xF81F
#define GREEN      0x07E0
#define CYAN       0x7FFF
#define YELLOW     0xFFE0
#define BROWN      0XBC40 // ��ɫ
#define BRRED      0XFC07 // �غ�ɫ
#define GRAY       0X8430 // ��ɫ
// GUI��ɫ

#define DARKBLUE   0X01CF // ����ɫ
#define LIGHTBLUE  0X7D7C // ǳ��ɫ
#define GRAYBLUE   0X5458 // ����ɫ
// ������ɫΪPANEL����ɫ

#define LIGHTGREEN 0X841F // ǳ��ɫ
#define LGRAY      0XC618 // ǳ��ɫ(PANNEL),���屳��ɫ

#define LGRAYBLUE  0XA651 // ǳ����ɫ(�м����ɫ)
#define LBBLUE     0X2B12 // ǳ����ɫ(ѡ����Ŀ�ķ�ɫ)

void IPS_Init(void);
void IPS_Clear(uint16_t color);
void IPS_DrawPoint_big(uint16_t x, uint16_t y, uint16_t color);
void IPS_Fill(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint16_t color);
void IPS_DrawLine(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color);
void IPS_ShowChar(uint16_t x, uint16_t y, uint8_t num, uint8_t mode, uint16_t color);
void IPS_ShowString(uint16_t x, uint16_t y, const uint8_t *p, uint16_t color);
void IPS_ShowString_len(uint16_t x, uint16_t y, const uint8_t *p, uint16_t color, uint16_t len);
// void IPS_ShowPicture(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2);
void IPS_Addr_Set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2);
void IPS_Write_Datauint8_t(uint8_t data);
void IPS_show_single_color_pic(
    uint8_t *d, uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t forecolor, uint16_t backcolor);

#endif
