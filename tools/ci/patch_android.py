"""Same Android fixes as Patch-Android in setup-and-build.ps1, for the GitHub build.

Usage: python3 patch_android.py <appDir> <label> <camera 0|1> <location 0|1>
"""
import pathlib
import re
import sys

app, label, camera, location = sys.argv[1], sys.argv[2], sys.argv[3] == '1', sys.argv[4] == '1'
root = pathlib.Path(app)

manifest = root / 'android/app/src/main/AndroidManifest.xml'
m = manifest.read_text(encoding='utf-8-sig')
perms = ['android.permission.INTERNET']
if camera:
    perms.append('android.permission.CAMERA')
if location:
    perms += ['android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION']
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
if add:
    m = re.sub(r'(<manifest[^>]*>)', lambda g: g.group(1) + '\n' + add, m, count=1)
m = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', m)
if 'usesCleartextTraffic' not in m:
    # Test builds talk to the PC's server over http on the local Wi-Fi.
    m = m.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
manifest.write_text(m, encoding='utf-8')

for name in ('build.gradle.kts', 'build.gradle'):
    g = root / 'android/app' / name
    if g.exists():
        c = g.read_text(encoding='utf-8-sig')
        c = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', c)
        c = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', c)
        g.write_text(c, encoding='utf-8')
print(f'patched {app}: {", ".join(perms)}')
