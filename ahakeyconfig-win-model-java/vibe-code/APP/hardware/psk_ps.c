#include "psk_ps.h"
#include "main.h"
#include "stdarg.h"
// uint8_t usart_recv_it_buff;

// lwrb_t usart_lwrb;

// uint8_t USART_RINGBUFF[USART_RINGBUFF_SIZE];
uint8_t USART_TX_BUF_PS[200] = {0x07, 0};

void ps_putc(char *ch, unsigned short len)
{
    PRINT(ch);
}

// uint8_t ps_getc(char *ch, unsigned short len)
// {
// 	return lwrb_read(&usart_lwrb, ch, len);
// }

// void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
// {
// 	if (huart->Instance == USART1)
// 	{
// 		lwrb_write(&usart_lwrb, &usart_recv_it_buff, 1);
// 		HAL_UART_Receive_IT(huart, (uint8_t *)&usart_recv_it_buff, 1);
// 	}
// }

// void ps_init(void)
// {
// 	lwrb_init(&usart_lwrb, (uint8_t *)USART_RINGBUFF, USART_RINGBUFF_SIZE);
// }
#define ZEROPAD     1  // Pad with zero
#define SIGN        2  // Unsigned/signed long
#define PLUS        4  // Show plus
#define SPACE       8  // Space if plus
#define LEFT        16 // Left justified
#define SPECIAL     32 // 0x
#define LARGE       64 // Use 'ABCDEF' instead of 'abcdef'
#define is_digit(c) ((c) >= '0' && (c) <= '9')
static int skip_atoi(const char **s)
{
    int i = 0;

    while (is_digit(**s))
        i = i * 10 + *((*s)++) - '0';

    return i;
}
uint8_t inf[20] = {0xAA, 0x05, 0xAF, 0xF1, 0x08};

void log_vsprintf(const char *fmt, va_list args)
{
    uint8_t p_inf_i = 5;
    // int len;
    unsigned long num;
    // int base;
    char *s;
    int   flags;       // Flags to number()
    int   field_width; // Width of output field
    int   precision;   // Min. # of digits for integers; max number of chars for from
                       // string
    int qualifier;     // 'h', 'l', or 'L' for integer fields
    // char *tmpstr = NULL;
    // int tmpstr_size = 0;
    char tmpch;

    uint8_t frame_number = 0xf1;
    // uint16_t data_size = 0;
    // uint8_t sum = 0;

    for (; *fmt; fmt++) {
        if (*fmt != '%') {
            continue;
        }
        flags = 0;
    repeat:
        fmt++; // This also skips first '%'

        switch (*fmt) {
        case '-':
            // flags |= LEFT;
            goto repeat;

        case '+':
            // flags |= PLUS;
            goto repeat;

        case ' ':
            // flags |= SPACE;
            goto repeat;

        case '#':
            // flags |= SPECIAL;
            goto repeat;

        case '0':
            // flags |= ZEROPAD;
            goto repeat;
        }

        // Get field width
        field_width = -1;

        if (is_digit(*fmt))
            field_width = skip_atoi(&fmt);
        else if (*fmt == '*') {
            fmt++;
            field_width = va_arg(args, int);

            if (field_width < 0) {
                field_width = -field_width;
                flags |= LEFT;
            }
        }

        // Get the precision
        precision = -1;

        if (*fmt == '.') {
            ++fmt;

            if (is_digit(*fmt))
                precision = skip_atoi(&fmt);
            else if (*fmt == '*') {
                ++fmt;
                precision = va_arg(args, int);
            }

            if (precision < 0)
                precision = 0;
        }

        // Get the conversion qualifier
        qualifier = -1;

        if (*fmt == 'l' || *fmt == 'L') {
            qualifier = *fmt;
            fmt++;
        }

        // Default base
        // base = 10;

        switch (*fmt) {
        case 'c':
            tmpch          = (unsigned char) va_arg(args, int);
            inf[p_inf_i++] = tmpch;
            continue;

        case 's':
            s = va_arg(args, char *);

            if (!s)
                s = "<NULL>";

            continue;

        case 'p':
            (void *) (unsigned long) va_arg(args, void *);
            continue;

        case 'n':
            continue;

        case 'A':
            continue;

        // Integer number formats - set up the flags and "break"
        case 'o':
            break;

        case 'X':

        case 'x':
            break;

        case 'd':
        case 'i':
            flags |= SIGN;

        case 'u':
            break;

        case 'f':
            qualifier = *fmt;
            break;

        default:
            // if (*fmt != '%')
            // {
            // 	// tmpch = '%';
            // 	// putc(&tmpch, 1);
            // }

            // if (*fmt)
            // {
            // 	// tmpch = *fmt;
            // 	// putc(&tmpch, 1);
            // }
            // else
            // {
            // 	--fmt;
            // }

            continue;
        }
        if (qualifier == 'f') {
            frame_number = va_arg(args, unsigned long);
        } else if (qualifier == 'l') {
            num            = va_arg(args, unsigned long);
            inf[p_inf_i++] = (num >> 24) & 0x000000ff;
            inf[p_inf_i++] = (num >> 16) & 0x000000ff;
            inf[p_inf_i++] = (num >> 8) & 0x000000ff;
            inf[p_inf_i++] = (num >> 0) & 0x000000ff;
        }
        // else if (qualifier == 'h')
        // {
        // 	if (flags & SIGN)
        // 		num = va_arg(args, int);
        // 	else
        // 		num = va_arg(args, unsigned int);
        // }
        else if (flags & SIGN) {
            num            = va_arg(args, int);
            inf[p_inf_i++] = (num >> 8) & 0x000000ff;
            inf[p_inf_i++] = (num >> 0) & 0x000000ff;
        } else {
            num            = va_arg(args, unsigned int);
            inf[p_inf_i++] = (num >> 8) & 0x000000ff;
            inf[p_inf_i++] = (num >> 0) & 0x000000ff;
        }

        // number(putc, num, base, field_width, precision, flags);
    }
    inf[p_inf_i] = 0;
    for (int t = 0; t < p_inf_i; t++) {
        inf[p_inf_i] += inf[t];
    }
    p_inf_i++;
    inf[3] = frame_number;
    inf[4] = p_inf_i - 6;
    ps_putc((char *) inf, p_inf_i);
    // if (tmpstr_size)
    // {
    // 	putc(tmpstr, tmpstr_size);
    // 	tmpstr = NULL;
    // 	tmpstr_size = 0;
    // }
}

void ano_send_data(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    log_vsprintf(format, args);
    // va_og_vsprintf(format, args);
    va_end(args);
}
