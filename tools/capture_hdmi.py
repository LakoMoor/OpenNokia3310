"""Capture a real Tang HDMI frame through a Windows DirectShow USB capture card."""
import argparse
from pathlib import Path
import shutil
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--device',default='USB3.0 UHD')
p.add_argument('--ffmpeg',type=Path)
p.add_argument('--output',type=Path,default=Path('build/hdmi-capture.png'))
a=p.parse_args()
ffmpeg=a.ffmpeg or shutil.which('ffmpeg')
if not ffmpeg:
    matches=sorted(Path('E:/tools/ffmpeg').glob('*/bin/ffmpeg.exe'))
    if matches: ffmpeg=matches[-1]
if not ffmpeg:
    p.error('Specify --ffmpeg or add ffmpeg to PATH')
a.output.parent.mkdir(parents=True,exist_ok=True)
subprocess.run([str(ffmpeg),'-hide_banner','-loglevel','warning','-rtbufsize','128M','-f','dshow',
    '-i','video='+a.device,'-vf',r'select=gte(n\,3)','-frames:v','1','-update','1',
    '-y',str(a.output)],check=True,timeout=20)
print(a.output.resolve())
