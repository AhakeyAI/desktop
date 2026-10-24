#include "ips096_st7735.h"
#include "font.h"
// #include "img.h"

uint16_t BACK_COLOR = CYAN;

void IPS_Delay(uint16_t delay)
{
    static uint16_t i;
    for (i = 0; i < delay; i++) {
        //__NOP();
    }
}
void IPS_Write_Bus(uint8_t data)
{
    CS_RESET;
    // HAL_SPI_Transmit(&ST7735_SPI, &data, 1, 0xff);

    // while (!LL_SPI_IsActiveFlag_TXE(SPI1)) // 等待数据发送完成
    // {
    // }
    // LL_SPI_TransmitData8(SPI1, data);	   // 发送8位数据
    // while (!LL_SPI_IsActiveFlag_TXE(SPI1)) // 等待数据发送完成
    // {
    // }
    // IPS_Delay(7);
    SPI0_MasterSendByte(data);
    // IPS_Delay(7);
    CS_SET;
}

void IPS_Write_Datauint8_t(uint8_t data)
{
    // RS_SET;
    IPS_Write_Bus(data);
}

void IPS_Write_Datauint16_t(uint16_t data)
{
    // RS_SET;
    // IPS_Write_Bus(data >> 8);
    // IPS_Write_Bus(data);
    // CS_RESET;
    // HAL_SPI_Transmit(&ST7735_SPI, &data, 1, 0xff);

    // DelayMs(1);
    SPI0_MasterSendByte(data >> 8);     // 发送8位数据
    SPI0_MasterSendByte(data & 0x00ff); // 发送8位数据
    // IPS_Delay(7);
    // CS_SET;
}

void IPS_Write_Reg(uint8_t data)
{
    RS_RESET;
    IPS_Write_Bus(data);
    RS_SET;
}

void IPS_Addr_Set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2)
{
    IPS_Write_Reg(0x2a); // 列地址设置
    IPS_Write_Datauint16_t(x1 + 1);
    IPS_Write_Datauint16_t(x2 + 1);
    IPS_Write_Reg(0x2b); // 行地址设置
    IPS_Write_Datauint16_t(y1 + 26);
    IPS_Write_Datauint16_t(y2 + 26);
    IPS_Write_Reg(0x2c); // 储存器写
}

