#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
MACSCP_CHECK_COMPILE_ONLY=1 ./MacSCP/check.sh
{ print '@testable import MacSCPTestSupport'; cat MacSCP/FTPIntegrationTest.swift; } > build/checks/entries/FTPIntegrationTest.swift
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" -I build/checks -L build/checks -lMacSCPTestSupport -Xlinker -rpath -Xlinker "$PWD/build/checks" build/checks/entries/FTPIntegrationTest.swift -framework Cocoa -framework WebKit -o build/checks/FTPIntegration
if [[ "${MACSCP_FTP_COMPILE_ONLY:-0}" != 1 ]]; then build/checks/FTPIntegration; fi
