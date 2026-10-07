#!/usr/bin/env python3
"""Inspect the actual image with Finder browsing and automatic opening disabled."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import json
from ds_store import DSStore

name = json.loads((Path(__file__).parent / 'config.json').read_text())['name']
result = subprocess.check_output([
    '/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
    '-noautoopenro', '-noautoopenrw', '-plist', sys.argv[1]])
entities = plistlib.loads(result)['system-entities']
volume = next(e for e in entities if 'mount-point' in e)
root = Path(volume['mount-point'])
try:
    with DSStore.open(str(root / '.DS_Store'), 'r') as store:
        assert store[name + '.app']['Iloc'] == (180, 215)
        assert store['Applications']['Iloc'] == (540, 215)
        settings = store['.']['icvp']
        assert settings['iconSize'] == 96
        assert settings['backgroundType'] == 2
        assert settings['backgroundImageAlias']
        assert store['.']['pBBk']
        window = store['.']['bwsp']
        assert window['WindowBounds'] == '{{200, 200}, {720, 440}}'
        assert not window['ShowToolbar'] and not window['ShowSidebar']
    subprocess.run(['swift', str(Path(__file__).parent / 'check-artwork.swift'), str(root / '.background.tiff')], check=True)
    assert os.readlink(root / 'Applications') == '/Applications'
    info = plistlib.loads((root / (name + '.app/Contents/Info.plist')).read_bytes())
    assert (root / (name + '.app/Contents/MacOS') / info['CFBundleExecutable']).is_file()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(root / (name + '.app'))], check=True)
    print('Actual DMG layout, background, icons, Applications link and app signature verified')
finally:
    detached = subprocess.run(['/usr/bin/hdiutil', 'detach', volume['dev-entry']],
                              stdout=subprocess.DEVNULL)
    if detached.returncode:
        subprocess.run(['/usr/bin/hdiutil', 'detach', '-force', volume['dev-entry']],
                       check=True, stdout=subprocess.DEVNULL)
