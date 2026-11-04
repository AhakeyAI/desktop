#include "k1_restore_store.h"
#include "main.h"
#include <string.h>

#define K1_STORE_SLOT0 0x4000u
#define K1_STORE_SLOT1 0x4200u
#define K1_STORE_SLOT_SIZE 512u
#define K1_STORE_V1_SIZE 432u
#define K1_STORE_V2_VERSION 2u
#define K1_STORE_RESTORE_NEVER 0u
#define K1_STORE_RESTORE_IN_PROGRESS 1u
#define K1_STORE_RESTORE_INCOMPLETE 2u
#define K1_STORE_RESTORE_COMPLETE 3u

typedef struct {
    uint8_t valid;
    uint8_t committed_corrupt;
    uint8_t version;
    uint8_t restore_state;
    uint8_t slot;
    uint32_t generation;
    uint32_t restore_attempt;
    k1_route_t routes[K1_ROUTE_MODE_COUNT];
} k1_record_t;

static k1_record_t s_current;
static uint8_t s_scanned;
static uint8_t s_usable;
static uint8_t s_committed_corrupt;

uint32_t k1_restore_store_crc32(const uint8_t *data, uint16_t length)
{
    uint32_t crc = 0xFFFFFFFFUL;
    for (uint16_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xEDB88320UL & (0UL - (crc & 1UL)));
    }
    return ~crc;
}

