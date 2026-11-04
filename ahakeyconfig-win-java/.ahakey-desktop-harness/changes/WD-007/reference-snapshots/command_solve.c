#include "command_solve.h"
#include "lwrb.h"
#include "main.h"
#include "../sdk_bridge/ahakey_sdk_config.h"
#include "../sdk_bridge/ahakey_sdk_runtime.h"
#include "services/device_lifecycle.h"
#include "services/display_config_store.h"
#include "services/display_preview.h"
#include "services/resource_upload_transaction.h"
#include "services/resource_flash_writer.h"
#include "services/standby_config.h"
#include "services/k1_restore_store.h"
#include "services/restore_initialization.h"
#include "usb1_hid.h"
#include "w25qxx.h"
#include <stddef.h>
extern const uint8_t defult_key_f18[3];
#define COMMAND_TRANSPORT_BLE 0
#define COMMAND_TRANSPORT_USB 1

uint8_t *command_data;
uint16_t command_len;
uint8_t  command_in_process;
uint8_t  command_transport;
uint8_t  data_transport;
uint8_t  ble_data_rec_buf[400];
lwrb_t   ble_data_lwrb;

static const char kFirmwareCatalogKey[] = "x1-c582-hw1-p1-1.0.0-r001";
/* Accepted protocol paths retained by CP4B: 0x00, 0x92, 0x95, 0x9F. */
static resource_upload_transaction_s s_resource_upload;
static struct {
    uint8_t active, selector, last_len;
    uint16_t expected_len, received_len, last_offset;
    uint32_t token, expected_crc, last_activity;
    uint8_t bytes[4 * K1_ROUTE_SERIALIZED_SIZE];
    uint8_t last_data[47];
} s_k1_route_tx;
typedef struct {
    uint32_t generation;
    uint16_t handle;
    uint8_t transport;
} command_identity_s;
typedef struct {
    volatile uint32_t generation;
    volatile uint8_t live, malformed;
    uint16_t handle;
    uint8_t config;
    volatile uint16_t count, ready_len;
    command_identity_s partial_id, ready_id;
    uint8_t partial[256], ready[256];
} command_link_s;
static command_link_s s_links[2];

static command_identity_s s_execution, s_upload_owner, s_raw_owner;
static uint8_t s_executing, s_raw_owned, s_next_link;
static resource_flash_writer_s s_resource_writer;
static uint8_t s_resource_write_submitted;
typedef struct {
    command_identity_s owner;
    uint8_t opcode, code, state, reserved;
} command_ack_s;
static command_ack_s s_chunk_ack, s_raw_ack;
#define s_chunk_ack_pending s_chunk_ack.state
#define s_chunk_ack_owner s_chunk_ack.owner
#define s_chunk_ack_id s_chunk_ack.opcode
/* Separate REQUEST/RESULT phases reuse the unchanged two ready buffers. */
enum { O_EMPTY, O_REQUEST, O_EXECUTING, O_RESULT, O_CANCELLED, O_RAW_BEGIN };
static volatile uint8_t s_o_phase[2];
static uint8_t s_o_long[2];
static uint8_t s_side[8][12], s_side_count;
static uint8_t s_tx_class[2], s_tx_link, s_tx_overflow;
static uint8_t command_identity_equal(command_identity_s a, command_identity_s b);
static void command_raw_finish(resource_writer_result_e result);
static void command_raw_fill_payload(void);
static uint8_t s_resource_writer_busy;
static uint8_t command_execution_live(void);
static uint8_t command_upload_finish(void);
static uint8_t command_identity_live(command_identity_s id);

void SPI2_WriteByte(uint8_t d);
uint8_t SPI2_ReadByte(void);

static uint8_t command_flash_status(uint8_t *status)
{
    if (!status) return 0;
    W25QXX_CS_L;
    SPI2_WriteByte(W25X_ReadStatusReg1);
    *status = SPI2_ReadByte();
    W25QXX_CS_H;
    return 1;
}

static uint8_t command_flash_write_enable(void)
{
    W25QXX_CS_L;
    SPI2_WriteByte(W25X_WriteEnable);
    W25QXX_CS_H;
    return 1;
}

static void command_flash_address(uint32_t address)
{
    if (NOR_FLASH_GET_SIZEID(nor_flash_id) == NOR_SIZE_256M)
        SPI2_WriteByte((uint8_t)(address >> 24));
    SPI2_WriteByte((uint8_t)(address >> 16));
    SPI2_WriteByte((uint8_t)(address >> 8));
    SPI2_WriteByte((uint8_t)address);
}

static uint8_t command_flash_erase(uint32_t address)
{
    if (address & 4095u) return 0;
    W25QXX_CS_L;
    SPI2_WriteByte(W25X_SectorErase);
    command_flash_address(address);
    W25QXX_CS_H;
    return 1;
}

static uint8_t command_flash_program(uint32_t address, const uint8_t *data, uint8_t len)
{
    if (!data || !len || len > 48u || len > 256u - (address & 255u)) return 0;
    W25QXX_CS_L;
    SPI2_WriteByte(W25X_PageProgram);
    command_flash_address(address);
    SPI0_MasterTrans((uint8_t *)data, len);
    W25QXX_CS_H;
    return 1;
}

static uint8_t command_flash_read(uint32_t address, uint8_t *data, uint8_t len)
{
    if (!data || !len || len > 32u) return 0;
    W25QXX_CS_L;
    SPI2_WriteByte(W25X_ReadData);
    command_flash_address(address);
    for (uint8_t i = 0; i < len; ++i) data[i] = SPI2_ReadByte();
    W25QXX_CS_H;
    return 1;
}

static const resource_flash_io_s s_resource_flash_io = {
    command_flash_status, command_flash_write_enable, command_flash_erase,
    command_flash_program, command_flash_read
};

static uint32_t command_clock_ms(void)
{
    uint32_t ticks = TMOS_GetSystemClock();
    return (ticks / 8u) * 5u + ((ticks % 8u) * 5u) / 8u;
}

static uint16_t command_read_u16_le(const uint8_t *d)
{
    return (uint16_t) (d[0] | ((uint16_t) d[1] << 8));
}

static uint32_t command_read_u32_le(const uint8_t *d)
{
    return (uint32_t) d[0] |
           ((uint32_t) d[1] << 8) |
           ((uint32_t) d[2] << 16) |
           ((uint32_t) d[3] << 24);
}

static void command_write_u16_le(uint8_t *d, uint16_t value)
{
    d[0] = (uint8_t) value;
    d[1] = (uint8_t) (value >> 8);
}

static void command_write_u32_le(uint8_t *d, uint32_t value)
{
    d[0] = (uint8_t) value;
    d[1] = (uint8_t) (value >> 8);
    d[2] = (uint8_t) (value >> 16);
    d[3] = (uint8_t) (value >> 24);
}

static uint8_t command_resource_write(uint32_t address, const uint8_t *data, uint16_t len)
{
    display_resource_entry_s entry;
    if (len > UINT8_MAX || !display_resource_entry_get(s_resource_upload.entry_id, &entry))
        return 0;
    if (!resource_flash_writer_submit(&s_resource_writer, address, data, (uint8_t)len,
                                      entry.start_address,
                                      entry.start_address + entry.max_bytes,
                                      command_clock_ms()))
        return 0;
    s_resource_write_submitted = 1;
    s_resource_writer_busy = 1;
    return 1;
}

static uint8_t command_resource_metadata_update(uint8_t entry_id, const display_resource_metadata_s *metadata)
{
    return display_config_store_set_metadata(entry_id, metadata);
}

static void command_resource_upload_init_once(void)
{
    if (!s_resource_upload.write) {
        resource_flash_writer_init(&s_resource_writer);
        resource_upload_transaction_init(&s_resource_upload,
                                         command_resource_write,
                                         command_resource_metadata_update);
        s_resource_upload.live = command_execution_live;
        s_resource_upload.finish = command_upload_finish;
    }
}

uint8_t command_cp2_resource_upload_active(void)
{
    command_resource_upload_init_once();
    return resource_upload_transaction_active(&s_resource_upload) || s_resource_upload.pending_mask ||
           ((s_resource_writer.active || s_resource_writer.busy) && s_resource_writer.mode == RESOURCE_JOB_CP2) || s_resource_writer.fault;
}

uint8_t command_external_flash_busy(void)
{
    return resource_flash_writer_excluded(&s_resource_writer);
}

#if !defined(CP2_6_ROUTE_PROTOCOL_HOST_TESTS)
static void command_return_identity(command_identity_s id, uint8_t command_id, uint8_t code)
{
    if (s_chunk_ack.state && command_identity_equal(id, s_chunk_ack.owner)) {
        s_chunk_ack.opcode = command_id;
        s_chunk_ack.code = code;
        s_chunk_ack.state = command_identity_live(id) ? 2 : 0;
    }
}

