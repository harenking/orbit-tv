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

# Egen skärm för Androids videospelare (ExoPlayer)
if 'PlayerActivity' not in s:
    s = s.replace('</application>', '''        <activity
            android:name=".PlayerActivity"
            android:exported="false"
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen"
            android:screenOrientation="landscape"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|screenLayout|uiMode|navigation|density"/>
    </application>''', 1)

p.write_text(s, encoding='utf-8')
print('AndroidManifest.xml patchad')

# Egen MainActivity som kan läsa ut varför appen senast stängdes
ma = Path('android/app/src/main/kotlin/se/orbit/orbit_tv/MainActivity.kt')
ma.parent.mkdir(parents=True, exist_ok=True)
ma.write_text(Path('tool/MainActivity.kt').read_text(encoding='utf-8'), encoding='utf-8')
print('MainActivity.kt ersatt')

pa = ma.parent / 'PlayerActivity.kt'
pa.write_text(Path('tool/PlayerActivity.kt').read_text(encoding='utf-8'), encoding='utf-8')
print('PlayerActivity.kt tillagd')

# Media3 (ExoPlayer) i bygget
M3 = '1.5.1'
kts = Path('android/app/build.gradle.kts')
gro = Path('android/app/build.gradle')
if kts.exists():
    t = kts.read_text(encoding='utf-8')
    t += f"""

dependencies {{
    implementation("androidx.media3:media3-exoplayer:{M3}")
    implementation("androidx.media3:media3-exoplayer-hls:{M3}")
    implementation("androidx.media3:media3-ui:{M3}")
}}

android {{
    lint {{
        checkReleaseBuilds = false
        abortOnError = false
    }}
}}
"""
    kts.write_text(t, encoding='utf-8')
    print('Media3 tillagt i build.gradle.kts')
elif gro.exists():
    t = gro.read_text(encoding='utf-8')
    t += f"""

dependencies {{
    implementation 'androidx.media3:media3-exoplayer:{M3}'
    implementation 'androidx.media3:media3-exoplayer-hls:{M3}'
    implementation 'androidx.media3:media3-ui:{M3}'
}}

android {{
    lint {{
        checkReleaseBuilds false
        abortOnError false
    }}
}}
"""
    gro.write_text(t, encoding='utf-8')
    print('Media3 tillagt i build.gradle')
else:
    raise SystemExit('Hittade ingen build.gradle')
