#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
if [ -d /opt/homebrew/opt/openssl@3 ]; then
 OPENSSL_ROOT=/opt/homebrew/opt/openssl@3
 c++ -std=c++17 -O2 -Ifirmware/lib/AiRobotCore/src -Ifirmware/.pio/libdeps/xiao_esp32c3/ArduinoJson/src -I"$OPENSSL_ROOT/include" firmware/test/native/simulator.cpp -L"$OPENSSL_ROOT/lib" -lcrypto -o .build/simulator
else
 c++ -std=c++17 -O2 -Ifirmware/lib/AiRobotCore/src -Ifirmware/.pio/libdeps/xiao_esp32c3/ArduinoJson/src firmware/test/native/simulator.cpp -lcrypto -o .build/simulator
fi
