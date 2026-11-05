#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ "${MACSCP_CLIPBOARD_REUSE_CHECKS:-0}" != 1 ]]; then
 MACSCP_CHECK_COMPILE_ONLY=1 ./MacSCP/check.sh
fi
{ print '@testable import MacSCPTestSupport'; cat MacSCP/ClipboardIntegrationTest.swift; } > build/checks/entries/ClipboardIntegrationTest.swift
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" -I build/checks -L build/checks -lMacSCPTestSupport -Xlinker -rpath -Xlinker "$PWD/build/checks" build/checks/entries/ClipboardIntegrationTest.swift -framework Cocoa -framework WebKit -o build/checks/ClipboardIntegration
# Requires the macOS pasteboard service; the test uses a disposable named board, never .general.
if [[ "${MACSCP_CLIPBOARD_COMPILE_ONLY:-0}" != 1 ]]; then build/checks/ClipboardIntegration; fi
