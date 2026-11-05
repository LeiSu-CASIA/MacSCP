#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${MACSCP_DROP_REUSE_CHECKS:-0}" != 1 ]]; then
 MACSCP_CHECK_COMPILE_ONLY=1 ./MacSCP/check.sh
fi
clang -fobjc-arc -c MacSCP/DraggingFixture.m -o build/checks/DraggingFixture.o
{ print '@testable import MacSCPTestSupport'; cat MacSCP/NativeDropIntegrationTest.swift; } > build/checks/entries/NativeDropIntegrationTest.swift
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" -I build/checks -L build/checks -lMacSCPTestSupport -Xlinker -rpath -Xlinker "$PWD/build/checks" -import-objc-header MacSCP/DraggingFixture.h build/checks/entries/NativeDropIntegrationTest.swift build/checks/DraggingFixture.o -framework Cocoa -framework WebKit -o build/checks/NativeDropIntegration
# Disposable named pasteboard only; never .general, no mouse or visible windows.
if [[ "${MACSCP_DROP_COMPILE_ONLY:-0}" != 1 ]]; then build/checks/NativeDropIntegration; fi
