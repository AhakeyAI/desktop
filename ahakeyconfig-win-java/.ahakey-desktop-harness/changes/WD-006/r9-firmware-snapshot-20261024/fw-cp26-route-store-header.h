#ifndef AHAKEY_K1_RESTORE_STORE_H
#define AHAKEY_K1_RESTORE_STORE_H

#include <stdint.h>

#define K1_ROUTE_MODE_COUNT 4u
#define K1_ROUTE_ACTION_MAX 100u
#define K1_ROUTE_SERIALIZED_SIZE 102u

typedef enum {
    K1_ROUTE_ORDINARY = 0,
    K1_ROUTE_CONSUMER = 1,
} k1_route_kind_t;

typedef struct {
    uint8_t kind;
    uint8_t length;
    uint8_t data[K1_ROUTE_ACTION_MAX];
} k1_route_t;

typedef enum {
    K1_STORE_UNAVAILABLE = 0,
    K1_STORE_VALID = 1,
    K1_STORE_NO_RECORD = 2,
    K1_STORE_PENDING_RESTORE = 3,
} k1_store_status_t;

uint32_t k1_restore_store_crc32(const uint8_t *data, uint16_t length);
uint8_t k1_restore_store_load(k1_route_t routes[K1_ROUTE_MODE_COUNT], uint8_t *restore_state);
uint8_t k1_restore_store_read(uint8_t mode, k1_route_t *route);
uint8_t k1_restore_store_replace(const k1_route_t routes[K1_ROUTE_MODE_COUNT]);
uint8_t k1_restore_store_project(void);
void k1_restore_store_invalidate_runtime(void);
uint8_t k1_restore_store_is_usable(void);

#endif
