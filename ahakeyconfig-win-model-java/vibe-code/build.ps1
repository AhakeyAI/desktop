$ErrorActionPreference = "Stop"

# Paths
$TOOLCHAIN = "C:\MRS_Toolchain\MRS_Toolchain_Win_V1.92\RISC-V Embedded GCC\bin"
$CC = "$TOOLCHAIN\riscv-none-embed-gcc.exe"
$OBJCOPY = "$TOOLCHAIN\riscv-none-embed-objcopy.exe"
$OBJDUMP = "$TOOLCHAIN\riscv-none-embed-objdump.exe"
$SIZE = "$TOOLCHAIN\riscv-none-embed-size.exe"

$PROJ = "C:\Users\20825\Desktop\vibe-code"
$SDK = "C:\WCH_SDK\ch583-main\EVT\EXAM"
$OUTDIR = "$PROJ\obj_firmware_ui_upload_fix_20260608"
$TARGET = "HID_Keyboard_582m_vibe_coding"

# Create output directory
if (-not (Test-Path $OUTDIR)) { New-Item -ItemType Directory -Path $OUTDIR | Out-Null }

# Compiler flags
$ARCH_FLAGS = "-march=rv32imac", "-mabi=ilp32"
$OPT_FLAGS = "-Os", "-fmessage-length=0", "-fsigned-char", "-ffunction-sections", "-fdata-sections", "-fno-common"
$DEFINES = "-DDEBUG=3", "-DBLE_BUFF_MAX_LEN=251"
$STD = "-std=gnu99"

# Include paths
$INCLUDES = @(
    "-I$SDK\SRC\Startup",
    "-I$PROJ\Profile\include",
    "-I$SDK\SRC\StdPeriphDriver\inc",
    "-I$SDK\BLE\HAL\include",
    "-I$SDK\SRC\Ld",
    "-I$SDK\BLE\LIB",
    "-I$SDK\SRC\RVMSIS",
    "-I$PROJ\APP",
    "-I$PROJ\APP\hardware",
    "-I$PROJ\APP\hid_dev",
    "-I$PROJ\APP\sub_main"
)

$CFLAGS = $ARCH_FLAGS + $OPT_FLAGS + $DEFINES + @($STD) + $INCLUDES + @("-c")

# Linker flags
$LDFLAGS = @(
    "-march=rv32imac", "-mabi=ilp32",
    "-T", "$SDK\SRC\Ld\Link.ld",
    "-nostartfiles",
    "--specs=nano.specs", "--specs=nosys.specs",
    "-Xlinker", "--gc-sections",
    "-L$SDK\BLE\LIB",
    "-L$SDK\SRC\StdPeriphDriver",
    "-lISP583", "-lCH58xBLE"
)

# Source files - Project
$PROJ_SRCS = @(
    Get-ChildItem "$PROJ\APP" -Recurse -Filter "*.c" | Select-Object -ExpandProperty FullName
    Get-ChildItem "$PROJ\Profile" -Recurse -Filter "*.c" | Select-Object -ExpandProperty FullName
)

# Source files - SDK HAL (only MCU.c is typically needed)
$SDK_SRCS = @(
    "$SDK\BLE\HAL\MCU.c",
    "$SDK\BLE\HAL\RTC.c",
    "$SDK\BLE\HAL\SLEEP.c",
    "$SDK\BLE\HAL\KEY.c",
    "$SDK\BLE\HAL\LED.c",
    "$SDK\SRC\RVMSIS\core_riscv.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_gpio.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_sys.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_clk.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_uart0.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_uart1.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_uart2.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_uart3.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_adc.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_flash.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_i2c.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_pwm.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_pwr.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_spi0.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_spi1.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_timer0.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_timer1.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_timer2.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_timer3.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_usbdev.c",
    "$SDK\SRC\StdPeriphDriver\CH58x_usb2dev.c"
)

# Startup assembly
$STARTUP = "$SDK\SRC\Startup\startup_CH583.S"

$ALL_SRCS = $PROJ_SRCS + $SDK_SRCS
$OBJS = @()

Write-Host "=== Building $TARGET ===" -ForegroundColor Cyan
Write-Host "Compiler: $CC"
Write-Host "Sources: $($ALL_SRCS.Count) C files + 1 ASM file"
Write-Host ""

# Compile startup assembly
Write-Host "[ASM] startup_CH583.S" -ForegroundColor Yellow
$startupObj = "$OUTDIR\startup_CH583.o"
& $CC $ARCH_FLAGS -c -x assembler-with-cpp $INCLUDES "$STARTUP" -o $startupObj
if ($LASTEXITCODE -ne 0) { Write-Host "FAILED to compile startup" -ForegroundColor Red; exit 1 }
$OBJS += $startupObj

# Compile C files
$failed = 0
foreach ($src in $ALL_SRCS) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $obj = "$OUTDIR\$name.o"
    $shortName = $src.Replace("C:\Users\20825\Desktop\vibe-code\", "").Replace("C:\WCH_SDK\ch583-main\EVT\EXAM\", "SDK\")
    Write-Host "[CC ] $shortName" -ForegroundColor Yellow
    & $CC $CFLAGS "$src" -o $obj
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $shortName" -ForegroundColor Red
        $failed++
    } else {
        $OBJS += $obj
    }
}

if ($failed -gt 0) {
    Write-Host "`n$failed file(s) failed to compile" -ForegroundColor Red
    exit 1
}

# Link
Write-Host "`n[LINK] $TARGET.elf" -ForegroundColor Green
& $CC $OBJS $LDFLAGS -o "$OUTDIR\$TARGET.elf"
if ($LASTEXITCODE -ne 0) { Write-Host "LINK FAILED" -ForegroundColor Red; exit 1 }

# Generate hex
Write-Host "[HEX ] $TARGET.hex" -ForegroundColor Green
& $OBJCOPY -O ihex "$OUTDIR\$TARGET.elf" "$OUTDIR\$TARGET.hex"

# Size
Write-Host "`n=== Size ===" -ForegroundColor Cyan
& $SIZE "$OUTDIR\$TARGET.elf"

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Output: $OUTDIR\$TARGET.hex"
