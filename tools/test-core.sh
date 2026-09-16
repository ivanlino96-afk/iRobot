#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
c++ -std=c++17 -O2 -Wall -Wextra -Werror -Ifirmware/lib/AiRobotCore/src firmware/test/native/test_core.cpp -o .build/test-core
.build/test-core
c++ -std=c++17 -O2 -Ifirmware/lib/AiRobotCore/src -Ifirmware/.pio/libdeps/xiao_esp32c3/ArduinoJson/src firmware/test/native/test_protocol.cpp -o .build/test-protocol
.build/test-protocol
cmp firmware/lib/AiRobotCore/src/core.hpp app/packages/airobot_kinematics/src/core.hpp

c++ -std=c++17 -O2 -Wall -Wextra -Werror firmware/test/native/test_servo_bench.cpp -o .build/test-servo-bench
.build/test-servo-bench
