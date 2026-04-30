#include "command_solve.h"
#include "lwrb.h"
#include "main.h"
#include "w25qxx.h"
uint8_t  tmp_command[256];
uint16_t rx_count = 0;
uint8_t *command_data;
uint16_t command_len;
uint8_t  command_in_process;
uint8_t  ble_data_rec_buf[400];
lwrb_t   ble_data_lwrb;

void receive_data(uint8_t *d, uint32_t len)
{
    if (len != lwrb_write(&ble_data_lwrb, d, len)) {
        PRINT("loss_data\n");
    }
    tmos_set_event(mTaskID, MCT_DATA_TODO);
}

void receive_bytes(uint8_t *d, uint32_t len)
{
    if (command_in_process)
        return;
    uint16_t i = 0;
    if (tmp_command[0] == 0xaa && tmp_command[1] == 0xbb) {
        memcpy(tmp_command + rx_count, d, min(sizeof(tmp_command) - rx_count, len));
        rx_count += len;
        if (rx_count > sizeof(tmp_command)) {
            memset(tmp_command, 0, sizeof(tmp_command));
            return;
        }
        for (i = 3; i < rx_count; i++) {
            if (tmp_command[i - 1] == 0xcc && tmp_command[i] == 0xdd) {
                // command_process(tmp_command + 2, i + 1 - 4);
                command_data = tmp_command + 2;
                command_len  = i + 1 - 4;
                tmos_set_event(mTaskID, MCT_COMMAND_TODO);
                command_in_process = 1;
                // memset(tmp_command, 0, sizeof(tmp_command));
                return;
            }
        }
    } else {
        for (i = 0; i < len - 1; i++) {
            if (d[i] == 0xaa && d[i + 1] == 0xbb) {
                memcpy(tmp_command, d + i, min(sizeof(tmp_command), len - i));
                rx_count = len - i;
            }
        }
        for (i = 3; i < rx_count; i++) {
            if (tmp_command[i - 1] == 0xcc && tmp_command[i] == 0xdd) {
                // command_process(tmp_command + 2, i + 1 - 4);
                command_data = tmp_command + 2;
                command_len  = i + 1 - 4;
                tmos_set_event(mTaskID, MCT_COMMAND_TODO);
                command_in_process = 1;
                // memset(tmp_command, 0, sizeof(tmp_command));
                return;
            }
        }
    }
}
void command_process(uint8_t *d, uint32_t len)
{
    // ps("rec:");
    // for (int i = 0; i < len; i++)
    //     ps("%02x ", d[i]);
    // ps("\n");
    // ps("len= %d\n", len);
    if (d[0] == 0) { // update event
        command_return_state();
        return;
    }

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
            if (d[2] < 3 && d[3] < 4) {
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
            if (d[2] < 3 && d[3] < 4) {
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
            uint16_t sector = address / 4096;
            PRINT("size %d, address %p, se %d\n", size, address, sector);
            W25QXX_Erase_Sector(sector);
            PRINT("end\n");
            running_data.data_address     = address;
            running_data.data_end_address = address + size;
            running_data.pic_writing      = 1;
            LCD_CS_RESET;
            IPS_Clear(BLACK);
            IPS_ShowString(24, 24, "Uploading Pic...", GREEN);
            char p[20];
            sprintf(p, "%d,%d", sector / 7, sector);
            IPS_ShowString(24, 40, p, GREEN);
            LCD_CS_SET;
        }
    }
    if (d[0] == 0x82 && len == 8) { // pic information update
        if (d[1] <= 2) {
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
            PRINT("update pic:mode%d,start%d,len%d,time%dms\n",
                  d[1],
                  key_bund.pic[d[1]][0],
                  key_bund.pic[d[1]][1],
                  key_bund.pic[d[1]][2]);
            running_data.have_update_custom_data = 1;
        }
    }
    if (d[0] == 0x83) { // pic information query
        if (d[1] <= 2) {
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
            peripheralChar4Notify(ret, ret_len);
        }
        return;
    }

    if (d[0] == 0x90) { // claude state update
        running_data.claude_state = d[1];
        PRINT("CLAUDE STATE %d\n", d[1]);
        update_claude_ws2812();
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
    peripheralChar4Notify(ret, ret_len);
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
    ret[ret_len++]  = 0;                          // data[7] = info.Reserve;
    ret[ret_len++]  = 0xcc;
    ret[ret_len++]  = 0xdd;
    peripheralChar4Notify(ret, ret_len);
}

void command_process_ok(void)
{
    command_in_process = 0;
    command_data       = NULL;
    memset(tmp_command, 0, sizeof(tmp_command));
}
void command_data_buf_init(void)
{
    lwrb_init(&ble_data_lwrb, ble_data_rec_buf, sizeof(ble_data_rec_buf));
}