void command_storage_tick(void)
{
    resource_writer_result_e result;
    uint32_t now;
    command_resource_upload_init_once();
    command_process_losses();
    if ((!s_resource_writer.active && !s_resource_writer.busy) || s_resource_writer.fault) return;
    now = command_clock_ms();
    command_raw_fill_payload();
    result = resource_flash_writer_step(&s_resource_writer, &s_resource_flash_io, now);
    if (s_resource_writer.mode != RESOURCE_JOB_CP2) {
        command_raw_finish(result);
        if (s_resource_writer.active || s_resource_writer.busy)
            tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
        return;
    }
    if (result == RESOURCE_WRITER_DONE) {
        s_resource_writer_busy = 0;
        if (s_chunk_ack_pending) {
            command_identity_s owner = s_chunk_ack_owner;
            uint8_t command_id = s_chunk_ack_id;
            command_return_identity(owner, command_id, 0);
        }
    } else if (result == RESOURCE_WRITER_ERROR) {
        s_resource_writer_busy = 0;
        if (s_resource_upload.active) resource_upload_abort_invalid(&s_resource_upload);
        if (s_chunk_ack_pending) {
            command_identity_s owner = s_chunk_ack_owner;
            uint8_t command_id = s_chunk_ack_id;
            command_return_identity(owner, command_id, 1);
        }
    }
    if (s_resource_writer.active || s_resource_writer.busy)
        tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
}

static uint8_t command_is_ai_presentation(uint8_t command_id)
{
    return command_id == 0x90 ||
           command_id == AHAKEY_CMD_TASK_LIGHT_MODE ||
           command_id == AHAKEY_CMD_TASK_SLOT_UPDATE ||
           command_id == AHAKEY_CMD_TASK_HEARTBEAT;
}

static void refresh_ai_presentation_idle_sleep(void)
{
    refresh_power_off_timeout();
    device_lifecycle_on_host_activity();
}

static uint8_t ordinary_key_action_payload_len(const uint8_t *action)
{
    if (action[0] == 0x00)
        return 0;
    if (action[0] != 0x73 && action[0] != 0x74)
        return 0xff;
    return min(action[1], USER_KEY_BIND_LEN - 2);
}

static uint8_t ordinary_key_desc_trimmed_len(const uint8_t *desc)
{
    uint8_t len = USER_KEY_DESC_LEN;
    while (len > 0 && (desc[len - 1] == 0x00 || desc[len - 1] == 0x20))
        len--;
    return len;
}

static uint8_t persist_standby_minutes(uint16_t minutes)
{
    uint16_t verify = 0xffff;
    key_bund.auto_power_off_minutes = minutes;
    running_data.have_update_custom_data = 1;
    standby_config_set_effective_minutes(minutes);
    device_lifecycle_set_standby_threshold_minutes(minutes);
    refresh_power_off_timeout();
    save_key_bound_data();
    EEPROM_READ(KEY_BUND_EEPROM_ADDR + offsetof(key_bund_s, auto_power_off_minutes), &verify, sizeof(verify));
    return verify == minutes;
}
#endif

#if AHAKEY_SDK_ENABLE
static ahakey_sdk_ai_state_t sdk_map_claude_state(uint8_t state)
{
    switch (state) {
    case CL_PermissionRequest:
    case CL_Notification:
        return AHAKEY_SDK_AI_WAITING_APPROVAL;
    case CL_SessionStart:
    case CL_UserPromptSubmit:
    case CL_PreToolUse:
    case CL_PostToolUse:
        return AHAKEY_SDK_AI_RUNNING;
    case CL_TaskCompleted:
        return AHAKEY_SDK_AI_DONE;
    case CL_Stop:
        return AHAKEY_SDK_AI_STOPPED;
    case CL_SessionEnd:
    default:
        return AHAKEY_SDK_AI_IDLE;
    }
}
#endif



static uint8_t command_identity_live(command_identity_s id)
{
    return id.transport < 2 && id.generation &&
           s_links[id.transport].live &&
           s_links[id.transport].generation == id.generation &&
           s_links[id.transport].handle == id.handle;
}
static uint8_t command_identity_equal(command_identity_s a, command_identity_s b)
{
    return a.transport == b.transport && a.generation == b.generation && a.handle == b.handle;
}
static command_identity_s command_identity(uint8_t transport)
{
    command_identity_s id = {s_links[transport].generation, s_links[transport].handle, transport};
    return id;
}
static uint8_t command_execution_live(void)
{
    uint32_t irq;
    uint8_t live;
    SYS_DisableAllIrq(&irq);
    live = s_executing && command_identity_live(s_execution);
    SYS_RecoverIrq(irq);
    return live;
}
static uint8_t command_upload_finish(void)
{
    uint32_t irq;
    uint8_t live;
    SYS_DisableAllIrq(&irq);
    live = s_executing && command_identity_live(s_execution) &&
           command_identity_equal(s_execution, s_upload_owner);
    if (live)
        s_resource_upload.active = 0; /* Atomic runtime publication, after verified persistence. */
    SYS_RecoverIrq(irq);
    if (live)
        task_resource_selection_dirty();
    return live;
}
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

static uint8_t command_k1_route_error(uint8_t version, uint8_t subcommand, uint32_t correlation)
{
    uint8_t ret[12] = {0xaa, 0xbb, 0x9e, 1, version, subcommand, 0, 0, 0, 0, 0xcc, 0xdd};
    command_write_u32_le(ret + 6, correlation);
    command_return_frame(ret, sizeof(ret));
    return 1;
}

static uint8_t command_k1_route_reply(uint8_t sub, const uint8_t *fields, uint8_t field_len)
{
    uint8_t ret[62];
    if ((uint16_t)field_len + 8 > sizeof(ret)) return 0;
    ret[0] = 0xaa; ret[1] = 0xbb; ret[2] = 0x9e; ret[3] = 0;
    ret[4] = 1; ret[5] = sub;
    if (field_len) memcpy(ret + 6, fields, field_len);
    ret[6 + field_len] = 0xcc; ret[7 + field_len] = 0xdd;
    command_return_frame(ret, field_len + 8);
    return 1;
}

static uint8_t command_k1_restore_reply(uint8_t result, uint8_t version, uint8_t sub, uint32_t nonce)
{
    uint8_t state = K1_RESTORE_STORAGE_UNAVAILABLE;
    uint32_t attempt = 0;
    uint8_t ret[17] = {0xaa, 0xbb, 0x9e, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xcc, 0xdd};
    ret[3] = result;
    ret[4] = version;
    ret[5] = sub;
    command_write_u32_le(ret + 6, nonce);
    if (!k1_restore_store_restore_status(&state, &attempt)) result = 1;
    ret[3] = result;
    ret[10] = state;
    command_write_u32_le(ret + 11, attempt);
    ret[15] = 0xcc;
    ret[16] = 0xdd;
    command_return_frame(ret, sizeof(ret));
    return result == 0;
}

static uint8_t command_k1_restore_handle(uint8_t *d, uint32_t len)
{
    uint8_t sub, result = 1;
    uint32_t nonce = 0;
    if (!d || len < 3) return command_k1_restore_reply(1, len > 1 ? d[1] : 0, len > 2 ? d[2] : 0, 0);
    sub = d[2];
    if (len == 7 || (d[1] == 2 && len == 11)) nonce = command_read_u32_le(d + 3);
    if (!((d[1] == 1 && len == 7) || (d[1] == 2 && sub == 0x31 && len == 11)))
        return command_k1_restore_reply(1, d[1], sub, nonce);
    if (sub == 0x30) {
        uint8_t state;
        result = k1_restore_store_restore_status(&state, 0) ? 0 : 1;
        return command_k1_restore_reply(result, d[1], sub, nonce);
    }
    if (sub != 0x31 || s_k1_route_tx.active || command_cp2_resource_upload_active() ||
        s_resource_writer.active || s_resource_writer.busy)
        return command_k1_restore_reply(1, d[1], sub, nonce);
    k1_route_t routes[K1_ROUTE_MODE_COUNT];
    memset(routes, 0, sizeof(routes));
    for (uint8_t mode = 0; mode < 3; ++mode) {
        routes[mode].kind = K1_ROUTE_ORDINARY;
        routes[mode].length = sizeof(defult_key_f18);
        memcpy(routes[mode].data, defult_key_f18, sizeof(defult_key_f18));
    }
    if (d[1] == 2)
        result = restore_initialization_start_v2(HAVE_VUSB, 1, routes,
                    restore_initialization_apply_defaults, command_read_u32_le(d + 7)) ? 0 : 1;
    else
        result = restore_initialization_start(HAVE_VUSB, 1, routes, restore_initialization_apply_defaults) ? 0 : 1;
    return command_k1_restore_reply(result, d[1], sub, nonce);
}

