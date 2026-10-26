"""Build portable Windows studio and bundle the programmer's non-system DLLs."""
import os
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import pefile

ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fpga',type=Path,required=True,help='Explicit qualified FPGA image; never select a stale build implicitly')
parser.add_argument('--fpga-sha256',required=True,help='Expected SHA256 from hardware qualification')
args=parser.parse_args()
sys.path.insert(0,str(ROOT/'apps/desktop'))
from flasher import validate_fpga
image=validate_fpga(args.fpga).resolve()
digest=hashlib.sha256(image.read_bytes()).hexdigest()
if digest!=args.fpga_sha256.lower():parser.error('FPGA SHA256 does not match the qualified image')
subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--windowed','--onedir',
    '--name','OpenNokia3310','--distpath','build/desktop-dist','--workpath','build/desktop-work',
    '--specpath','build','--paths','tools','--paths','apps/desktop',
    '--hidden-import','prepare_firmware','--collect-all','sounddevice',
    '--collect-all','_sounddevice_data','apps/desktop/opennokia.py'],check=True)
dest=ROOT/'build/desktop-dist/OpenNokia3310'
programmer=dest/'programmer';programmer.mkdir(exist_ok=True)
source=Path(os.environ.get('OSS_CAD_SUITE','E:/tools/oss-cad-suite'))
loader=source/'bin/openFPGALoader.exe'
search=[source/'bin',source/'lib']
pending=[loader];seen=set()
while pending:
    path=pending.pop()
    if path.name.lower() in seen:continue
    seen.add(path.name.lower());shutil.copy2(path,programmer/path.name)
    pe=pefile.PE(str(path))
    for entry in getattr(pe,'DIRECTORY_ENTRY_IMPORT',[]):
        name=entry.dll.decode()
        dep=next((base/name for base in search if (base/name).is_file()),None)
        if dep:pending.append(dep)
    pe.close()
shutil.copy2(ROOT/'LICENSE',dest/'LICENSE.txt')
shutil.copytree(ROOT/'apps/desktop/licenses',dest/'licenses',dirs_exist_ok=True)
(dest/'images').mkdir(exist_ok=True);shutil.copy2(image,dest/'images/nokia_top.fs')
(dest/'images/manifest.json').write_text(json.dumps({
    'file':'nokia_top.fs','sha256':digest,
    'packaging_source_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'qualification':'Original v6.39 Phonebook on Tang; one USB power-cycle boot passed.',
    'limits':['Pre-CHV FPGA build: new PIN/PUK model is not included.',
              'Virtual network disabled; virtual registration/calls/SMS incomplete.',
              'USB stability and repeated cold boot remain under investigation.']
},indent=2)+'\n')
(dest/'README.txt').write_text('Open Nokia 3310 Windows Studio\n\nRun OpenNokia3310.exe. No Python installation required.\nRemote: connect FTDI UART B. Firmware: select operation and image.\nInstall operations require a full 8 MiB backup before writing. ROM offset is fixed at 0x200000.\nThe bundled FPGA image is an experimental preview. Proprietary Nokia ROM is not included.\n\nDriver: Windows needs the Tang FTDI driver for JTAG/UART.\nOriginal Nokia boot remains experimental; see GitHub verification status.\n\nProject/source: https://github.com/LakoMoor/OpenNokia3310\nBundled openFPGALoader is GPL-2.0-or-later; source: https://github.com/trabucayre/openFPGALoader\nProgrammer binaries/dependencies: https://github.com/YosysHQ/oss-cad-suite-build\nPython/Tk, PyInstaller and pyserial notices are included with their runtime packages.\n')
archive=ROOT/'build/OpenNokia3310-Windows-preview.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for path in dest.rglob('*'):
        if path.is_file():z.write(path,path.relative_to(dest.parent))
print(archive)