void IPS_Init(void)
{
    // GPIOB_ModeCfg(GPIO_Pin_22, GPIO_ModeOut_PP_5mA);

    // GPIOPinRemap(ENABLE, RB_PIN_SPI0);
    // GPIOB_SetBits(GPIO_Pin_12);
    // GPIOB_ModeCfg(GPIO_Pin_12 | GPIO_Pin_13 | GPIO_Pin_14,
    // GPIO_ModeOut_PP_5mA); SPI0_MasterDefInit();

    // 单字节发送
    // GPIOA_ResetBits(GPIO_Pin_12);
    // SPI0_MasterSendByte(0x55);
    // GPIOA_SetBits(GPIO_Pin_12);
    // DelayMs(1);
    IPS_Write_Reg(0x11);

    IPS_Write_Reg(0x21);

    IPS_Write_Reg(0xB1);
    IPS_Write_Datauint8_t(0x05);
    IPS_Write_Datauint8_t(0x3A);
    IPS_Write_Datauint8_t(0x3A);

    IPS_Write_Reg(0xB2);
    IPS_Write_Datauint8_t(0x05);
    IPS_Write_Datauint8_t(0x3A);
    IPS_Write_Datauint8_t(0x3A);

    IPS_Write_Reg(0xB3);
    IPS_Write_Datauint8_t(0x05);
    IPS_Write_Datauint8_t(0x3A);
    IPS_Write_Datauint8_t(0x3A);
    IPS_Write_Datauint8_t(0x05);
    IPS_Write_Datauint8_t(0x3A);
    IPS_Write_Datauint8_t(0x3A);

    IPS_Write_Reg(0xB4);
    IPS_Write_Datauint8_t(0x03);

    IPS_Write_Reg(0xC0);
    IPS_Write_Datauint8_t(0x62);
    IPS_Write_Datauint8_t(0x02);
    IPS_Write_Datauint8_t(0x04);

    IPS_Write_Reg(0xC1);
    IPS_Write_Datauint8_t(0xC0);

    IPS_Write_Reg(0xC2);
    IPS_Write_Datauint8_t(0x0D);
    IPS_Write_Datauint8_t(0x00);

    IPS_Write_Reg(0xC3);
    IPS_Write_Datauint8_t(0x8D);
    IPS_Write_Datauint8_t(0x6A);

    IPS_Write_Reg(0xC4);
    IPS_Write_Datauint8_t(0x8D);
    IPS_Write_Datauint8_t(0xEE);

    IPS_Write_Reg(0xC5); /*VCOM*/
    IPS_Write_Datauint8_t(0x0E);

    IPS_Write_Reg(0xE0);
    IPS_Write_Datauint8_t(0x10);
    IPS_Write_Datauint8_t(0x0E);
    IPS_Write_Datauint8_t(0x02);
    IPS_Write_Datauint8_t(0x03);
    IPS_Write_Datauint8_t(0x0E);
    IPS_Write_Datauint8_t(0x07);
    IPS_Write_Datauint8_t(0x02);
    IPS_Write_Datauint8_t(0x07);
    IPS_Write_Datauint8_t(0x0A);
    IPS_Write_Datauint8_t(0x12);
    IPS_Write_Datauint8_t(0x27);
    IPS_Write_Datauint8_t(0x37);
    IPS_Write_Datauint8_t(0x00);
    IPS_Write_Datauint8_t(0x0D);
    IPS_Write_Datauint8_t(0x0E);
    IPS_Write_Datauint8_t(0x10);

    IPS_Write_Reg(0xE1);
    IPS_Write_Datauint8_t(0x10);
    IPS_Write_Datauint8_t(0x0E);
    IPS_Write_Datauint8_t(0x03);
    IPS_Write_Datauint8_t(0x03);
    IPS_Write_Datauint8_t(0x0F);
    IPS_Write_Datauint8_t(0x06);
    IPS_Write_Datauint8_t(0x02);
    IPS_Write_Datauint8_t(0x08);
    IPS_Write_Datauint8_t(0x0A);
    IPS_Write_Datauint8_t(0x13);
    IPS_Write_Datauint8_t(0x26);
    IPS_Write_Datauint8_t(0x36);
    IPS_Write_Datauint8_t(0x00);
    IPS_Write_Datauint8_t(0x0D);
    IPS_Write_Datauint8_t(0x0E);
    IPS_Write_Datauint8_t(0x10);

    IPS_Write_Reg(0x3A);
    IPS_Write_Datauint8_t(0x05);

    IPS_Write_Reg(0x36);

#if (USE_HORIZONTAL == 0)
    IPS_Write_Datauint8_t(0x08);
#endif
#if (USE_HORIZONTAL == 1)
    IPS_Write_Datauint8_t(0xC8);
#endif
#if (USE_HORIZONTAL == 2)
    IPS_Write_Datauint8_t(0x78);
#endif
#if (USE_HORIZONTAL == 3)
    IPS_Write_Datauint8_t(0xA8);
#endif
    IPS_Write_Reg(0x29);
}

void IPS_Clear(uint16_t color)
{
    uint16_t i, j;
    IPS_Addr_Set(0, 0, IPS_W - 1, IPS_H - 1);
    // for (i = 0; i < IPS_W; i++) {
    //     for (j = 0; j < IPS_H; j++) {
    //         IPS_Write_Datauint16_t(color);
    //     }
    // }
    // SPI0_MasterSendByte()
    uint16_t remain = 160 * 80 * 2;
    uint8_t  index  = 1;
    while (remain > 0) {
#define CHUNK_SIZE 4000
        uint16_t this_len = remain > CHUNK_SIZE ? CHUNK_SIZE : remain;
        uint16_t sendlen  = this_len;
        uint8_t *d_p      = (uint8_t *) &color;
        R8_SPI0_CTRL_MOD &= ~RB_SPI_FIFO_DIR; // 设置数据方向为输出
        R16_SPI0_TOTAL_CNT = sendlen;         // 设置要发送的数据长度
        R8_SPI0_INT_FLAG   = RB_SPI_IF_CNT_END;

        while (sendlen) {
            if (R8_SPI0_FIFO_COUNT < SPI_FIFO_SIZE) {
                R8_SPI0_FIFO = d_p[index];
                index        = !index;
                sendlen--;
            }
        }
        while (R8_SPI0_FIFO_COUNT != 0)
            ; // 等待FIFO中的数据全部发送完成
        remain -= this_len;
    }

    BACK_COLOR = color;
}

void IPS_Draw_Point(uint16_t x, uint16_t y, uint16_t color)
{
    IPS_Addr_Set(x, y, x, y);
    IPS_Write_Datauint16_t(color);
}

void IPS_DrawPoint_big(uint16_t x, uint16_t y, uint16_t color)
{
    IPS_Fill(x - 1, y - 1, x + 1, y + 1, color);
}

void IPS_Fill(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint16_t color)
{
    uint16_t i, j;
    IPS_Addr_Set(xsta, ysta, xend, yend);
    for (i = ysta; i <= yend; i++) {
        for (j = xsta; j <= xend; j++) {
            IPS_Write_Datauint16_t(color);
        }
    }
}

