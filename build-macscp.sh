#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="${MACSCP_OUTPUT:-$PWD/build/候选.noindex/MacSCP-Next.app}"
BUILD_TARGET="$(uname -m)-apple-macos13.0"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache
cp Resources/ssh-askpass.sh "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/ssh-askpass.sh"
cp Resources/terminal.html node_modules/@xterm/xterm/lib/xterm.js node_modules/@xterm/xterm/css/xterm.css node_modules/@xterm/addon-fit/lib/addon-fit.js "$APP/Contents/Resources/"
cp node_modules/@xterm/xterm/LICENSE "$APP/Contents/Resources/xterm-LICENSE"
cp node_modules/@xterm/addon-fit/LICENSE "$APP/Contents/Resources/xterm-addon-fit-LICENSE"
clang -target "$BUILD_TARGET" -c Sources/PTY.c -o build/PTY.o
clang -target "$BUILD_TARGET" -c MacSCP/FTPCurl.c -o build/FTPCurl.o
cp "${MACSCP_LAUNCHER:-MacSCP/Launcher.swift}" build/main.swift
swiftc -target "$BUILD_TARGET" -module-cache-path "$PWD/build/module-cache" MacSCP/Terminal.swift MacSCP/Askpass.swift MacSCP/SSHCredentialChannel.swift MacSCP/SSHConnection.swift MacSCP/SSHAuthenticationLog.swift MacSCP/TerminalWindow.swift MacSCP/AppMenu.swift MacSCP/CommanderAppearance.swift MacSCP/CommanderChrome.swift MacSCP/TaskDetailsWindow.swift MacSCP/Pane.swift MacSCP/Sites.swift MacSCP/PasswordVault.swift MacSCP/SiteImport.swift MacSCP/SiteImportWindow.swift MacSCP/SSHOptions.swift MacSCP/SSHOptionsView.swift MacSCP/SFTP.swift MacSCP/RemoteFileClient.swift MacSCP/LocalReadClient.swift MacSCP/FileClipboard.swift MacSCP/App+FileClipboard.swift MacSCP/FTPTransport.swift MacSCP/FTPListing.swift MacSCP/FTPClient.swift MacSCP/FTPLogin.swift MacSCP/ConnectionForm.swift MacSCP/FTPAdvancedOptionsView.swift MacSCP/FTPUploadSource.swift MacSCP/FTPDownloadTarget.swift MacSCP/Resume.swift MacSCP/FTPPublication.swift MacSCP/QueueJournal.swift MacSCP/TransferPolicy.swift MacSCP/TransferConflict.swift MacSCP/TransferSettingsView.swift MacSCP/TransferOptionsWindow.swift MacSCP/App+TransferOptions.swift MacSCP/TransferPresetRule.swift MacSCP/TransferPresets.swift MacSCP/TransferPresetArchive.swift MacSCP/WinSCPPresetINI.swift MacSCP/PresetImportWindow.swift MacSCP/TransferPresetsWindow.swift MacSCP/TransferPresetRuleWindow.swift MacSCP/App+TransferPresets.swift MacSCP/TextTransfer.swift MacSCP/Transfer.swift MacSCP/TransferScheduler.swift MacSCP/RelayTransfer.swift MacSCP/RelayJournal.swift MacSCP/RecoverySelection.swift MacSCP/RecoveryWindow.swift MacSCP/QueueToolbar.swift MacSCP/FilePromise.swift MacSCP/Drag.swift MacSCP/Sync.swift MacSCP/SyncPreview.swift MacSCP/SyncTextComparison.swift MacSCP/SyncContents.swift MacSCP/SyncPartialDeletion.swift MacSCP/SyncContentsWindow.swift MacSCP/SyncTimestamp.swift MacSCP/ContinuousSync.swift MacSCP/ContinuousWindow.swift MacSCP/SyncWindow.swift MacSCP/Checksum.swift MacSCP/DirectorySize.swift MacSCP/FilePropertiesWindow.swift MacSCP/ChecksumWindow.swift MacSCP/RemoteOperations.swift MacSCP/LocalTrash.swift MacSCP/LocalTrashWindow.swift MacSCP/RemoteRelocation.swift MacSCP/Breadcrumb.swift MacSCP/DirectoryTree.swift MacSCP/Navigation.swift MacSCP/LinkedBrowsing.swift MacSCP/Listing.swift MacSCP/FileSelection.swift MacSCP/TextDocument.swift MacSCP/Editor.swift MacSCP/Search.swift MacSCP/SearchWindow.swift MacSCP/SyncRecompare.swift MacSCP/App+SyncRetry.swift MacSCP/App.swift build/main.swift build/PTY.o build/FTPCurl.o -lcurl -o "$APP/Contents/MacOS/MacSCP" -framework Cocoa -framework WebKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>MacSCP</string><key>CFBundleIdentifier</key><string>local.macscp.app</string><key>CFBundleName</key><string>MacSCP</string><key>CFBundleVersion</key><string>40</string><key>CFBundleShortVersionString</key><string>0.1.39</string><key>CFBundleIconFile</key><string>AppIcon</string><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>13.0</string></dict></plist>
PLIST
if [[ -n "${MACSCP_BUNDLE_NAME:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleName $MACSCP_BUNDLE_NAME" "$APP/Contents/Info.plist"; fi
if [[ -n "${MACSCP_BUNDLE_ID:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $MACSCP_BUNDLE_ID" "$APP/Contents/Info.plist"; fi
if [[ -f MacSCP/AppIcon.icns ]]; then cp MacSCP/AppIcon.icns "$APP/Contents/Resources/"; fi
AUTH_APP="$APP/Contents/Helpers/MacSCP-Authentication.app"
mkdir -p "$AUTH_APP/Contents/MacOS" "$AUTH_APP/Contents/Resources" build/authentication-entry
cp MacSCP/AuthenticationLauncher.swift build/authentication-entry/main.swift
swiftc -target "$BUILD_TARGET" -module-cache-path "$PWD/build/module-cache" MacSCP/Askpass.swift MacSCP/SSHCredentialChannel.swift build/authentication-entry/main.swift -o "$AUTH_APP/Contents/MacOS/MacSCP-Authentication" -framework Cocoa
cat > "$AUTH_APP/Contents/Info.plist" <<'AUTHPLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>MacSCP-Authentication</string><key>CFBundleIdentifier</key><string>local.macscp.app.authentication</string><key>CFBundleName</key><string>MacSCP-Authentication</string><key>CFBundleVersion</key><string>40</string><key>CFBundleShortVersionString</key><string>0.1.39</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>CFBundleIconFile</key><string>AppIcon</string><key>LSMinimumSystemVersion</key><string>13.0</string></dict></plist>
AUTHPLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${MACSCP_BUNDLE_ID:-local.macscp.app}.authentication" "$AUTH_APP/Contents/Info.plist"
if [[ -f MacSCP/AppIcon.icns ]]; then cp MacSCP/AppIcon.icns "$AUTH_APP/Contents/Resources/"; fi
codesign --force --sign - "$AUTH_APP"
codesign --force --deep --sign - "$APP"
