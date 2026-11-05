#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
MACSCP_OUTPUT="$PWD/build/MacSCP-VisibleAudit.app" MACSCP_LAUNCHER=MacSCP/AuditLauncher.swift MACSCP_BUNDLE_NAME=MacSCP-VisibleAudit MACSCP_BUNDLE_ID=local.macscp.visibleaudit ./build-macscp.sh
print 'Visible acceptance app ready: build/MacSCP-VisibleAudit.app'
print 'Uses its own temporary files and profile. Quit normally to remove fixtures.'
