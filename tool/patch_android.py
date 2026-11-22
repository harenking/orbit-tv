"""Anpassar den genererade AndroidManifest.xml för Android TV (körs i bygget)."""
import re
from pathlib import Path

p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text(encoding='utf-8')

# Behörigheter och TV-funktioner före <application
extra = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n'
    '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
    '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
)
if 'android.permission.INTERNET' not in s.split('<application')[0]:
    s = s.replace('<application', extra + '    <application', 1)

# Tillåt http:// (många IPTV-servrar saknar https)
if 'usesCleartextTraffic' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)

# Visa appen på Android TV:s startskärm
if 'LEANBACK_LAUNCHER' not in s:
    s = re.sub(
        r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
        r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        s,
        count=1,
    )

if 'android:banner' not in s:
    s = s.replace('<application', '<application android:banner="@drawable/banner"', 1)

s = s.replace('android:label="orbit_tv"', 'android:label="Orbit IPTV"')

p.write_text(s, encoding='utf-8')
print('AndroidManifest.xml patchad')