static uint8_t command_k1_route_handle(uint8_t *d, uint32_t len)
{
    uint8_t sub, fields[54], selector, mode, offset, count;
    uint32_t nonce, token;
    k1_route_t routes[K1_ROUTE_MODE_COUNT];
    if (!d || !len || d[0] != 0x9e) return 0;
    if (len < 3) return command_k1_route_error(len > 1 ? d[1] : 0, len > 2 ? d[2] : 0, 0);
    sub = d[2];
    if (sub == 0x30 || sub == 0x31)
        return command_k1_restore_handle(d, len);
    command_resource_upload_init_once();
    if (d[1] != 1) return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
    if (restore_initialization_is_quarantined())
        return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
    if (resource_upload_transaction_active(&s_resource_upload) || s_resource_upload.pending_mask || s_resource_writer.active || s_resource_writer.busy)
        return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
    if (sub == 0x00) {
        if (len != 7) return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
        nonce = command_read_u32_le(d + 3);
        command_write_u32_le(fields, nonce); fields[4] = 0x03; fields[5] = K1_ROUTE_MODE_COUNT;
        return command_k1_route_reply(sub, fields, 6);
    }
    if (sub == 0x10) {
        uint8_t serialized[K1_ROUTE_SERIALIZED_SIZE];
        if (len != 10) return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
        nonce = command_read_u32_le(d + 3); mode = d[7]; offset = d[8]; count = d[9];
        if (mode >= K1_ROUTE_MODE_COUNT || !count || count > 42 || offset >= K1_ROUTE_SERIALIZED_SIZE || count > K1_ROUTE_SERIALIZED_SIZE - offset ||
            !k1_restore_store_read(mode, &routes[0])) return command_k1_route_error(d[1], sub, nonce);
        memset(serialized, 0, sizeof(serialized)); serialized[0] = routes[0].kind; serialized[1] = routes[0].length;
        if (routes[0].length) memcpy(serialized + 2, routes[0].data, routes[0].length);
        command_write_u32_le(fields, nonce); fields[4] = mode; fields[5] = offset;
        fields[6] = K1_ROUTE_SERIALIZED_SIZE; fields[7] = 0;
        command_write_u32_le(fields + 8, k1_restore_store_crc32(serialized, sizeof(serialized)));
        memcpy(fields + 12, serialized + offset, count);
        return command_k1_route_reply(sub, fields, 12 + count);
    }
    if (sub == 0x20) {
        uint16_t payload_len;
        if (len != 14) return command_k1_route_error(d[1], sub, len >= 14 ? command_read_u32_le(d + 10) : 0);
        selector = d[3]; payload_len = command_read_u16_le(d + 4); nonce = command_read_u32_le(d + 10);
        if ((selector >= K1_ROUTE_MODE_COUNT && selector != 0xff) || payload_len != (selector == 0xff ? 408 : 102) || !nonce)
            return command_k1_route_error(d[1], sub, nonce);
        if (s_k1_route_tx.active) {
            if (s_k1_route_tx.token == nonce && s_k1_route_tx.selector == selector && s_k1_route_tx.expected_len == payload_len &&
                s_k1_route_tx.expected_crc == command_read_u32_le(d + 6)) {
                command_write_u32_le(fields, nonce); command_write_u32_le(fields + 4, nonce);
                command_write_u16_le(fields + 8, s_k1_route_tx.received_len);
                return command_k1_route_reply(sub, fields, 10);
            }
            return command_k1_route_error(d[1], sub, nonce);
        }
        memset(&s_k1_route_tx, 0, sizeof(s_k1_route_tx));
        s_k1_route_tx.active = 1; s_k1_route_tx.selector = selector; s_k1_route_tx.expected_len = payload_len;
        s_k1_route_tx.expected_crc = command_read_u32_le(d + 6); s_k1_route_tx.token = nonce;
        s_k1_route_tx.last_activity = command_clock_ms();
        command_write_u32_le(fields, nonce); command_write_u32_le(fields + 4, nonce); command_write_u16_le(fields + 8, 0);
        return command_k1_route_reply(sub, fields, 10);
    }
    if (sub == 0x21) {
        uint16_t chunk_offset;
        if (len < 12) return command_k1_route_error(d[1], sub, 0);
        token = command_read_u32_le(d + 3); selector = d[7]; chunk_offset = command_read_u16_le(d + 8); count = d[10];
        if (len != (uint32_t)11 + count || count == 0 || count > 47 || !s_k1_route_tx.active || token != s_k1_route_tx.token || selector != s_k1_route_tx.selector)
            return command_k1_route_error(d[1], sub, token);
        if (chunk_offset == s_k1_route_tx.last_offset && count == s_k1_route_tx.last_len && !memcmp(d + 11, s_k1_route_tx.last_data, count)) {
            /* Exact duplicate of only the most recently accepted chunk. */
        } else {
            if (chunk_offset != s_k1_route_tx.received_len || count > s_k1_route_tx.expected_len - s_k1_route_tx.received_len)
                return command_k1_route_error(d[1], sub, token);
            memcpy(s_k1_route_tx.bytes + chunk_offset, d + 11, count);
            s_k1_route_tx.last_offset = chunk_offset; s_k1_route_tx.last_len = count;
            memcpy(s_k1_route_tx.last_data, d + 11, count); s_k1_route_tx.received_len += count;
        }
        s_k1_route_tx.last_activity = command_clock_ms();
        command_write_u32_le(fields, token); fields[4] = selector;
        command_write_u16_le(fields + 5, s_k1_route_tx.received_len); fields[7] = count;
        return command_k1_route_reply(sub, fields, 8);
    }
    if (sub == 0x22) {
        if (len != 8) return command_k1_route_error(d[1], sub, len >= 7 ? command_read_u32_le(d + 3) : 0);
        token = command_read_u32_le(d + 3); selector = d[7];
        if (!s_k1_route_tx.active || token != s_k1_route_tx.token || selector != s_k1_route_tx.selector ||
            s_k1_route_tx.received_len != s_k1_route_tx.expected_len ||
            k1_restore_store_crc32(s_k1_route_tx.bytes, s_k1_route_tx.expected_len) != s_k1_route_tx.expected_crc)
            return command_k1_route_error(d[1], sub, token);
        if (selector == 0xff) {
            for (uint8_t i = 0; i < K1_ROUTE_MODE_COUNT; ++i) {
                const uint8_t *p = s_k1_route_tx.bytes + i * K1_ROUTE_SERIALIZED_SIZE;
                routes[i].kind = p[0]; routes[i].length = p[1]; memset(routes[i].data, 0, sizeof(routes[i].data));
                if (routes[i].length <= K1_ROUTE_ACTION_MAX) memcpy(routes[i].data, p + 2, routes[i].length);
            }
        } else {
            if (!k1_restore_store_load(routes, 0)) return command_k1_route_error(d[1], sub, token);
            const uint8_t *p = s_k1_route_tx.bytes;
            routes[selector].kind = p[0]; routes[selector].length = p[1]; memset(routes[selector].data, 0, sizeof(routes[selector].data));
            if (routes[selector].length <= K1_ROUTE_ACTION_MAX) memcpy(routes[selector].data, p + 2, routes[selector].length);
        }
        if (!k1_restore_store_replace(routes) || !k1_restore_store_project()) return command_k1_route_error(d[1], sub, token);
        s_k1_route_tx.active = 0;
        command_write_u32_le(fields, token); fields[4] = selector;
        command_write_u32_le(fields + 5, s_k1_route_tx.expected_crc);
        return command_k1_route_reply(sub, fields, 9);
    }
    return command_k1_route_error(d[1], sub, 0);
}
static void command_link_open(uint8_t transport, uint16_t handle, uint8_t config)
{
    uint32_t irq;
    command_link_s *link = &s_links[transport];
    PRINT("[K1DIAG] command_link_open_begin transport=%u old_live=%u old_handle=%u new_handle=%u config=%u generation=%lu\n",
          transport, link->live, link->handle, handle, config,
          (unsigned long)link->generation);
    command_link_lost(transport);
    SYS_DisableAllIrq(&irq);
    /* Fail closed at wrap: task drains every old reference before counter reuse. */
    if (link->generation == 0xffffffffUL) {
        tmos_set_event(mTaskID, MCT_COMMAND_TODO);
    } else {
        ++link->generation;
        link->handle = handle;
        link->config = config;
        link->live = 1;
    }
    SYS_RecoverIrq(irq);
    PRINT("[K1DIAG] command_link_open_done transport=%u live=%u handle=%u generation=%lu\n",
          transport, link->live, link->handle, (unsigned long)link->generation);
}
void command_usb_configured(uint8_t config)
{
    if (!config) command_link_lost(1);
    else if (!s_links[1].live || s_links[1].config != config)
        command_link_open(1, 0, config);
}
void command_ble_connected(uint16_t handle)
{
    command_link_open(0, handle, 1);
}
void command_receive_fault(uint8_t transport)
{
    if (transport > 1) return;
    s_links[transport].count = 0;
    s_links[transport].malformed = 1;
    tmos_set_event(mTaskID, MCT_COMMAND_TODO);
}
#if !defined(CP2_6_ROUTE_PROTOCOL_HOST_TESTS)
void command_process_losses(void)
{
    command_resource_upload_init_once();
    for (uint8_t i = 0; i < 2; ++i) {
        command_link_s *link = &s_links[i];
        uint32_t irq;
        uint8_t bad;
        SYS_DisableAllIrq(&irq);
        bad = link->malformed;
        link->malformed = 0;
        if (link->count && !command_identity_live(link->partial_id)) link->count = 0;
        if (s_o_phase[i] != O_EMPTY && !command_identity_live(link->ready_id)) {
            if (s_o_phase[i] == O_RAW_BEGIN && s_resource_writer.mode == RESOURCE_JOB_RAW_BEGIN)
                resource_flash_writer_cancel(&s_resource_writer);
            if (s_o_phase[i] == O_EXECUTING || s_o_phase[i] == O_CANCELLED)
                s_o_phase[i] = O_CANCELLED;
            else { s_o_phase[i] = O_EMPTY; link->ready_len = 0; }
        }
        SYS_RecoverIrq(irq);
        if (s_resource_upload.active &&
            (!command_identity_live(s_upload_owner) ||
             (bad && s_upload_owner.transport == i &&
              command_identity_equal(s_upload_owner, command_identity(i))))) {
            if (s_resource_writer.active || s_resource_writer.busy)
                resource_flash_writer_cancel(&s_resource_writer);
            else
                resource_upload_abort_invalid(&s_resource_upload);
        }
        if (s_chunk_ack_pending && !command_identity_live(s_chunk_ack_owner))
            s_chunk_ack_pending = 0;
    }
    if (s_raw_ack.state && !command_identity_live(s_raw_ack.owner)) s_raw_ack.state = 0;
    for (uint8_t n = 0; n < s_side_count;) {
        command_identity_s id;
        memcpy(&id.generation, s_side[n], 4);
        memcpy(&id.handle, s_side[n] + 4, 2);
        id.transport = s_side[n][6];
        if (!command_identity_live(id)) {
            --s_side_count;
            memmove(s_side[n], s_side[n + 1], (s_side_count - n) * 12u);
        } else ++n;
    }
    if (s_raw_owned && !command_identity_live(s_raw_owner)) {
        if (s_resource_writer.mode == RESOURCE_JOB_RAW_DATA)
            resource_flash_writer_cancel(&s_resource_writer);
        lwrb_skip(&ble_data_lwrb, lwrb_get_full(&ble_data_lwrb));
        s_raw_owned = 0;
        running_data.pic_writing = 0;
    }
    /* Never reuse generation zero; drain execution and recovery before wrap. */
    for (uint8_t i = 0; i < 2; ++i)
        if (!s_links[i].live && s_links[i].generation == 0xffffffffUL &&
            !s_executing && !s_raw_owned && !s_resource_upload.active && !s_resource_upload.pending_mask &&
            !s_resource_writer.active && !s_resource_writer.busy && !s_chunk_ack.state && !s_raw_ack.state &&
            !s_side_count && s_o_phase[i] == O_EMPTY && !usb_ep2_tx_pending())
            s_links[i].generation = 0;
}
void command_recovery_tick(void)
{
    uint32_t before = s_resource_upload.pending_mask;
    command_process_losses();
    if (s_k1_route_tx.active && (uint32_t)(command_clock_ms() - s_k1_route_tx.last_activity) >= 30000u)
        s_k1_route_tx.active = 0;
    /* Loss handling already made its one immediate attempt on this tick. */
    if (before) resource_upload_retry_one(&s_resource_upload);
}
uint8_t command_resource_pending(uint8_t entry)
{
    return entry < 19 && (s_resource_upload.pending_mask & (1UL << entry)) != 0;
}
uint8_t command_resource_unavailable(uint8_t entry)
{
    return command_resource_pending(entry) ||
           (s_resource_upload.active && s_resource_upload.entry_id == entry);
}
void command_boot_sanitize(void)
{
    command_resource_upload_init_once();
    for (uint8_t i = 0; i < DISPLAY_RESOURCE_ENTRY_COUNT; ++i) {
        display_resource_metadata_s *m = &key_bund.display_resource_metadata[i];
        display_resource_entry_s entry;
        display_resource_entry_get(i, &entry);
        /* Erased migration is only the all-erased record, not a valid CRC of FFFFFFFF. */
        const uint8_t *bytes = (const uint8_t *)m;
        uint8_t erased = 1;
        for (unsigned n = 0; n < sizeof(*m); ++n) if (bytes[n] != 0xff) erased = 0;
        if (erased) { memset(m, 0, sizeof(*m)); continue; }
        if (m->write_state == DISPLAY_RESOURCE_WRITE_WRITING ||
            m->write_state > DISPLAY_RESOURCE_WRITE_INVALID || m->user_resource_valid > 1 ||
            (m->user_resource_valid != (m->write_state == DISPLAY_RESOURCE_WRITE_VALID)) ||
            (m->user_resource_valid && (!m->frame_count || m->frame_count > entry.max_frames ||
             m->payload_bytes != (uint32_t)m->frame_count * DISPLAY_RESOURCE_FRAME_BYTES))) {
            resource_upload_mark_invalid(&s_resource_upload, i);
            memset(m, 0, sizeof(*m)); m->write_state = DISPLAY_RESOURCE_WRITE_INVALID;
        }
    }
    task_resource_selection_dirty();
}
#endif
static void command_receive(uint8_t transport, uint8_t *data, uint32_t len)
{
    command_link_s *link = &s_links[transport];
    if (!data || !len || !link->live) return;
    if (len > 256) { command_receive_fault(transport); return; }
    for (uint32_t n = 0; n < len; ++n) {
        uint8_t b = data[n];
        if (s_o_phase[transport] != O_EMPTY) return;
        if (link->count && !command_identity_live(link->partial_id)) link->count = 0;
        if (!link->count) {
            if (b == 0xaa) {
                link->partial_id = command_identity(transport);
                link->partial[link->count++] = b;
            }
            continue;
        }
        if (link->count == 1 && b != 0xbb) {
            link->count = b == 0xaa ? 1 : 0;
            continue;
        }
        if (link->count >= sizeof(link->partial)) { command_receive_fault(transport); return; }
        link->partial[link->count++] = b;
        if (link->count < 5) continue;
        uint16_t total = 0;
        if (link->partial[2] == 0x9e && link->partial[3] == 2 && link->partial[4] == 0x31)
            total = 15; /* V2 nonce/token may contain the delimiter bytes. */
        else if (link->partial[2] == 0x8a) total = 16;
        else if (link->partial[2] == 0x8b) {
            if (link->count < 9) continue;
            if (!link->partial[8] || link->partial[8] > 48) { command_receive_fault(transport); return; }
            total = link->partial[8] + 11;
        } else if (link->partial[link->count - 2] == 0xcc && b == 0xdd) total = link->count;
        if (!total || link->count < total) continue;
        if (link->partial[total - 2] != 0xcc || b != 0xdd) {
            command_receive_fault(transport); return;
        }
        if (command_identity_live(link->partial_id)) {
            memcpy(link->ready, link->partial + 2, total - 4);
            link->ready_id = link->partial_id;
            link->ready_len = total - 4;
            s_o_phase[transport] = O_REQUEST; /* Publish only after bytes and identity. */
            tmos_set_event(mTaskID, MCT_COMMAND_TODO);
        }
        link->count = 0;
        return; /* Stop-and-wait: discard concatenated bytes, never synthesize a command. */
    }
}
void receive_bytes(uint8_t *d, uint32_t len) { command_receive(0, d, len); }
void command_receive_ble(uint16_t handle, uint8_t *d, uint32_t len)
{
    if (s_links[0].handle == handle) command_receive(0, d, len);
}
void receive_usb_bytes(uint8_t *d, uint32_t len) { command_receive(1, d, len); }
#if !defined(CP2_6_ROUTE_PROTOCOL_HOST_TESTS)
static void command_receive_raw(uint8_t transport, uint8_t *d, uint32_t len)
{
    command_identity_s id = command_identity(transport);
    if (!d || !len || !command_identity_live(id) || command_cp2_resource_upload_active()) return;
    if (s_raw_owned && !command_identity_equal(id, s_raw_owner)) return;
    if (!s_raw_owned) { s_raw_owner = id; s_raw_owned = 1; }
    data_transport = transport;
    lwrb_write(&ble_data_lwrb, d, len);
    tmos_set_event(mTaskID, MCT_DATA_TODO);
}
void receive_data(uint8_t *d, uint32_t len) { command_receive_raw(0, d, len); }
void receive_usb_data(uint8_t *d, uint32_t len) { command_receive_raw(1, d, len); }
uint8_t command_raw_admit(void)
{
    command_process_losses();
    uint32_t irq; uint8_t ok;
    SYS_DisableAllIrq(&irq);
    ok = s_raw_owned && command_identity_live(s_raw_owner) && !command_cp2_resource_upload_active();
    SYS_RecoverIrq(irq);
    return ok;
}
void command_raw_complete(void)
{
    if (!lwrb_get_full(&ble_data_lwrb)) s_raw_owned = 0;
}
void command_dispatch_one(void)
{
    command_process_losses();
    for (uint8_t n = 0; n < 2; ++n) {
        uint8_t i = (s_next_link + n) % 2;
        command_link_s *link = &s_links[i];
        uint32_t irq;
        SYS_DisableAllIrq(&irq);
        if (s_o_phase[i] != O_REQUEST || !command_identity_live(link->ready_id)) {
            SYS_RecoverIrq(irq); continue;
        }
        if (((s_resource_writer.active || s_resource_writer.busy) &&
             s_resource_writer.mode != RESOURCE_JOB_CP2 && link->ready[0] != 0) ||
            (link->ready[0] == 0x80 && (s_raw_ack.state ||
             (s_raw_owned && lwrb_get_full(&ble_data_lwrb))))) {
            SYS_RecoverIrq(irq); continue;
        }
        s_o_phase[i] = O_EXECUTING;
        command_len = link->ready_len;
        s_execution = link->ready_id;
        s_executing = command_in_process = 1;
        command_transport = i;
        SYS_RecoverIrq(irq);
        command_data = link->ready;
        command_process(command_data, command_len);
        s_executing = 0;
        if (s_o_phase[i] == O_EXECUTING || s_o_phase[i] == O_CANCELLED) {
            s_o_phase[i] = O_EMPTY; link->ready_len = 0;
        }
        command_process_ok();
        s_next_link = 1 - i;
        break;
    }
    if (s_links[0].ready_len || s_links[1].ready_len)
        tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
}
#endif

