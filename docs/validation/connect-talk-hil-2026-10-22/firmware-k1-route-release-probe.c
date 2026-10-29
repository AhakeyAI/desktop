/* Diagnostic extraction only; NOT firmware source or a formal Harness gate.
 * Two exact functions from ed426c9 APP/hardware/psk_multi_button.c.
 * Availability and HID transport are stubbed. Exit 1 is the expected current
 * failure if the route becomes unavailable between DOWN and UP; this does not
 * establish that the field Siri event entered that state.
 * Run: clang -std=c11 -Wall -Wextra -Werror firmware-k1-route-release-probe.c -o /tmp/k1-release-probe
 *      /tmp/k1-release-probe
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define K1_ROUTE_ACTION_MAX 100u
#define K1_ROUTE_CONSUMER 1u
#define K1_ROUTE_ORDINARY 0u
typedef enum { PRESS_DOWN, PRESS_UP } PressEvent;
typedef struct {uint8_t kind,length;uint8_t data[100];} k1_route_t;
static struct {uint8_t mode_data;} running_data;
static int available=1, host_down=0, sends=0;
static uint8_t k1_restore_store_read(uint8_t mode,k1_route_t*out){(void)mode;if(!available)return 0;memset(out,0,sizeof(*out));out->kind=1;out->length=2;out->data[0]=0xCF;return 1;}
static void keyboard_press_consumer_usage_1(uint16_t usage,int8_t press){(void)usage;host_down=press!=0;sends++;}
static void prase_user_key(uint8_t*a,uint8_t len,uint8_t press){(void)a;(void)len;(void)press;}
static struct {
    uint8_t active;
    uint8_t kind;
    uint8_t mode;
    uint8_t length;
    uint16_t usage;
    uint8_t action[K1_ROUTE_ACTION_MAX];
} s_k1_capture;
static void input_control_k1_finish(uint8_t transmit_release)
{
    if (!s_k1_capture.active) return;
    if (transmit_release) {
        if (s_k1_capture.kind == K1_ROUTE_CONSUMER)
            keyboard_press_consumer_usage_1(s_k1_capture.usage, 0);
        else if (s_k1_capture.length)
            prase_user_key(s_k1_capture.action, s_k1_capture.length, 0);
    }
    memset(&s_k1_capture, 0, sizeof(s_k1_capture));
}
static void input_control_k1_route_event(PressEvent event)
{
    k1_route_t route;
    if (!k1_restore_store_read(running_data.mode_data, &route)) {
        if (event == PRESS_UP) input_control_k1_finish(0);
        return;
    }
    if (event == PRESS_DOWN) {
        if (s_k1_capture.active) return;
        input_control_k1_finish(0);
        s_k1_capture.active = 1;
        s_k1_capture.kind = route.kind;
        s_k1_capture.mode = running_data.mode_data;
        s_k1_capture.length = route.length;
        if (route.kind == K1_ROUTE_CONSUMER) {
            s_k1_capture.usage = (uint16_t)route.data[0] | ((uint16_t)route.data[1] << 8);
            keyboard_press_consumer_usage_1(s_k1_capture.usage, 1);
        } else {
            memcpy(s_k1_capture.action, route.data, route.length);
            if (route.length) prase_user_key(s_k1_capture.action, route.length, 1);
        }
    } else if (event == PRESS_UP) {
        input_control_k1_finish(1);
    }
}
int main(void){
 input_control_k1_route_event(PRESS_DOWN);input_control_k1_route_event(PRESS_UP);
 if(host_down||sends!=2){puts("INVALID: normal control failed");return 2;}
 puts("PASS control: available route pairs Consumer down/up");
 available=1;sends=0;input_control_k1_route_event(PRESS_DOWN);
 available=0;input_control_k1_route_event(PRESS_UP);
 printf("PROBE: host_down=%d sends=%d capture_active=%u\n",host_down,sends,s_k1_capture.active);
 if(host_down){puts("FAIL release invariant: route unavailable on UP leaves Consumer down while forgetting captured action");return 1;}
 puts("PASS release invariant");return 0;
}
