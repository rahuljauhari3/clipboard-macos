# ClipboardMate

macOS menu bar clipboard manager (SwiftUI, macOS 14+, SQLite.swift, KeyboardShortcuts).

Features
- Monitors clipboard for text and images
- Stores last 100 items in SQLite (persisted under Application Support)
- Exclude copying from specific apps (Keychain Access by default)
- Search, copy-back, delete item, Clear All
- Menu bar popover UI; global shortcut (default Cmd+Shift+C) configurable in Preferences

Build & Run
1) Open this package in Xcode: File -> Open -> select the folder.
2) Select the ClipboardMateApp scheme and run.
3) Grant accessibility permission if prompted (for global shortcut) and Screen Recording if you later add image OCR.

Notes
- Database path: ~/Library/Application Support/ClipboardMate/clipboard.sqlite
- Default excluded apps: com.apple.keychainaccess. Add others in Preferences (e.g., 1Password, password managers).
- The app runs as an accessory (menu bar only) app.

## Build .app (CLI)

You can produce a standalone ClipboardMate.app bundle directly from Swift Package Manager.

Requirements
- macOS 14+
- Xcode command-line tools installed

Steps
1) Build the release binary
```bash path=null start=null
swift build -c release
```

2) Create the .app bundle structure and Info.plist
```bash path=null start=null
APP_ROOT="$PWD/dist/ClipboardMate.app"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"

cat > "$APP_ROOT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>ClipboardMate</string>
	<key>CFBundleDisplayName</key>
	<string>ClipboardMate</string>
	<key>CFBundleIdentifier</key>
	<string>com.lark.ClipboardMate</string>
	<key>CFBundleExecutable</key>
	<string>ClipboardMate</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST
```

3) Copy the compiled binary into the bundle
```bash path=null start=null
BIN_PATH=$(swift build -c release --show-bin-path)/clipboardmate
install -m 755 "$BIN_PATH" "$APP_ROOT/Contents/MacOS/ClipboardMate"
```

4) (Optional) Ad-hoc code sign to avoid Gatekeeper warnings locally
```bash path=null start=null
codesign --force --deep --sign - "$APP_ROOT"
```

5) Run the app
```bash path=null start=null
open "$APP_ROOT"
```

Notes
- The app is a menu bar app (no Dock icon). Press Command+Q to quit.
- Default global toggle is Command+Shift+C (configurable in Preferences).
- To distribute outside your machine, sign with a Developer ID certificate and notarize.

