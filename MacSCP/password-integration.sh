#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
MACSCP_CHECK_COMPILE_ONLY=1 ./MacSCP/check.sh
{ print '@testable import MacSCPTestSupport'; cat MacSCP/PasswordIntegrationTest.swift; } > build/checks/entries/PasswordIntegrationTest.swift
swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" -I build/checks -L build/checks -lMacSCPTestSupport -Xlinker -rpath -Xlinker "$PWD/build/checks" build/checks/entries/PasswordIntegrationTest.swift -framework Cocoa -framework WebKit -o build/checks/PasswordIntegration
if [[ "${MACSCP_PASSWORD_COMPILE_ONLY:-0}" != 1 ]]; then build/checks/PasswordIntegration; fi
