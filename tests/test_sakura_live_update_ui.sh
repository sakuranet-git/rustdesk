#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT/flutter/lib/desktop/pages/desktop_home_page.dart"

/usr/bin/grep -Fq '(isWindows || isMacOS) && bind.isCustomClient()' "$PAGE"
/usr/bin/grep -Fq 'SAKURA-Remote-mac-version.json' "$PAGE"
/usr/bin/grep -Fq '/Library/Preferences/jp.sakuranet.sakuraremote' "$PAGE"
/usr/bin/grep -Fq 'jp.sakuranet.sakuraremote.pkg' "$PAGE"
/usr/bin/grep -Fq '/Library/Application Support/SAKURA-Remote/updater.sh' "$PAGE"
/usr/bin/grep -Fq "Process.run('/usr/bin/osascript'" "$PAGE"
/usr/bin/grep -Fq 'if (result.exitCode != 0)' "$PAGE"
/usr/bin/grep -Fq "throw Exception('installed ProductVersion unavailable')" "$PAGE"
/usr/bin/grep -Fq "manifest['platform'] != 'macos'" "$PAGE"
/usr/bin/grep -Fq "manifest['arch'] != 'arm64'" "$PAGE"
/usr/bin/grep -Fq 'OutlinedButton.icon(' "$PAGE"
/usr/bin/grep -Fq 'minimumSize: const Size(176, 36)' "$PAGE"
/usr/bin/grep -Fq 'side: BorderSide(color: updateColor)' "$PAGE"
/usr/bin/grep -Fq 'Brightness.dark' "$PAGE"

echo "SAKURA-Remote LiveUpdate UI checks passed"
