#ifndef AHAKEY_RESOURCE_MAP_H
#define AHAKEY_RESOURCE_MAP_H

#include <stdint.h>

#define DISPLAY_RESOURCE_ENTRY_COUNT 19
#define DISPLAY_RESOURCE_FRAME_BYTES (7UL * 4096UL)
#define DISPLAY_RESOURCE_DEFAULT_MAX_FRAMES 8
#define DISPLAY_RESOURCE_STATE_MAX_FRAMES 12
#define DISPLAY_RESOURCE_MAX_CHUNK_BYTES 48

typedef enum {
    DISPLAY_RESOURCE_ROLE_MODE_DEFAULT = 0,
    DISPLAY_RESOURCE_ROLE_SINGLE_STATE = 1,
    DISPLAY_RESOURCE_ROLE_MULTI_STATE = 2,
} display_resource_role_e;

typedef struct
{
    uint8_t  entry_id;
    uint8_t  start_frame;
    uint8_t  max_frames;
    uint8_t  role;
    uint8_t  mode;
    uint8_t  state;
    uint32_t start_address;
    uint32_t max_bytes;
} display_resource_entry_s;

uint8_t display_resource_entry_get(uint8_t entry_id, display_resource_entry_s *out);
uint8_t display_resource_entry_valid(uint8_t entry_id);

#endif
