/********************************** (C) COPYRIGHT
 ******************************** File Name          : hidkbd.h Author : WCH
 * Version            : V1.0
 * Date               : 2018/12/10
 * Description        :
 *********************************************************************************
 * Copyright (c) 2021 Nanjing Qinheng Microelectronics Co., Ltd.
 * Attention: This software (modified or not) and binary are used for
 * microcontroller manufactured by Nanjing Qinheng Microelectronics.
 *******************************************************************************/

#ifndef HIDKBD_H
#define HIDKBD_H
#include "CONFIG.h"

#ifdef __cplusplus
extern "C" {
#endif

/*********************************************************************
 * INCLUDES
 */

/*********************************************************************
 * CONSTANTS
 */

// Task Events
#define START_DEVICE_EVT                  0x0001
#define START_REPORT_EVT                  0x0002
#define START_PARAM_UPDATE_EVT            0x0004
#define START_PHY_UPDATE_EVT              0x0008
/*********************************************************************
 * MACROS
 */
// HID keyboard input report length
#define HID_KEYBOARD_IN_RPT_LEN           8

// HID LED output report length
#define HID_LED_OUT_RPT_LEN               1

/*********************************************************************
 * CONSTANTS
 */
// Param update delay
#define START_PARAM_UPDATE_EVT_DELAY      12800

// Param update delay
#define START_PHY_UPDATE_DELAY            1600

// HID idle timeout in msec; set to zero to disable timeout
#define DEFAULT_HID_IDLE_TIMEOUT          60000

// Minimum connection interval (units of 1.25ms)
#define DEFAULT_DESIRED_MIN_CONN_INTERVAL 6

// Maximum connection interval (units of 1.25ms)
#define DEFAULT_DESIRED_MAX_CONN_INTERVAL 8

// Slave latency to use if parameter update request
#define DEFAULT_DESIRED_SLAVE_LATENCY     0

// Supervision timeout value (units of 10ms)
#define DEFAULT_DESIRED_CONN_TIMEOUT      200

// Default passcode
#define DEFAULT_PASSCODE                  0

// Default GAP pairing mode
#define DEFAULT_PAIRING_MODE              GAPBOND_PAIRING_MODE_WAIT_FOR_REQ

// Default MITM mode (TRUE to require passcode or OOB when pairing)
#define DEFAULT_MITM_MODE                 FALSE

// Default bonding mode, TRUE to bond
#define DEFAULT_BONDING_MODE              TRUE

// Default GAP bonding I/O capabilities
#define DEFAULT_IO_CAPABILITIES           GAPBOND_IO_CAP_NO_INPUT_NO_OUTPUT

// Battery level is critical when it is less than this %
#define DEFAULT_BATT_CRITICAL_LEVEL       6

/*********************************************************************
 * FUNCTIONS
 */

/*********************************************************************
 * GLOBAL VARIABLES
 */

/*
 * Task Initialization for the BLE Application
 */
extern void HidEmu_Init(void);

/*
 * Task Event Processor for the BLE Application
 */
extern uint16_t HidEmu_ProcessEvent(uint8_t task_id, uint16_t events);

/*********************************************************************
*********************************************************************/

#ifdef __cplusplus
}
#endif

#endif