static uint16_t read_u16(const uint8_t *p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t read_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static void write_u16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static void write_u32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

static uint8_t route_valid(const uint8_t *p, k1_route_t *out)
{
    uint8_t kind = p[0], len = p[1];
    if (kind == K1_ROUTE_ORDINARY) {
        if (len > K1_ROUTE_ACTION_MAX || (len && len < 2) || (len && len != (uint8_t)(p[3] + 2u))) return 0;
        if (len && p[2] != 0x73 && p[2] != 0x74) return 0;
    } else if (kind == K1_ROUTE_CONSUMER) {
        uint16_t usage;
        if (len != 2) return 0;
        usage = read_u16(p + 2);
        if (usage == 0 || usage > 0x03FFu) return 0;
    } else return 0;
    for (uint16_t i = (uint16_t)2 + len; i < K1_ROUTE_SERIALIZED_SIZE; ++i)
        if (p[i] != 0) return 0;
    if (out) {
        memset(out, 0, sizeof(*out));
        out->kind = kind;
        out->length = len;
        if (len) memcpy(out->data, p + 2, len);
    }
    return 1;
}

static void serialize_route(uint8_t *p, const k1_route_t *route)
{
    memset(p, 0, K1_ROUTE_SERIALIZED_SIZE);
    p[0] = route->kind;
    p[1] = route->length;
    if (route->length) memcpy(p + 2, route->data, route->length);
}

static uint8_t record_parse(const uint8_t raw[K1_STORE_SLOT_SIZE], uint8_t slot, k1_record_t *out)
{
    uint8_t version;
    uint16_t record_len, payload_len, crc_offset, marker_offset;
    const uint8_t *marker;
    if (memcmp(raw, "K1RT", 4) != 0) return 0;
    version = raw[4];
    if (version == 1 && memcmp(raw + 428, "K1CM", 4) == 0) out->committed_corrupt = 1;
    if (version == K1_STORE_V2_VERSION && memcmp(raw + 444, "K2CM", 4) == 0) out->committed_corrupt = 1;
    if (version != 1 && version != K1_STORE_V2_VERSION && memcmp(raw + 444, "K2CM", 4) == 0)
        out->committed_corrupt = 1;
    if (version == 1) {
        if (raw[5] != 16 || read_u16(raw + 6) != K1_STORE_V1_SIZE || read_u16(raw + 12) != 408 || read_u16(raw + 14) != 0)
            return 0;
        record_len = K1_STORE_V1_SIZE; payload_len = 408; crc_offset = 424; marker_offset = 428;
        marker = (const uint8_t *)"K1CM";
    } else if (version == K1_STORE_V2_VERSION) {
        if (raw[5] != 32 || read_u16(raw + 6) != K1_STORE_SLOT_SIZE || read_u16(raw + 12) != 408 ||
            read_u16(raw + 14) != 0 || raw[16] > K1_STORE_RESTORE_COMPLETE || raw[17] || raw[18] || raw[19] ||
            !((raw[16] == K1_STORE_RESTORE_NEVER && read_u32(raw + 20) == 0) ||
              (raw[16] != K1_STORE_RESTORE_NEVER && read_u32(raw + 20) != 0))) return 0;
        for (uint8_t i = 24; i < 32; ++i) if (raw[i]) return 0;
        for (uint16_t i = 448; i < K1_STORE_SLOT_SIZE; ++i) if (raw[i] != 0xFF) return 0;
        record_len = K1_STORE_SLOT_SIZE; payload_len = 408; crc_offset = 440; marker_offset = 444;
        marker = (const uint8_t *)"K2CM";
    } else {
        if (memcmp(raw + (version == 1 ? 428 : 444), version == 1 ? "K1CM" : "K2CM", 4) == 0)
            out->committed_corrupt = 1;
        return 0;
    }
    if (memcmp(raw + marker_offset, marker, 4) != 0) return 0;
    out->committed_corrupt = 1;
    if (k1_restore_store_crc32(raw, crc_offset) != read_u32(raw + crc_offset)) return 0;
    if (version == 1) {
        for (uint16_t i = 432; i < K1_STORE_SLOT_SIZE; ++i) if (raw[i] != 0xFF) return 0;
        out->restore_state = K1_STORE_RESTORE_NEVER;
        out->restore_attempt = 0;
    } else {
        out->restore_state = raw[16];
        out->restore_attempt = read_u32(raw + 20);
    }
    (void)record_len;
    (void)payload_len;
    for (uint8_t mode = 0; mode < K1_ROUTE_MODE_COUNT; ++mode)
        if (!route_valid(raw + (version == 1 ? 16 : 32) + mode * K1_ROUTE_SERIALIZED_SIZE, &out->routes[mode])) return 0;
    out->valid = 1; out->version = version; out->slot = slot; out->generation = read_u32(raw + 8);
    out->committed_corrupt = 0;
    return 1;
}

static uint8_t generation_newer(uint32_t a, uint32_t b)
{
    uint32_t delta = a - b;
    return delta && delta < 0x80000000UL;
}

static uint8_t scan_store(void)
{
    uint8_t raw[2][K1_STORE_SLOT_SIZE];
    k1_record_t rec[2];
    uint8_t ok[2] = {0, 0};
    memset(rec, 0, sizeof(rec));
    EEPROM_READ(K1_STORE_SLOT0, raw[0], K1_STORE_SLOT_SIZE);
    EEPROM_READ(K1_STORE_SLOT1, raw[1], K1_STORE_SLOT_SIZE);
    ok[0] = record_parse(raw[0], 0, &rec[0]);
    ok[1] = record_parse(raw[1], 1, &rec[1]);
    if ((!ok[0] && rec[0].committed_corrupt) || (!ok[1] && rec[1].committed_corrupt)) goto unavailable;
    if (!ok[0] && !ok[1]) {
        s_scanned = 1; s_usable = 0; s_committed_corrupt = 0;
        memset(&s_current, 0, sizeof(s_current));
        return 0;
    }
    if (ok[0] && !ok[1]) s_current = rec[0];
    else if (!ok[0] && ok[1]) s_current = rec[1];
    else {
        if (rec[0].version != rec[1].version) {
            k1_record_t *v1 = rec[0].version == 1 ? &rec[0] : &rec[1];
            k1_record_t *v2 = rec[0].version == 2 ? &rec[0] : &rec[1];
            if (!generation_newer(v2->generation, v1->generation)) goto unavailable;
            s_current = *v2;
            s_scanned = 1; s_usable = 1;
            return 1;
        }
        if (rec[0].generation == rec[1].generation) {
            if (memcmp(&rec[0].routes, &rec[1].routes, sizeof(rec[0].routes)) ||
                rec[0].restore_state != rec[1].restore_state || rec[0].restore_attempt != rec[1].restore_attempt) goto unavailable;
            s_current = rec[0].version >= rec[1].version ? rec[0] : rec[1];
        } else if (generation_newer(rec[0].generation, rec[1].generation)) s_current = rec[0];
        else if (generation_newer(rec[1].generation, rec[0].generation)) s_current = rec[1];
        else goto unavailable;
    }
    s_scanned = 1; s_usable = 1;
    return 1;
unavailable:
    s_scanned = 1; s_usable = 0;
    s_committed_corrupt = (uint8_t)(rec[0].committed_corrupt || rec[1].committed_corrupt);
    memset(&s_current, 0, sizeof(s_current));
    return 0;
}

static uint8_t record_write(uint8_t slot, const k1_route_t routes[K1_ROUTE_MODE_COUNT], uint32_t generation,
                            uint8_t restore_state, uint32_t restore_attempt)
{
    uint8_t raw[K1_STORE_SLOT_SIZE], verify[K1_STORE_SLOT_SIZE];
    uint16_t addr = slot ? K1_STORE_SLOT1 : K1_STORE_SLOT0;
    memset(raw, 0xFF, sizeof(raw));
    memcpy(raw, "K1RT", 4); raw[4] = K1_STORE_V2_VERSION; raw[5] = 32;
    write_u16(raw + 6, K1_STORE_SLOT_SIZE); write_u32(raw + 8, generation); write_u16(raw + 12, 408); write_u16(raw + 14, 0);
    raw[16] = restore_state; raw[17] = raw[18] = raw[19] = 0; write_u32(raw + 20, restore_attempt);
    memset(raw + 24, 0, 8);
    for (uint8_t mode = 0; mode < K1_ROUTE_MODE_COUNT; ++mode) serialize_route(raw + 32 + mode * K1_ROUTE_SERIALIZED_SIZE, &routes[mode]);
    write_u32(raw + 440, k1_restore_store_crc32(raw, 440));
    EEPROM_ERASE(addr, K1_STORE_SLOT_SIZE);
    EEPROM_WRITE(addr, raw, 444);
    EEPROM_READ(addr, verify, 444);
    if (memcmp(raw, verify, 444)) return 0;
    EEPROM_WRITE(addr + 444, (uint8_t *)"K2CM", 4);
    EEPROM_READ(addr, verify, K1_STORE_SLOT_SIZE);
    if (!record_parse(verify, slot, &s_current)) return 0;
    return 1;
}

uint8_t k1_restore_store_load(k1_route_t routes[K1_ROUTE_MODE_COUNT], uint8_t *restore_state)
{
    if (!s_scanned) (void)scan_store();
    if (!s_usable) return 0;
    if (restore_state) *restore_state = s_current.restore_state;
    if (routes) memcpy(routes, s_current.routes, sizeof(s_current.routes));
    return s_current.restore_state == K1_STORE_RESTORE_NEVER || s_current.restore_state == K1_STORE_RESTORE_COMPLETE;
}

uint8_t k1_restore_store_read(uint8_t mode, k1_route_t *route)
{
    if (mode >= K1_ROUTE_MODE_COUNT || !route) return 0;
    if (!s_scanned) (void)scan_store();
    if (!s_usable || s_current.restore_state == K1_STORE_RESTORE_IN_PROGRESS || s_current.restore_state == K1_STORE_RESTORE_INCOMPLETE) return 0;
    *route = s_current.routes[mode];
    return 1;
}

uint8_t k1_restore_store_replace(const k1_route_t routes[K1_ROUTE_MODE_COUNT])
{
    uint8_t target, restore_state = K1_STORE_RESTORE_NEVER;
    uint32_t attempt = 0, generation = 1;
    k1_record_t prior;
    for (uint8_t i = 0; i < K1_ROUTE_MODE_COUNT; ++i) {
        uint8_t encoded[K1_ROUTE_SERIALIZED_SIZE]; serialize_route(encoded, &routes[i]);
        if (!route_valid(encoded, 0)) return 0;
    }
    if (!s_scanned) (void)scan_store();
    if (s_usable) {
        prior = s_current;
        if (prior.restore_state == K1_STORE_RESTORE_IN_PROGRESS || prior.restore_state == K1_STORE_RESTORE_INCOMPLETE ||
            prior.generation == 0xFFFFFFFFUL) return 0;
        generation = prior.generation + 1;
        restore_state = prior.restore_state; attempt = prior.restore_attempt; target = 1u - prior.slot;
    } else {
        if (s_committed_corrupt) return 0;
        target = 0;
    }
    if (!record_write(target, routes, generation, restore_state, attempt)) {
        s_scanned = 0;
        (void)scan_store();
        return 0;
    }
    s_scanned = s_usable = 1;
    return 1;
}

uint8_t k1_restore_store_project(void)
{
    k1_route_t routes[K1_ROUTE_MODE_COUNT];
    if (!k1_restore_store_load(routes, 0)) return 0;
    for (uint8_t mode = 0; mode < K1_ROUTE_MODE_COUNT; ++mode) {
        memset(key_bund.user_key_bind[mode][0], 0, sizeof(key_bund.user_key_bind[mode][0]));
        if (routes[mode].kind == K1_ROUTE_ORDINARY && routes[mode].length)
            memcpy(key_bund.user_key_bind[mode][0], routes[mode].data, routes[mode].length);
    }
    return 1;
}

void k1_restore_store_invalidate_runtime(void) { s_scanned = s_usable = s_committed_corrupt = 0; memset(&s_current, 0, sizeof(s_current)); }
uint8_t k1_restore_store_is_usable(void) { if (!s_scanned) (void)scan_store(); return s_usable; }
