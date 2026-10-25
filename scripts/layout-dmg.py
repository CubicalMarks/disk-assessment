"""Write the installer's Finder layout without Apple Events or UI automation."""
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
background = Alias.for_file(str(mount / '.background' / 'installer.png')).to_bytes()
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        # Leave room for Finder's title/path/status bars on newer macOS releases.
        'WindowBounds': '{{160, 120}, {680, 528}}',
        'ShowStatusBar': False,
        'ShowToolbar': False,
        'ShowSidebar': False,
        'ShowPathbar': False,
        'ShowTabView': False,
        'ContainerShowSidebar': False,
        'PreviewPaneVisibility': False,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1,
        'backgroundType': 2,
        'backgroundImageAlias': background,
        'backgroundColorRed': 1.0,
        'backgroundColorGreen': 1.0,
        'backgroundColorBlue': 1.0,
        'gridOffsetX': 0.0,
        'gridOffsetY': 0.0,
        'gridSpacing': 100.0,
        'arrangeBy': 'none',
        'showIconPreview': True,
        'showItemInfo': False,
        'labelOnBottom': True,
        'textSize': 14.0,
        'iconSize': 112.0,
    }
    store['Disk Assessment.app']['Iloc'] = (180, 220)
    store['Applications']['Iloc'] = (500, 220)
