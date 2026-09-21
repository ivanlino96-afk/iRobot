#!/usr/bin/env bash
# Compila airobot_kinematics como biblioteca dinámica de host para que
# `flutter test` (que corre en la VM de Dart del host, no en iOS) pueda
# resolver NativeKinematics vía dlopen. En iOS real la misma fuente se
# enlaza estáticamente mediante el podspec; este script no la afecta.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$dir/../../libairobot_kinematics.so"
clang++ -std=c++17 -dynamiclib -o "$out" "$dir/src/airobot_kinematics.cpp"
echo "Compilado: $out"