void IPS_DrawLine(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, uint16_t color)
{
    uint16_t t;
    int      xerr = 0, yerr = 0, delta_x, delta_y, distance;
    int      incx, incy, uRow, uCol;
    delta_x = x2 - x1; // 计算坐标增量
    delta_y = y2 - y1;
    uRow    = x1; // 画线起点坐标
    uCol    = y1;
    if (delta_x > 0)
        incx = 1; // 设置单步方向
    else if (delta_x == 0)
        incx = 0; // 垂直线
    else {
        incx    = -1;
        delta_x = -delta_x;
    }
    if (delta_y > 0)
        incy = 1;
    else if (delta_y == 0)
        incy = 0; // 水平线
    else {
        incy    = -1;
        delta_y = -delta_x;
    }
    if (delta_x > delta_y)
        distance = delta_x; // 选取基本增量坐标轴
    else
        distance = delta_y;
    for (t = 0; t < distance + 1; t++) {
        IPS_Draw_Point(uRow, uCol, color); // 画点
        xerr += delta_x;
        yerr += delta_y;
        if (xerr > distance) {
            xerr -= distance;
            uRow += incx;
        }
        if (yerr > distance) {
            yerr -= distance;
            uCol += incy;
        }
    }
}

void IPS_ShowChar(uint16_t x, uint16_t y, uint8_t num, uint8_t mode, uint16_t color)
{
    uint8_t  temp;
    uint8_t  pos, t;
    uint16_t x0 = x;
    if (x > IPS_W - 8 || y > IPS_H - 16)
        return;                                // 设置窗口
    num = num - ' ';                           // 得到偏移后的值
    IPS_Addr_Set(x, y, x + 8 - 1, y + 16 - 1); // 设置光标位置
    if (!mode)                                 // 非叠加方式
    {
        if (BACK_COLOR == color)
            BACK_COLOR = !color;
        for (pos = 0; pos < 16; pos++) {
            temp = asc2_1608[(uint16_t) num * 16 + pos]; // 调用1608字体
            for (t = 0; t < 8; t++) {
                if (temp & 0x01)
                    IPS_Write_Datauint16_t(color);
                else
                    IPS_Write_Datauint16_t(BACK_COLOR);
                temp >>= 1;
                x++;
            }
            x = x0;
            y++;
        }
    } else // 叠加方式
    {
        for (pos = 0; pos < 16; pos++) {
            temp = asc2_1608[(uint16_t) num * 16 + pos]; // 调用1608字体
            for (t = 0; t < 8; t++) {
                if (temp & 0x01)
                    IPS_Draw_Point(x + t, y + pos, color); // 画一个点
                temp >>= 1;
            }
        }
    }
}

void IPS_ShowString(uint16_t x, uint16_t y, const uint8_t *p, uint16_t color)
{
    while (*p != '\0') {
        if (x > IPS_W - 16) {
            x = 0;
            y += 16;
        }
        // if (y > IPS_H - 16) {
        //     y = x = 0;
        //     IPS_Clear(RED);
        // }
        IPS_ShowChar(x, y, *p, 0, color);
        x += 8;
        p++;
    }
}
void IPS_ShowString_len(uint16_t x, uint16_t y, const uint8_t *p, uint16_t color, uint16_t len)
{
    while (*p != '\0' && len > 0) {
        len--;
        // if (x > IPS_W - 16)
        // {
        // 	x = 0;
        // 	y += 16;
        // }
        if (y > IPS_H - 16) {
            y = x = 0;
            IPS_Clear(RED);
        }
        IPS_ShowChar(x, y, *p, 0, color);
        x += 8;
        p++;
    }
}

// void IPS_ShowPicture(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2)
//{
//	int i;
//	IPS_Addr_Set(x1, y1, x2, y2);
//	for (i = 0; i < 7140; i++)
//	{
//		IPS_Write_Datauint8_t(gImage_img[i * 2 + 1]);
//		IPS_Write_Datauint8_t(gImage_img[i * 2]);
//	}
// }

void IPS_show_single_color_pic(
    uint8_t *d, uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t forecolor, uint16_t backcolor)
{
    IPS_Addr_Set(x, y, x + w-1, y + h-1);
    int st = 0;
    for (int i = y; i < y + h; i++) {
        for (int j = 0; j < w; j++) {
            uint8_t mask = 0x80 >> (j % 8);
            if (d[st + j / 8] & mask) {
                IPS_Write_Datauint16_t(forecolor);
            } else
                IPS_Write_Datauint16_t(backcolor);
        }
        st += (w - 1) / 8 + 1;
    }
}