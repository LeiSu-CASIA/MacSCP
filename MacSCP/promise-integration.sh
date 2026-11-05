#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/checks build/module-cache
clang -c MacSCP/FTPCurl.c -o build/checks/FTPCurl.o
swiftc -module-cache-path "$PWD/build/module-cache" MacSCP/SFTP.swift MacSCP/RemoteFileClient.swift MacSCP/Resume.swift MacSCP/FTPPublication.swift MacSCP/QueueJournal.swift MacSCP/TransferPolicy.swift MacSCP/FTPUploadSource.swift MacSCP/FTPDownloadTarget.swift MacSCP/TextTransfer.swift MacSCP/Transfer.swift MacSCP/Checksum.swift MacSCP/Sync.swift MacSCP/FTPTransport.swift MacSCP/Sites.swift MacSCP/SSHOptions.swift MacSCP/Navigation.swift MacSCP/Listing.swift MacSCP/CommanderAppearance.swift MacSCP/CommanderChrome.swift MacSCP/AppMenu.swift MacSCP/Drag.swift MacSCP/FilePromise.swift MacSCP/NativeFilePromiseTest.swift build/checks/FTPCurl.o -lcurl -o build/checks/NativeFilePromise
if [[ "${MACSCP_PROMISE_COMPILE_ONLY:-0}" != 1 ]]; then build/checks/NativeFilePromise; fi
