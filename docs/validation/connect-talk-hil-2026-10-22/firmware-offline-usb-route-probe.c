/* Diagnostic only: exact command_link_lost body from firmware fe2278616f69087b7f9097ae4777f7231ff39a30.
 * Expected exit 1 demonstrates an already-offline USB poll clearing a BLE route transaction.
 * Hardware/IRQ scheduling is stubbed; this is not a complete device trace or firmware fix.
 */
#include <stdint.h>
#include <stdio.h>
#define PRINT(...) ((void)0)
struct { uint8_t live; uint16_t handle; uint32_t generation; } s_links[2];
struct { uint8_t active; } s_k1_route_tx;
static int mTaskID;
#define MCT_COMMAND_TODO 1
static void SYS_DisableAllIrq(uint32_t *irq) { *irq=0; }
static void SYS_RecoverIrq(uint32_t irq) { (void)irq; }
static void tmos_set_event(int task, int event) { (void)task;(void)event; }
void input_control_k1_clear_for_disconnect(void) {}
void command_link_lost(uint8_t transport)
{
    uint32_t irq;
    uint8_t transitioned = 0;
    if (transport > 1) return;
    PRINT("[K1DIAG] command_link_lost transport=%u live=%u handle=%u generation=%lu\n",
          transport, s_links[transport].live, s_links[transport].handle,
          (unsigned long)s_links[transport].generation);
    s_k1_route_tx.active = 0;
    SYS_DisableAllIrq(&irq);
    if (s_links[transport].live) {
        s_links[transport].live = 0;
        transitioned = 1;
        tmos_set_event(mTaskID, MCT_COMMAND_TODO);
    }
    SYS_RecoverIrq(irq);
    if (transitioned) {
        extern void input_control_k1_clear_for_disconnect(void);
        input_control_k1_clear_for_disconnect();
    }
}

int main(void) {
 s_links[0].live=1; s_links[1].live=0; s_k1_route_tx.active=1;
 command_link_lost(1);
 if (!s_k1_route_tx.active) {
   fputs("FAIL: already-offline USB poll cleared active BLE route transaction\n",stderr);
   return 1;
 }
 puts("PASS: active BLE route transaction preserved");return 0;
}
