#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/checks/entries build/module-cache
clang -c Sources/PTY.c -o build/checks/PTY.o
clang -c MacSCP/FTPCurl.c -o build/checks/FTPCurl.o
# Compile the same production sources once; each unchanged test uses internal APIs via @testable.
MACSCP_TEST_SOURCES=(
 MacSCP/SFTP.swift MacSCP/RemoteFileClient.swift MacSCP/LocalReadClient.swift MacSCP/FileClipboard.swift MacSCP/App+FileClipboard.swift MacSCP/FTPTransport.swift MacSCP/FTPListing.swift MacSCP/FTPClient.swift MacSCP/FTPLogin.swift MacSCP/ConnectionForm.swift MacSCP/FTPAdvancedOptionsView.swift MacSCP/FTPUploadSource.swift MacSCP/FTPDownloadTarget.swift
 MacSCP/Resume.swift MacSCP/FTPPublication.swift
 MacSCP/QueueJournal.swift
 MacSCP/TransferPolicy.swift
 MacSCP/TransferConflict.swift
 MacSCP/TransferSettingsView.swift MacSCP/TransferOptionsWindow.swift MacSCP/App+TransferOptions.swift MacSCP/TransferPresetRule.swift MacSCP/TransferPresets.swift MacSCP/TransferPresetArchive.swift MacSCP/WinSCPPresetINI.swift MacSCP/PresetImportWindow.swift MacSCP/TransferPresetsWindow.swift MacSCP/TransferPresetRuleWindow.swift MacSCP/App+TransferPresets.swift
 MacSCP/TextTransfer.swift MacSCP/Transfer.swift
 MacSCP/TransferScheduler.swift
 MacSCP/RelayTransfer.swift
 MacSCP/RelayJournal.swift
 MacSCP/RecoverySelection.swift
 MacSCP/RecoveryWindow.swift
 MacSCP/QueueToolbar.swift
 MacSCP/FilePromise.swift
 MacSCP/Drag.swift
 MacSCP/Sync.swift
 MacSCP/SyncPreview.swift MacSCP/SyncTextComparison.swift MacSCP/SyncContents.swift MacSCP/SyncPartialDeletion.swift MacSCP/SyncContentsWindow.swift MacSCP/SyncTimestamp.swift MacSCP/ContinuousSync.swift MacSCP/ContinuousWindow.swift
 MacSCP/SyncWindow.swift
 MacSCP/Checksum.swift
 MacSCP/DirectorySize.swift
 MacSCP/FilePropertiesWindow.swift
 MacSCP/ChecksumWindow.swift
 MacSCP/Sites.swift MacSCP/PasswordVault.swift
 MacSCP/SiteImport.swift
 MacSCP/SiteImportWindow.swift
 MacSCP/SSHOptions.swift
 MacSCP/SSHOptionsView.swift
 MacSCP/Askpass.swift MacSCP/SSHCredentialChannel.swift
 MacSCP/SSHConnection.swift MacSCP/SSHAuthenticationLog.swift
 MacSCP/RemoteOperations.swift
 MacSCP/LocalTrash.swift
 MacSCP/LocalTrashWindow.swift
 MacSCP/RemoteRelocation.swift
 MacSCP/Breadcrumb.swift
 MacSCP/DirectoryTree.swift
 MacSCP/Navigation.swift
 MacSCP/LinkedBrowsing.swift
 MacSCP/AppMenu.swift
 MacSCP/CommanderAppearance.swift
 MacSCP/CommanderChrome.swift MacSCP/TaskDetailsWindow.swift
 MacSCP/Listing.swift
 MacSCP/FileSelection.swift
 MacSCP/TextDocument.swift
 MacSCP/Editor.swift
 MacSCP/Search.swift
 MacSCP/SearchWindow.swift
 MacSCP/SyncRecompare.swift MacSCP/App+SyncRetry.swift MacSCP/App.swift
 MacSCP/Pane.swift
 MacSCP/Terminal.swift
 MacSCP/TerminalWindow.swift
)
swiftc -module-cache-path "$PWD/build/module-cache" -emit-module -emit-library -enable-testing -module-name MacSCPTestSupport "${MACSCP_TEST_SOURCES[@]}" build/checks/PTY.o build/checks/FTPCurl.o -lcurl -framework Cocoa -framework WebKit -emit-module-path build/checks/MacSCPTestSupport.swiftmodule -Xlinker -install_name -Xlinker @rpath/libMacSCPTestSupport.dylib -o build/checks/libMacSCPTestSupport.dylib
if [[ "${MACSCP_CHECK_COMPILE_ONLY:-0}" == 1 ]]; then exit 0; fi
for test in SFTP Parallel Transfer Atomic Sync Sites RemoteOperations Breadcrumb NativeBreadcrumb Listing Throttle TextDocument NativeEditor Search NativeSearch Resume ResumeJob SyncPreview NativeSync Checksum NativeChecksum SSHOptions NativeSSH QueueJournal PreserveExit NativeNavigation NativeKeyboard FileDragPayload NativeDirectedDrop LocalCopy NativeFileClipboard Menu RemoteRelocation SymbolicLink NativeDirectoryTree TransferPolicy NativeTransferSettings TransferBatchOptions NativeTransferOptions TextMode TextTransfer NativeTextModes TransferProgress NativeTaskDetails TransferPresets NativeTransferPresets TransferPresetArchive NativePresetArchive TransferPresetRules NativeAutomaticTransferPresets Askpass NativeSSHConnection FilePromise QueueOrder NativeQueueControls Relay RelayRecovery LinkedBrowsing NativeLinkedApp NativeRecovery NativeRecoveryApp NativeLayout NativePaneSplit NativeConnectionState SiteImport NativeSiteImport NativeSiteImportApp NativeCommanderAppearance NativeSessionTabs NativeTransferConflict NativeFileSelection DirectorySize NativeFileProperties DirectoryHistory NativeDirectoryHistory LocalTrash NativeLocalTrash RemoteClient FTPListing FTPDownloadTarget FTPPublication NativeConnectionForm FTPSiteImport NativeFTPImport PasswordVault SSHAuthenticationLog SyncDeletion NativeSyncDeletion SyncComparisonOptions NativeSyncOptions TimestampProtocol SyncTimestamp NativeSyncTimestamp ContinuousSync ContinuousEngine NativeContinuous SyncContents NativeSyncContents SyncPartialDeletion NativePartialDeletion SyncRecompare NativeSyncRecompare SFTPDeadline; do
 case "$test" in
  SFTP) entry=MacSCP/ProtocolTest.swift ;;
  *) entry="MacSCP/${test}Test.swift" ;;
 esac
 print -- "RUN: $test"
 { print '@testable import MacSCPTestSupport'; cat "$entry"; } > "build/checks/entries/${test}Test.swift"
 swiftc -parse-as-library -module-cache-path "$PWD/build/module-cache" -I build/checks -L build/checks -lMacSCPTestSupport -Xlinker -rpath -Xlinker "$PWD/build/checks" "build/checks/entries/${test}Test.swift" -framework Cocoa -framework WebKit -o "build/checks/$test"
 "build/checks/$test"
done
MACSCP_OUTPUT="$PWD/build/候选.noindex/MacSCP-Next.app" ./build-macscp.sh
codesign --verify --deep --strict build/候选.noindex/MacSCP-Next.app
plutil -lint build/候选.noindex/MacSCP-Next.app/Contents/Info.plist
print 'PASS: all test groups and production app build/signature/plist'
