#!/bin/bash
# Compile and run pure-logic tests against shipped sources (not mocks).
set -e
cd "$(dirname "$0")/.."
SCRATCH_OUT="${1:-./Tests/last-run.log}"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
TARGET="arm64-apple-macosx13.0"
OUT="./Tests/freenet_logic_tests"

SWIFTC_ARGS=(
  -sdk "$SDK_PATH"
  -target "$TARGET"
  -framework Foundation
  -framework CryptoKit
  IntentMode.swift
  DPIArgsValidator.swift
  EngineConfigs.swift
  ChecksumVerifier.swift
  TorReadiness.swift
  AppVersion.swift
  Tests/LogicTestsMain.swift
  -o "$OUT"
)

echo "Compiling logic tests..."
swiftc "${SWIFTC_ARGS[@]}"
echo "Running..."
set +e
"$OUT" | tee "$SCRATCH_OUT"
CODE=${PIPESTATUS[0]}
set -e
exit $CODE
