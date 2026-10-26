"""Local installer choices only; no ROM contents or credentials."""
import json
import os
from pathlib import Path

def location():
    return Path(os.environ.get('LOCALAPPDATA',str(Path.home())))/'OpenNokia3310'/'installer.json'

def load(path=None):
    path=Path(path) if path is not None else location()
    try:
        value=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(value,dict):return {}
        return {key:value[key] for key in ('loader','image','rom','eeprom','folder')
                if isinstance(value.get(key),str) and len(value[key])<32768}
    except (OSError,ValueError):return {}

def save(values,path=None):
    path=Path(path) if path is not None else location()
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix('.tmp')
    temp.write_text(json.dumps(values,indent=2),encoding='utf-8')
    temp.replace(path)
