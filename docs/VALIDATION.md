# Validation of the initial public source snapshot

- 103 existing test groups passed on the development Apple Silicon Mac, using temporary fixtures, stdio SFTP and hidden AppKit windows.
- The first source-only run exposed a missing Python timestamp fixture. The fixture was added, the timestamp protocol check and all remaining groups passed, and the final production app build/signature/plist checks passed. The complete group list is in `MacSCP/check.sh`.
- `node MacSCP/TerminalResourceTest.js` verifies that the standalone terminal renderer references packaged assets, and that its ready/input/resize bridge and split UTF-8 output preserve data. This uses a JavaScript harness, not a real SSH authentication session.
- Three README screenshots were rendered from production native UI controllers with fictional data and inspected. No user server, credentials or real file listing appears in the screenshots.
- A fresh dependency installation with `npm ci --ignore-scripts` succeeded using the committed lockfile.

These checks do not prove compatibility with every server or macOS version. No third-party machine installation, Apple notarization, or complete Finder drag gesture acceptance is claimed.
