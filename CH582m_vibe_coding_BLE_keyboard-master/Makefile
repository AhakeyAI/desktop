# CH582 BLE Keyboard Firmware Makefile
# Derived from .cproject settings (Eclipse CDT / MounRiver Studio)
#
# Required variables (set via env or command line):
#   SDK_SRC  — path to EVT/EXAM/SRC      (contains Startup, Ld, RVMSIS, StdPeriphDriver, LIB)
#   HAL_DIR  — path to BLE HAL directory  (contains include/CONFIG.h, include/HAL.h, *.c)
#   LIB_DIR  — path to LIB directory      (contains libCH58xBLE.a, libISP583.a)
#   PREFIX   — toolchain prefix           (default: riscv-none-embed-)

SDK_SRC ?= ../SRC
HAL_DIR ?= ../HAL
LIB_DIR ?= $(SDK_SRC)/LIB
PREFIX  ?= riscv-none-embed-

PROJ_NAME = HID_Keyboard_582m_vibe_coding
OUT_DIR   = obj

CC      = $(PREFIX)gcc
AS      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
SIZE    = $(PREFIX)size

ARCH = -march=rv32imac_zicsr_zifencei -mabi=ilp32

CFLAGS  = $(ARCH)
CFLAGS += -Os -fmessage-length=0 -fsigned-char
CFLAGS += -ffunction-sections -fdata-sections -fno-common
CFLAGS += -std=gnu99
CFLAGS += -DDEBUG=3 -DBLE_BUFF_MAX_LEN=251
# GCC 14 promotes several warnings to errors that GCC 8 (original MRS toolchain) accepted silently
CFLAGS += -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration \
          -Wno-error=implicit-int -Wno-error=int-conversion

INCLUDES  = -I$(SDK_SRC)/Startup
INCLUDES += -IProfile/include
INCLUDES += -I$(SDK_SRC)/StdPeriphDriver/inc
INCLUDES += -I$(HAL_DIR)/include
INCLUDES += -I$(SDK_SRC)/Ld
INCLUDES += -I$(LIB_DIR)
INCLUDES += -I$(SDK_SRC)/RVMSIS
INCLUDES += -IAPP
INCLUDES += -IAPP/hardware
INCLUDES += -IAPP/hid_dev
INCLUDES += -IAPP/sub_main

LDFLAGS  = $(ARCH)
LDFLAGS += -nostartfiles
LDFLAGS += --specs=nano.specs --specs=nosys.specs
LDFLAGS += -Xlinker --gc-sections
LDFLAGS += -Xlinker --print-memory-usage
LDFLAGS += -T$(SDK_SRC)/Ld/Link.ld
# Libraries placed AFTER objects in the link command (see rule below)
# libISP583.a lives in StdPeriphDriver; LIBCH58xBLE.a uses uppercase prefix → use full filename
LDLIBS   = -L$(SDK_SRC)/StdPeriphDriver -lISP583
LDLIBS  += -L$(LIB_DIR) -l:LIBCH58xBLE.a

# --- Sources ---

SRCS_APP = $(wildcard APP/*.c APP/hardware/*.c APP/hid_dev/*.c APP/sub_main/*.c)
SRCS_PROFILE = $(wildcard Profile/*.c)

# HAL: exclude KEY.c and LED.c (unused in this project)
_HAL_ALL = $(wildcard $(HAL_DIR)/*.c)
SRCS_HAL = $(filter-out $(HAL_DIR)/KEY.c $(HAL_DIR)/LED.c,$(_HAL_ALL))

# StdPeriphDriver: exclude CH57x-only peripherals
# CH57x variants excluded; also skip USB host/dev which conflict with BLE builds
_PERIPH_EXCLUDE = CH57x_pwm.c CH57x_adc.c CH57x_usbdev.c CH57x_usbhostClass.c \
                  CH57x_usbhostBase.c CH57x_spi0.c CH57x_timer0.c CH57x_timer1.c \
                  CH57x_timer2.c CH57x_timer3.c CH57x_uart0.c CH57x_uart2.c CH57x_uart3.c \
                  CH58x_usb2dev.c CH58x_usb2hostBase.c CH58x_usb2hostClass.c \
                  CH58x_usbhostBase.c CH58x_usbhostClass.c \
                  CH58x_pwm.c CH58x_i2c.c
_PERIPH_ALL  = $(wildcard $(SDK_SRC)/StdPeriphDriver/*.c)
SRCS_PERIPH  = $(filter-out $(addprefix $(SDK_SRC)/StdPeriphDriver/,$(_PERIPH_EXCLUDE)),$(_PERIPH_ALL))

SRCS_ASM = $(SDK_SRC)/Startup/startup_CH583.S

ALL_C_SRCS = $(SRCS_APP) $(SRCS_PROFILE) $(SRCS_HAL) $(SRCS_PERIPH)
ALL_SRCS   = $(ALL_C_SRCS) $(SRCS_ASM)

# Use VPATH so make can find sources by filename regardless of directory
VPATH = $(sort $(dir $(ALL_SRCS)))

OBJS  = $(patsubst %.c,$(OUT_DIR)/%.o,$(notdir $(filter %.c,$(ALL_SRCS))))
OBJS += $(patsubst %.S,$(OUT_DIR)/%.o,$(notdir $(filter %.S,$(ALL_SRCS))))

.PHONY: all clean

all: $(OUT_DIR)/$(PROJ_NAME).hex

$(OUT_DIR)/$(PROJ_NAME).elf: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)
	$(SIZE) $@

$(OUT_DIR)/$(PROJ_NAME).hex: $(OUT_DIR)/$(PROJ_NAME).elf
	$(OBJCOPY) -O ihex $< $@
	@echo "==> $@"

$(OUT_DIR)/%.o: %.c | $(OUT_DIR)
	$(CC) $(CFLAGS) $(INCLUDES) -MMD -MP -c -o $@ $<

$(OUT_DIR)/%.o: %.S | $(OUT_DIR)
	$(AS) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(OUT_DIR):
	mkdir -p $@

clean:
	rm -rf $(OUT_DIR)

-include $(wildcard $(OUT_DIR)/*.d)
