#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
[[ $# == 1 && -f "$1" ]] || { print 'Usage: MacSCP/gui-network-audit.sh /tmp/.../fixture.json'; exit 1; }
MACSCP_OUTPUT="$PWD/build/MacSCP-NetworkAudit.app" MACSCP_LAUNCHER=MacSCP/NetworkAuditLauncher.swift MACSCP_BUNDLE_NAME=MacSCP-NetworkAudit MACSCP_BUNDLE_ID=local.macscp.networkaudit ./build-macscp.sh
cp "$1" build/MacSCP-NetworkAudit.app/Contents/Resources/gui-network-fixture.json
codesign --force --deep --sign - build/MacSCP-NetworkAudit.app
print 'Ready: build/MacSCP-NetworkAudit.app (isolated loopback SSH only)'
