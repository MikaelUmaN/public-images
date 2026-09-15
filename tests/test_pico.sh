#!/bin/bash
# Test the Raspberry Pi Pico toolchain (run inside mikaeluman/pico:latest).
set -e

echo "=== Pico Toolchain Test ==="

echo "1. Checking Arm cross-toolchain..."
arm-none-eabi-gcc --version | head -1
arm-none-eabi-g++ --version | head -1
arm-none-eabi-objcopy --version | head -1

echo "2. Checking build tooling..."
cmake --version | head -1
ninja --version
python3 --version

echo "3. Checking Pico tooling..."
picotool version
pioasm --version

echo "4. Checking SDK..."
if [ -z "${PICO_SDK_PATH:-}" ]; then
    echo "   PICO_SDK_PATH is not set"
    exit 1
fi
echo "   PICO_SDK_PATH=${PICO_SDK_PATH}"
test -f "${PICO_SDK_PATH}/pico_sdk_init.cmake"
test -f "${PICO_SDK_PATH}/lib/cyw43-driver/src/cyw43.h" || {
    echo "   SDK submodules missing (cyw43-driver) - wireless boards will not build"
    exit 1
}
echo "   SDK and submodules present"

echo "5. Building a minimal blink firmware for pico2_w..."
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.13)
include($ENV{PICO_SDK_PATH}/pico_sdk_init.cmake)
project(smoketest C CXX ASM)
pico_sdk_init()
add_executable(smoketest main.c)
target_link_libraries(smoketest pico_stdlib)
pico_add_extra_outputs(smoketest)
EOF

cat > "$WORKDIR/main.c" <<'EOF'
#include "pico/stdlib.h"

int main(void) {
    const uint pin = 25;
    gpio_init(pin);
    gpio_set_dir(pin, GPIO_OUT);
    while (true) {
        gpio_put(pin, 1);
        sleep_ms(250);
        gpio_put(pin, 0);
        sleep_ms(250);
    }
}
EOF

cmake -S "$WORKDIR" -B "$WORKDIR/build" -G Ninja -DPICO_BOARD=pico2_w > /dev/null
cmake --build "$WORKDIR/build" > /dev/null
test -f "$WORKDIR/build/smoketest.uf2"
echo "   smoketest.uf2 built ($(stat -c%s "$WORKDIR/build/smoketest.uf2") bytes)"

echo "6. Inspecting the built firmware with picotool..."
picotool info "$WORKDIR/build/smoketest.uf2"

echo ""
echo "=== Pico Toolchain Test PASSED ==="