#if !defined(CP2_6_ROUTE_PROTOCOL_HOST_TESTS)
void command_process(uint8_t *d, uint32_t len)
{
    if (!d || !len || !command_execution_live()) return;
    // ps("rec:");
    // for (int i = 0; i < len; i++)
    //     ps("%02x ", d[i]);
    // ps("\n");
    // ps("len= %d\n", len);
    refresh_power_off_timeout();
    if (d[0] == 0) { // update event
        command_return_state();
        return;
    }
    if (d[0] == 0x9e) {
        (void)command_k1_route_handle(d, len);
        return;
    }
    if (restore_initialization_is_quarantined() &&
        !(d[0] == 0x00 || d[0] == 0x83 || d[0] == 0x88 || d[0] == 0x9f ||
          (d[0] == 0x96 && len == 1))) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (s_resource_writer.fault) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (s_chunk_ack.state || s_resource_writer.active || s_resource_writer.busy) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    command_resource_upload_init_once();
    if (s_resource_upload.pending_mask ||
        (s_resource_upload.active && !command_identity_equal(s_execution, s_upload_owner))) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (resource_upload_transaction_active(&s_resource_upload) &&
        d[0] != AHAKEY_CMD_RESOURCE_UPLOAD_CHUNK &&
        d[0] != AHAKEY_CMD_RESOURCE_UPLOAD_COMMIT) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x9F) {
        if (len != 1) {
            command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
            return;
        }

        uint8_t ret[2 + 2 + sizeof(kFirmwareCatalogKey) - 1 + 2];
        uint8_t ret_len = 0;
        ret[ret_len++]  = 0xaa;
        ret[ret_len++]  = 0xbb;
        ret[ret_len++]  = 0x9F;
        ret[ret_len++]  = AHAKEY_STATUS_OK;
        memcpy(ret + ret_len, kFirmwareCatalogKey, sizeof(kFirmwareCatalogKey) - 1);
        ret_len += sizeof(kFirmwareCatalogKey) - 1;
        ret[ret_len++] = 0xcc;
        ret[ret_len++] = 0xdd;
        command_return_frame(ret, ret_len);
        return;
    }
    if (d[0] == 0x96) {
        if (len == 1) {
            uint8_t ret[] = {0xaa, 0xbb, 0x96, AHAKEY_STATUS_OK,
                             key_bund.voice_onboarding_state, 0xcc, 0xdd};
            command_return_frame(ret, sizeof(ret));
        } else if (len == 2) {
            if (d[1] != VOICE_ONBOARDING_SUPPRESSED_BY_DESKTOP) {
                command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
            } else if (voice_onboarding_persist_state(VOICE_ONBOARDING_SUPPRESSED_BY_DESKTOP)) {
                command_return(d[0], AHAKEY_STATUS_OK);
            } else {
                command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
            }
        } else {
            command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
        }
        return;
    }
    if (d[0] == 0x87) {
        uint8_t action_type;
        uint8_t action_len;
        uint8_t desc_len;
        uint8_t ret[64];
        uint8_t ret_len = 0;
        uint8_t *action;
        uint8_t *desc;
        if (len != 3) {
            command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
            return;
        }
        if (d[1] >= USER_MODE_COUNT || d[2] >= USER_KEY_COUNT) {
            command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
            return;
        }
        action = key_bund.user_key_bind[d[1]][d[2]];
        desc   = key_bund.user_key_desc[d[1]][d[2]];

        action_type = action[0];
        action_len  = ordinary_key_action_payload_len(action);
        if (action_len == 0xff) {
            command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
            return;
        }
        if (action_type == 0x00)
            action_len = 0;
        desc_len = ordinary_key_desc_trimmed_len(desc);
        if ((uint16_t) 11 + action_len + desc_len > sizeof(ret)) {
            command_return(d[0], AHAKEY_STATUS_TOO_LARGE);
            return;
        }

        ret[ret_len++] = 0xaa;
        ret[ret_len++] = 0xbb;
        ret[ret_len++] = 0x87;
        ret[ret_len++] = AHAKEY_STATUS_OK;
        ret[ret_len++] = d[1];
        ret[ret_len++] = d[2];
        ret[ret_len++] = action_type;
        ret[ret_len++] = action_len;
        if (action_len) {
            memcpy(ret + ret_len, action + 2, action_len);
            ret_len += action_len;
        }
        ret[ret_len++] = desc_len;
        if (desc_len) {
            memcpy(ret + ret_len, desc, desc_len);
            ret_len += desc_len;
        }
        ret[ret_len++] = 0xcc;
        ret[ret_len++] = 0xdd;
        command_return_frame(ret, ret_len);
        return;
    }
    if (d[0] == 0x97) {
        if (len == 1) {
            uint8_t ret[64];
            uint8_t ret_len = 0;
            ret[ret_len++]  = 0xaa;
            ret[ret_len++]  = 0xbb;
            ret[ret_len++]  = 0x97;
            ret[ret_len++]  = AHAKEY_STATUS_OK;
            ret[ret_len++]  = running_data.sw_state;
            ret[ret_len++]  = SIDE_SWITCH_POSITION_COUNT;
            for (uint8_t position = 0; position < SIDE_SWITCH_POSITION_COUNT; position++) {
                side_switch_position_config_s *config = &key_bund.side_switch_config.position[position];
                uint8_t action_len = config->bind_type == SIDE_SWITCH_BIND_CUSTOM ?
                                     side_switch_actual_action_len(config->action) : 0;
                if (ret_len + 2 + action_len + 2 > sizeof(ret)) {
                    command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
                    return;
                }
                ret[ret_len++] = config->bind_type;
                ret[ret_len++] = action_len;
                if (action_len) {
                    memcpy(ret + ret_len, config->action, action_len);
                    ret_len += action_len;
                }
            }
            ret[ret_len++] = 0xcc;
            ret[ret_len++] = 0xdd;
            command_return_frame(ret, ret_len);
        } else {
            uint8_t offset = 2;
            uint8_t combined_action_len = 0;
            side_switch_config_s next_config;
            if (len < 2 || d[1] != 0x01) {
                command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
                return;
            }
            memset(&next_config, 0, sizeof(next_config));
            next_config.magic = SIDE_SWITCH_CONFIG_MAGIC;
            for (uint8_t position = 0; position < SIDE_SWITCH_POSITION_COUNT; position++) {
                uint8_t bind_type;
                uint8_t action_len;
                if (offset + 2 > len) {
                    command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
                    return;
                }
                bind_type = d[offset++];
                action_len = d[offset++];
                if (bind_type > SIDE_SWITCH_BIND_CUSTOM || offset + action_len > len) {
                    command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
                    return;
                }
                next_config.position[position].bind_type = bind_type;
                if (bind_type == SIDE_SWITCH_BIND_CUSTOM) {
                    if (action_len < 2 || action_len > SIDE_SWITCH_ACTION_BIND_LEN ||
                        (d[offset] != 0x73 && d[offset] != 0x74) ||
                        (uint8_t) (d[offset + 1] + 2) != action_len ||
                        combined_action_len + action_len > SIDE_SWITCH_MAX_COMBINED_ACTION_BYTES) {
                        command_return(d[0], AHAKEY_STATUS_OUT_OF_RANGE);
                        return;
                    }
                    memcpy(next_config.position[position].action, d + offset, action_len);
                    combined_action_len += action_len;
                } else if (action_len != 0) {
                    command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
                    return;
                }
                offset += action_len;
            }
            if (offset != len) {
                command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
                return;
            }
            memcpy(&key_bund.side_switch_config, &next_config, sizeof(key_bund.side_switch_config));
            running_data.have_update_custom_data = 1;
            save_key_bound_data();
            side_switch_action_gate_reset();
            command_return(d[0], AHAKEY_STATUS_OK);
        }
        return;
    }

    if (d[0] == 0x88) {
        uint8_t ret[64];
        uint8_t ret_len = 0;
        ret[ret_len++]  = 0xaa;
        ret[ret_len++]  = 0xbb;
        ret[ret_len++]  = 0x88;
        ret[ret_len++]  = DISPLAY_CONFIG_STATUS_OK;
        if (len == 2 && d[1] == DISPLAY_CONFIG_READ_BRIGHTNESS) {
            ret[ret_len++] = d[1];
            ret[ret_len++] = key_bund.ws2812_brightness;
        } else if (len == 4 && d[1] == DISPLAY_CONFIG_READ_SINGLE_LIGHT_EFFECT) {
            if (d[2] >= USER_MODE_COUNT || d[3] >= CL_STATE_COUNT) {
                command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
                return;
            }
            ret[ret_len++] = d[1];
            ret[ret_len++] = d[2];
            ret[ret_len++] = d[3];
            ret[ret_len++] = key_bund.ai_light_mode[d[2]][d[3]];
        } else if (len == 3 && d[1] == DISPLAY_CONFIG_READ_RESOURCE_BASIC) {
            display_resource_metadata_s metadata;
            if (!display_config_store_get_metadata(d[2], &metadata)) {
                command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
                return;
            }
            ret[ret_len++] = d[1];
            ret[ret_len++] = d[2];
            ret[ret_len++] = metadata.user_resource_valid;
            ret[ret_len++] = metadata.write_state;
        } else if (len == 3 && d[1] == DISPLAY_CONFIG_READ_RESOURCE_INTEGRITY) {
            display_resource_metadata_s metadata;
            if (!display_config_store_get_metadata(d[2], &metadata)) {
                command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
                return;
            }
            ret[ret_len++] = d[1];
            ret[ret_len++] = d[2];
            if (metadata.user_resource_valid != 1 ||
                metadata.write_state != DISPLAY_RESOURCE_WRITE_VALID) {
                metadata.frame_count   = 0;
                metadata.payload_bytes = 0;
                metadata.crc32         = 0;
            }
            command_write_u16_le(ret + ret_len, metadata.frame_count);
            ret_len += 2;
            command_write_u32_le(ret + ret_len, metadata.payload_bytes);
            ret_len += 4;
            command_write_u32_le(ret + ret_len, metadata.crc32);
            ret_len += 4;
        } else {
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        ret[ret_len++] = 0xcc;
        ret[ret_len++] = 0xdd;
        command_return_frame(ret, ret_len);
        return;
    }
    if (d[0] == 0x89) {
        uint8_t ok = 0;
        if (len == 2 && d[1] == 2) {
            display_preview_stop();
            ok = 1;
        } else if (len == 3 && d[1] == 0) {
            ok = display_preview_start_brightness(d[2]);
        } else if (len == 4 && d[1] == 1) {
            ok = display_preview_start_light(d[2], d[3]);
        }
        command_return(d[0], ok ? DISPLAY_CONFIG_STATUS_OK : DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x8A) {
        uint8_t ok;
        if (len != 12) {
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        if (!s_resource_writer.active && !s_resource_writer.busy && !s_resource_writer.fault)
            resource_flash_writer_init(&s_resource_writer);
        s_upload_owner = s_execution;
        ok = resource_upload_begin(&s_resource_upload,
                                   d[1],
                                   command_read_u16_le(d + 6),
                                   command_read_u32_le(d + 2),
                                   command_read_u32_le(d + 8));
        command_return(d[0], ok ? DISPLAY_CONFIG_STATUS_OK : DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x8B) {
        uint8_t payload_len;
        uint8_t ok;
        if (len < 7) {
            resource_upload_abort_invalid(&s_resource_upload);
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        payload_len = d[6];
        if (len != (uint32_t) payload_len + 7) {
            resource_upload_abort_invalid(&s_resource_upload);
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        s_resource_write_submitted = 0;
        ok = resource_upload_chunk(&s_resource_upload, d[1], command_read_u32_le(d + 2), d + 7, payload_len);
        if (ok && s_resource_write_submitted) {
            s_chunk_ack_owner = s_execution;
            s_chunk_ack_id = d[0];
            s_chunk_ack_pending = 1;
            tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
        } else {
            command_return(d[0], ok ? DISPLAY_CONFIG_STATUS_OK : DISPLAY_CONFIG_STATUS_FAIL);
        }
        return;
    }
    if (d[0] == 0x8C) {
        uint8_t ok;
        if (len != 2) {
            resource_upload_abort_invalid(&s_resource_upload);
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        ok = resource_upload_commit(&s_resource_upload, d[1]);
        command_return(d[0], ok ? DISPLAY_CONFIG_STATUS_OK : DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x8D) {
        if (len != 2) {
            command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
            return;
        }
        command_return(d[0],
                       display_config_store_clear_resource(d[1]) ?
                           DISPLAY_CONFIG_STATUS_OK :
                           DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x8E) {
        uint8_t ok = 0;
        if (len == 3 && d[1] == DISPLAY_CONFIG_SAVE_BRIGHTNESS) {
            ok = display_config_store_save_brightness(d[2]);
        } else if (len == 5 && d[1] == DISPLAY_CONFIG_SAVE_SINGLE_LIGHT_EFFECT) {
            ok = display_config_store_save_single_light(d[2], d[3], d[4]);
        }
        if (ok)
            display_preview_stop();
        command_return(d[0], ok ? DISPLAY_CONFIG_STATUS_OK : DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }
    if (d[0] == 0x8F) {
        command_return(d[0], DISPLAY_CONFIG_STATUS_FAIL);
        return;
    }

#if AHAKEY_SDK_ENABLE && AHAKEY_ENABLE_USER_COMMANDS
    if (d[0] >= AHAKEY_PROTOCOL_USER_MIN && d[0] <= AHAKEY_PROTOCOL_USER_MAX) {
        if (ahakey_sdk_dispatch_command(d[0], d + 1, len > 1 ? len - 1 : 0)) {
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
#endif

    if (d[0] == 0x01) // change _name
    {
        memset(data_in_fram.device_name, 0, sizeof(data_in_fram.device_name));
        memcpy(data_in_fram.device_name, d + 1, len - 1);
    }
    if (d[0] == 0x02) { // change appearence
        memset(&data_in_fram.GAP_APPEARE, 0, sizeof(data_in_fram.GAP_APPEARE));
        memcpy(&data_in_fram.GAP_APPEARE, d + 1, len - 1);
    }
    if (d[0] == 0x03) { // reset no use, beacuse program controls power, once stopped, no power can supply
        // power_reset(0);
    }
    if (d[0] == 0x04) { // save config
        save_key_bound_data();
    }
    if (d[0] == 0x74) {
    } // old key mode

    //! ----------------------------------------------------------------
    if (d[0] == 0x73) {                   // 0x73 type mode key_index ...
        if (d[1] == 0x73 || d[1] == 0x74) // combime_key
        {
            if (d[2] < USER_MODE_COUNT && d[3] < USER_KEY_COUNT) {
                memset(key_bund.user_key_bind[d[2]][d[3]], 0, sizeof(key_bund.user_key_bind[0][0]));
                memcpy(key_bund.user_key_bind[d[2]][d[3]] + 2,
                       d + 4,
                       min(len - 4, sizeof(key_bund.user_key_bind[0][0]) - 2));
                key_bund.user_key_bind[d[2]][d[3]][0] = d[1];
                key_bund.user_key_bind[d[2]][d[3]][1] = min(len - 4, sizeof(key_bund.user_key_bind[0][0]) - 2);
                // for (int i = 0; i < 20; i++)
                //     ps("%02x ", key_bund.user_key_bind[d[2]][d[3]][i]);
                // ps("\n");
                running_data.have_update_custom_data = 1;
            }
        }
        if (d[1] == 0x75) {
            if (d[2] < USER_MODE_COUNT && d[3] < USER_KEY_COUNT) {
                memset(key_bund.user_key_desc[d[2]][d[3]], 0x20, sizeof(key_bund.user_key_desc[0][0]));
                memcpy(key_bund.user_key_desc[d[2]][d[3]], d + 4, min(len - 4, sizeof(key_bund.user_key_desc[0][0])));
                running_data.have_update_custom_data = 1;
            }
        }
    }
    if (d[0] == 0x80 && len == 8) { // flash write
        if (d[1] == 0) {
            uint16_t size    = d[2] | d[3] << 8;
            uint32_t address = 0;
            address |= d[4];
            address |= d[5] << 8;
            address |= d[6] << 16;
            address |= d[7] << 24;
            uint32_t flash_size = nor_flash_get_size();
            if (size == 0 || flash_size == 0 || address >= flash_size || size > flash_size - address) {
                (void)0; /* Serial diagnostic omitted to keep CP2 within X1 flash budget. */
                command_return(0x80, 1);
                return;
            }
            if (!resource_flash_writer_raw_begin(&s_resource_writer, address, command_clock_ms())) {
                command_return(0x80, 1);
                return;
            }
            s_o_phase[s_execution.transport] = O_RAW_BEGIN;
            tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
            return;
        }
    }
    if (d[0] == 0x82 && len == 8) { // pic information update
        if (d[1] < USER_MODE_COUNT) {
            uint16_t t;
            t = d[2];
            t |= d[3] << 8;
            key_bund.pic[d[1]][0] = t;

            t = d[4];
            t |= d[5] << 8;
            key_bund.pic[d[1]][1] = t;

            t = d[6];
            t |= d[7] << 8;
            key_bund.pic[d[1]][2] = t;
            /* Legacy config remains readable; serial-only diagnostic omitted. */
            running_data.have_update_custom_data = 1;
        }
    }
    if (d[0] == 0x83) { // pic information query
        if (d[1] < USER_MODE_COUNT) {
            uint8_t ret[20];
            uint8_t ret_len = 0;
            ret[ret_len++]  = 0xaa;
            ret[ret_len++]  = 0xbb;
            ret[ret_len++]  = 0x83;
            ret[ret_len++]  = 0;
            ret[ret_len++]  = d[1];
            memcpy(ret + ret_len, (uint8_t *) (key_bund.pic[d[1]]), sizeof(key_bund.pic[0]));
            ret_len += sizeof(key_bund.pic[0]);
            uint16_t max_pic_size = nor_flash_get_size() / 7 / 4096;
            memcpy(ret + ret_len, (uint8_t *) (&max_pic_size), sizeof(max_pic_size));
            ret_len += sizeof(max_pic_size);
            ret[ret_len++] = 0xcc;
            ret[ret_len++] = 0xdd;
            command_return_frame(ret, ret_len);
        }
        return;
    }
    if (d[0] == 0x84) { // AI state light config: mode + CL_STATE_COUNT light mode bytes
        if (len == 2 + CL_STATE_COUNT && d[1] < USER_MODE_COUNT) {
            for (uint8_t state = 0; state < CL_STATE_COUNT; state++) {
                uint8_t light_mode = d[2 + state];
                if (light_mode > WS2812_APPROVAL_WAIT)
                    light_mode = WS2812_OFF;
                key_bund.ai_light_mode[d[1]][state] = light_mode;
            }
            running_data.have_update_custom_data = 1;
            if (running_data.mode_data == d[1])
                update_claude_ws2812();
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x85) { // WS2812 brightness config: brightness 1..100
        if (len == 2 && d[1] >= 1 && d[1] <= 100) {
            key_bund.ws2812_brightness = d[1];
            ws2812_state.global_light  = key_bund.ws2812_brightness;
            running_data.have_update_custom_data = 1;
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x95) {
        if (len == 1) {
            uint8_t ret[8];
            uint8_t ret_len = 0;
            uint8_t lo;
            uint8_t hi;
            standby_config_sanitize_stored_minutes(&key_bund.auto_power_off_minutes);
            standby_config_set_effective_minutes(key_bund.auto_power_off_minutes);
            standby_config_encode_query_payload(standby_config_effective_minutes(), &lo, &hi);
            ret[ret_len++]  = 0xaa;
            ret[ret_len++]  = 0xbb;
            ret[ret_len++]  = 0x95;
            ret[ret_len++]  = 0;
            ret[ret_len++]  = lo;
            ret[ret_len++]  = hi;
            ret[ret_len++]  = 0xcc;
            ret[ret_len++]  = 0xdd;
            command_return_frame(ret, ret_len);
        } else if (len == 3) {
            uint16_t minutes = d[1] | (d[2] << 8);
            if (!standby_config_is_supported_minutes(minutes)) {
                command_return(d[0], STANDBY_CONFIG_OUT_OF_RANGE);
            } else if (persist_standby_minutes(minutes)) {
                command_return(d[0], 0);
            } else {
                command_return(d[0], STANDBY_CONFIG_SAVE_FAILED);
            }
        } else {
            command_return(d[0], STANDBY_CONFIG_INVALID_PAYLOAD);
        }
        return;
    }
    if (d[0] == 0x90) { // claude state update
        if (len == 2 && d[1] < CL_STATE_COUNT) {
            display_presentation_result_e result = task_apply_single_state(d[1]);
            if (result == DISPLAY_PRESENTATION_RESULT_ACCEPTED) {
                (void)0; /* Serial diagnostic omitted to keep CP2 within X1 flash budget. */
                refresh_ai_presentation_idle_sleep();
#if AHAKEY_SDK_ENABLE
                ahakey_sdk_emit_ai_state(sdk_map_claude_state(d[1]));
#endif
            }
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x91) { // direct WS2812 light effect from upper software
        if (len == 2 && d[1] <= WS2812_APPROVAL_WAIT) {
            running_data.ws2812_mode_ignore_flag = 0;
            running_data.ws2812_single_color     = 0x102080;
            running_data.ws2812_mode             = (enum ws2812_mode_e) d[1];
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x92) { // set keyboard work mode from upper software
        if (len == 2 && d[1] < USER_MODE_COUNT) {
            running_data.edit_flag = 1;
            running_data.have_edit = 1;
            set_mode(d[1]);
            tmos_start_task(mTaskID, MCT_MODE_END, MS1_TO_SYSTEM_TIME(1500));
            command_return(d[0], 0);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x93) { // AI OLED GIF config: mode + ai_oled_state + start + count + interval_ms
        if (len == 9 && d[1] < USER_MODE_COUNT && d[2] > AI_OLED_IDLE && d[2] < AI_OLED_STATE_COUNT) {
            uint16_t start;
            uint16_t count;
            uint16_t interval_ms;
            uint16_t max_pic_size = nor_flash_get_size() / 7 / 4096;

            start       = d[3];
            start |= d[4] << 8;
            count       = d[5];
            count |= d[6] << 8;
            interval_ms = d[7];
            interval_ms |= d[8] << 8;

            if (count == 0 || (max_pic_size > 0 && (uint32_t) start + count <= max_pic_size)) {
                key_bund.ai_pic[d[1]][d[2]][0] = start;
                key_bund.ai_pic[d[1]][d[2]][1] = count;
                key_bund.ai_pic[d[1]][d[2]][2] = interval_ms;
                key_bund.ai_oled_magic = AI_OLED_CONFIG_MAGIC;
                running_data.have_update_custom_data = 1;
                if (running_data.mode_data == d[1] && running_data.ai_oled_active &&
                    running_data.ai_oled_state == (enum ai_oled_state_e) d[2]) {
                    running_data.pic_index = 0;
                    tmos_set_event(mTaskID, MCT_PIC_DISPLAY);
                }
                command_return(d[0], 0);
            } else {
                command_return(d[0], 2);
            }
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == 0x94) { // AI OLED GIF config query
        if (len == 3 && d[1] < USER_MODE_COUNT && d[2] > AI_OLED_IDLE && d[2] < AI_OLED_STATE_COUNT) {
            uint8_t ret[24];
            uint8_t ret_len = 0;
            uint16_t max_pic_size = nor_flash_get_size() / 7 / 4096;
            ret[ret_len++]  = 0xaa;
            ret[ret_len++]  = 0xbb;
            ret[ret_len++]  = 0x94;
            ret[ret_len++]  = 0;
            ret[ret_len++]  = d[1];
            ret[ret_len++]  = d[2];
            memcpy(ret + ret_len, (uint8_t *) (key_bund.ai_pic[d[1]][d[2]]), sizeof(key_bund.ai_pic[0][0]));
            ret_len += sizeof(key_bund.ai_pic[0][0]);
            memcpy(ret + ret_len, (uint8_t *) (&max_pic_size), sizeof(max_pic_size));
            ret_len += sizeof(max_pic_size);
            ret[ret_len++] = 0xcc;
            ret[ret_len++] = 0xdd;
            command_return_frame(ret, ret_len);
        } else {
            command_return(d[0], 1);
        }
        return;
    }
    if (d[0] == AHAKEY_CMD_TASK_LIGHT_MODE) {
        if (len == 2 && task_set_display_mode(d[1])) {
            refresh_ai_presentation_idle_sleep();
            command_return(d[0], AHAKEY_STATUS_OK);
        } else {
            command_return(d[0], len == 2 ? AHAKEY_STATUS_OUT_OF_RANGE : AHAKEY_STATUS_INVALID_PAYLOAD);
        }
        return;
    }
    if (d[0] == AHAKEY_CMD_TASK_SLOT_UPDATE) {
        uint8_t idle_refresh = 0;
        display_presentation_result_e result = task_apply_multi_snapshot(d, len, &idle_refresh);

        if (result == DISPLAY_PRESENTATION_RESULT_ACCEPTED) {
            if (idle_refresh)
                refresh_ai_presentation_idle_sleep();
            command_return(d[0], AHAKEY_STATUS_OK);
        } else if (result == DISPLAY_PRESENTATION_RESULT_IGNORED_WRONG_MODE) {
            command_return(d[0], AHAKEY_STATUS_OK);
        } else {
            command_return(d[0],
                           result == DISPLAY_PRESENTATION_RESULT_INVALID_PAYLOAD ?
                               AHAKEY_STATUS_INVALID_PAYLOAD :
                               AHAKEY_STATUS_OUT_OF_RANGE);
        }
        return;
    }
    if (d[0] == AHAKEY_CMD_TASK_HEARTBEAT) {
        if (len != 1) {
            command_return(d[0], AHAKEY_STATUS_INVALID_PAYLOAD);
        } else {
            task_ack_heartbeat();
            command_return(d[0], AHAKEY_STATUS_OK);
        }
        return;
    }
    command_return(d[0], 0);
}
void command_return(uint8_t id, uint8_t code)
{
    uint8_t ret[6];
    uint8_t ret_len = 0;
    ret[ret_len++]  = 0xaa;
    ret[ret_len++]  = 0xbb;
    ret[ret_len++]  = id;
    ret[ret_len++]  = code;
    ret[ret_len++]  = 0xcc;
    ret[ret_len++]  = 0xdd;
    command_return_frame(ret, ret_len);
}
void command_return_state(void)
{
    uint8_t ret[20];
    uint8_t ret_len = 0;
    ret[ret_len++]  = 0xaa;
    ret[ret_len++]  = 0xbb;
    ret[ret_len++]  = 0;
    ret[ret_len++]  = running_data.power_persent; // data[0] = info.BatteryLevel;
    ret[ret_len++]  = 50;                         // data[1] = info.SignalStrength;
    ret[ret_len++]  = 1;                          // data[2] = info.FirmwareVersionMain;
    ret[ret_len++]  = 0;                          // data[3] = info.FirmwareVersionSub;
    ret[ret_len++]  = running_data.mode_data;     // data[4] = info.WorkMode;
    ret[ret_len++]  = running_data.ws2812_mode;   // data[5] = info.LightMode;
    ret[ret_len++]  = running_data.sw_state;      // data[6] = info.SwitchState;
    ret[ret_len++]  = key_bund.ws2812_brightness; // data[7] = info.LightBrightness;
    ret[ret_len++]  = 0xcc;
    ret[ret_len++]  = 0xdd;
    command_return_frame(ret, ret_len);
}
#endif

void command_return_frame(uint8_t *d, uint8_t len)
{
    uint32_t irq;
    SYS_DisableAllIrq(&irq);
    if (s_executing && s_o_phase[s_execution.transport] == O_EXECUTING && command_identity_live(s_execution)) {
        command_link_s *link = &s_links[s_execution.transport];
        memcpy(link->ready, d, len);
        link->ready_len = len;
        s_o_long[s_execution.transport] = s_execution.transport == COMMAND_TRANSPORT_BLE &&
                                         !peripheralChar4NotifyIsShort(len);
        s_o_phase[s_execution.transport] = O_RESULT;
        tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
    }
    SYS_RecoverIrq(irq);
}

#if !defined(CP2_6_ROUTE_PROTOCOL_HOST_TESTS)
static uint8_t command_submit_reply(command_identity_s id, uint8_t *data, uint8_t len, uint8_t long_once)
{
    uint32_t irq;
    uint8_t accepted = 0;
    SYS_DisableAllIrq(&irq);
    if (command_identity_live(id)) {
        if (id.transport == COMMAND_TRANSPORT_USB)
            accepted = usb_ep2_try_submit(data, len, id.generation) == USB_EP2_ACCEPTED;
        else if (long_once) {
            peripheralChar4Notify(data, len);
            accepted = 1; /* Existing long fragmentation is deliberately one-shot. */
        } else accepted = peripheralChar4TryNotify(id.handle, data, len) == SUCCESS;
    }
    SYS_RecoverIrq(irq);
    return accepted;
}

void command_side_snapshot(void)
{
    command_identity_s id = s_executing ? s_execution : s_raw_owner;
    if (!(s_executing || s_raw_owned) || !command_identity_live(id)) return;
    if (s_side_count == 8) { s_tx_overflow = 1; return; }
    uint8_t *slot = s_side[s_side_count];
    memcpy(slot, &id.generation, 4);
    memcpy(slot + 4, &id.handle, 2);
    slot[6] = id.transport;
    slot[7] = running_data.power_persent;
    slot[8] = running_data.mode_data;
    slot[9] = running_data.ws2812_mode;
    slot[10] = running_data.sw_state;
    slot[11] = key_bund.ws2812_brightness;
    ++s_side_count;
    tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
}

void command_tx_pump(void)
{
    command_process_losses();
    uint8_t accepted = 0;
    for (uint8_t n = 0; n < 2 && !accepted; ++n) {
        uint8_t link_index = (s_tx_link + n) & 1;
        for (uint8_t k = 0; k < 4 && !accepted; ++k) {
            uint8_t kind = (s_tx_class[link_index] + k) & 3;
            if (!kind) {
                command_link_s *link = &s_links[link_index];
                if (s_o_phase[link_index] == O_RESULT &&
                    command_submit_reply(link->ready_id, link->ready, (uint8_t)link->ready_len, s_o_long[link_index])) {
                    s_o_phase[link_index] = O_EMPTY;
                    link->ready_len = 0;
                    accepted = 1;
                }
            } else if (kind < 3) {
                command_ack_s *a = kind == 1 ? &s_chunk_ack : &s_raw_ack;
                uint8_t frame[] = {0xaa,0xbb,a->opcode,a->code,0xcc,0xdd};
                if (a->state == 2 && a->owner.transport == link_index &&
                    command_submit_reply(a->owner, frame, sizeof(frame), 0)) {
                    a->state = 0;
                    accepted = 1;
                    tmos_set_event(mTaskID, MCT_DATA_TODO);
                }
            } else {
                for (uint8_t j = 0; j < s_side_count; ++j) {
                    uint8_t *slot = s_side[j];
                    if (slot[6] != link_index) continue;
                    command_identity_s id;
                    memcpy(&id.generation, slot, 4);
                    memcpy(&id.handle, slot + 4, 2);
                    id.transport = slot[6];
                    uint8_t frame[] = {0xaa,0xbb,0,slot[7],50,1,0,slot[8],slot[9],slot[10],slot[11],0xcc,0xdd};
                    if (command_submit_reply(id, frame, sizeof(frame), 0)) {
                        --s_side_count;
                        memmove(slot, slot + 12, (s_side_count - j) * 12u);
                        accepted = 1;
                    }
                    break;
                }
            }
            if (accepted) {
                s_tx_class[link_index] = (kind + 1) & 3;
                s_tx_link = 1 - link_index;
            }
        }
    }
    if (s_o_phase[0] != O_EMPTY || s_o_phase[1] != O_EMPTY || s_chunk_ack.state || s_raw_ack.state || s_side_count)
        tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
}

static void command_raw_fill_payload(void)
{
    if (!resource_flash_writer_raw_needs_payload(&s_resource_writer)) return;
    if (!s_raw_owned || !command_identity_live(s_raw_owner)) {
        resource_flash_writer_cancel(&s_resource_writer);
        return;
    }
    uint16_t remain = s_resource_writer.raw_write_len - s_resource_writer.raw_done;
    uint8_t count = remain > 48 ? 48 : (uint8_t)remain;
    /* The original linear prefix is retained, so appended RX never moves it. */
    uint8_t *prefix = lwrb_get_linear_block_read_address(&ble_data_lwrb);
    (void)resource_flash_writer_raw_payload(&s_resource_writer, prefix + s_resource_writer.raw_done, count);
}

static void command_raw_finish(resource_writer_result_e result)
{
    if (result != RESOURCE_WRITER_DONE && result != RESOURCE_WRITER_ERROR) return;
    if (s_resource_writer.mode == RESOURCE_JOB_RAW_BEGIN) {
        for (uint8_t i = 0; i < 2; ++i) {
            if (s_o_phase[i] != O_RAW_BEGIN) continue;
            command_link_s *link = &s_links[i];
            command_identity_s id = link->ready_id;
            if (!command_identity_live(id)) { s_o_phase[i] = O_EMPTY; link->ready_len = 0; continue; }
            if (result == RESOURCE_WRITER_DONE) {
                if (!GPIOB_ReadPortPin(GPIO_Pin_12) || !GPIOB_ReadPortPin(GPIO_Pin_17) || R8_SPI0_FIFO_COUNT) return;
                uint32_t address = command_read_u32_le(link->ready + 4);
                uint16_t size = command_read_u16_le(link->ready + 2);
                if (!command_identity_live(id)) continue;
                running_data.data_address = address;
                running_data.data_end_address = address + size;
                running_data.pic_writing = 1;
                uint8_t disposition = main_present_raw_begin_completion((uint16_t)(address / 4096));
                (void)disposition; /* Terminal decision; never a replay request. */
            }
            if (command_identity_live(id)) {
                const uint8_t reply[] = {0xaa,0xbb,0x80,result == RESOURCE_WRITER_DONE ? 0 : 1,0xcc,0xdd};
                memcpy(link->ready, reply, sizeof(reply));
                link->ready_len = sizeof(reply);
                s_o_long[i] = 0;
                s_o_phase[i] = O_RESULT;
            } else { s_o_phase[i] = O_EMPTY; link->ready_len = 0; running_data.pic_writing = 0; }
        }
    } else if (s_raw_owned && command_identity_live(s_raw_owner)) {
        if (result == RESOURCE_WRITER_DONE) {
            running_data.data_address += s_resource_writer.raw_write_len;
            lwrb_skip(&ble_data_lwrb, s_resource_writer.raw_read_len);
            if (running_data.data_address >= running_data.data_end_address) {
                s_raw_ack.state = 2;
                if (running_data.data_end_address % 4096 == 1024) {
                    running_data.pic_writing = 0;
                    tmos_start_task(mTaskID, MCT_PIC_DISPLAY, MS1_TO_SYSTEM_TIME(200));
                }
            }
            command_raw_complete();
        } else s_raw_ack.state = 0;
    }
    resource_flash_writer_release(&s_resource_writer);
    tmos_set_event(mTaskID, MCT_DATA_TODO);
}

void command_raw_data_task(void)
{
    command_process_losses();
    if (s_resource_writer.active || s_resource_writer.busy) {
        tmos_start_task(mTaskID, MCT_DATA_TODO, MS1_TO_SYSTEM_TIME(1));
        return;
    }
    if (command_cp2_resource_upload_active() || !command_raw_admit()) {
        lwrb_skip(&ble_data_lwrb, lwrb_get_full(&ble_data_lwrb));
        command_raw_complete();
        running_data.pic_writing = 0;
        return;
    }
    if (running_data.data_address < running_data.data_end_address && lwrb_get_full(&ble_data_lwrb)) {
        uint16_t read_len = lwrb_get_linear_block_read_length(&ble_data_lwrb);
        uint32_t remain = running_data.data_end_address - running_data.data_address;
        uint16_t write_len = read_len > remain ? remain : read_len;
        if (write_len == remain) {
            if (s_raw_ack.state) {
                tmos_start_task(mTaskID, MCT_DATA_TODO, MS1_TO_SYSTEM_TIME(1));
                return;
            }
            s_raw_ack.owner = s_raw_owner;
            s_raw_ack.opcode = 0x81;
            s_raw_ack.code = 0;
            s_raw_ack.state = 1;
        }
        if (!resource_flash_writer_raw_data(&s_resource_writer, running_data.data_address,
                                           read_len, write_len, command_clock_ms())) return;
        tmos_start_task(mTaskID, MCT_COMMAND_TODO, MS1_TO_SYSTEM_TIME(1));
    } else command_raw_complete();
}

void command_process_ok(void)
{
    command_in_process = 0;
    command_data       = NULL;
}
void command_data_buf_init(void)
{
    lwrb_init(&ble_data_lwrb, ble_data_rec_buf, sizeof(ble_data_rec_buf));
}
#endif
