"""Build a freedesktop icon theme from pinned Google Material Symbols SVGs."""
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

source = Path(__file__).parent
output = Path(sys.argv[1]) / 'share/icons/MaterialDolphin'
output.mkdir(parents=True, exist_ok=True)
mapping = json.loads((source / 'mapping.json').read_text())
ET.register_namespace('', 'http://www.w3.org/2000/svg')
directories = []
count = 0
for context, icons in mapping.items():
    for size in ('24x24', 'scalable'):
        directory = f'{size}/{context}'
        directories.append((directory, context, size))
        target = output / directory
        target.mkdir(parents=True, exist_ok=True)
        for symbol, names in icons.items():
            filled = context == 'places' and size == 'scalable'
            suffix = '_fill1_24px.svg' if filled else '_24px.svg'
            svg = ET.parse(source / 'sources' / (symbol + suffix)).getroot()
            color = '#6750a4' if filled else '#49454f'
            svg.set('fill', color)
            data = ET.tostring(svg, encoding='unicode')
            for name in names:
                (target / (name + '.svg')).write_text(data)
                if size == '24x24' and not name.endswith('-symbolic'):
                    (target / (name + '-symbolic.svg')).write_text(data)
                count += 1

index = '[Icon Theme]\nName=Material Dolphin\nComment=Google Material Symbols Rounded for Dolphin\nInherits=Papirus-Light,Papirus,hicolor\nDirectories=' + ','.join(d[0] for d in directories) + '\n'
for directory, context, size in directories:
    index += f'\n[{directory}]\nContext={context.title()}\n'
    index += 'Size=24\nType=Threshold\nThreshold=8\n' if size == '24x24' else 'Size=64\nType=Scalable\nMinSize=33\nMaxSize=512\n'
(output / 'index.theme').write_text(index)
(output / 'LICENSE').write_bytes((source / 'LICENSE').read_bytes())
print(f'Built {count} icon mappings plus symbolic aliases')
