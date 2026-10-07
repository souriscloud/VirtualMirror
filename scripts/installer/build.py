#!/usr/bin/env python3
"""Write the common Finder layout without asking Finder to arrange a window."""
import json
import plistlib
import subprocess
import sys
from pathlib import Path
from dmgbuild import core

app, background, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
config = json.loads((Path(__file__).parent / 'config.json').read_text())
name = config['name']
if app.name != name + '.app':
    raise SystemExit('App filename must match installer configuration')
if not (app / 'Contents/Info.plist').is_file():
    raise SystemExit('Not an application bundle')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
original_hdiutil = core.hdiutil

def headless_hdiutil(command, *args, **kwargs):
    if command == 'attach':
        args = ('-noautoopen', '-noautoopenro', '-noautoopenrw', *args)
        if '-nobrowse' not in args:
            raise RuntimeError('Installer mounts must disable browsing')
    return original_hdiutil(command, *args, **kwargs)

core.hdiutil = headless_hdiutil
core.build_dmg(str(output), name, settings={
    'format': 'UDZO', 'filesystem': 'HFS+',
    'files': [str(app)], 'symlinks': {'Applications': '/Applications'},
    'background': str(background),
    'window_rect': ((200, 200), (720, 440)),
    'default_view': 'icon-view', 'arrange_by': None,
    'icon_size': 96, 'text_size': 13,
    'icon_locations': {name + '.app': (180, 215), 'Applications': (540, 215)},
    'show_status_bar': False, 'show_toolbar': False, 'show_sidebar': False,
    'show_tab_view': False, 'show_pathbar': False,
    'include_icon_view_settings': True, 'include_list_view_settings': False,
})
print(f'Styled {name} DMG prepared without Finder')
