"""Fixed Tang Nano 20K flash operations; no shell commands or arbitrary offsets."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time

FLASH_SIZE=8*1024*1024

def find_loader():
    home=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).parent
    candidates=[home/'programmer/openFPGALoader.exe',shutil.which('openFPGALoader'),
                'E:/tools/oss-cad-suite/bin/openFPGALoader.exe']
    return next((str(p) for p in candidates if p and Path(p).is_file()),'')

def validate_fpga(path):
    path=Path(path)
    if path.suffix.lower()!='.fs':raise ValueError('Choose a Gowin .fs bitstream for Tang Nano 20K.')
    data=path.read_bytes()
    if not 1000<len(data)<16*1024*1024:raise ValueError('Unexpected bitstream size.')
    lines=data.splitlines()
    if not any(line.strip().startswith(b'00111011') for line in lines[:100]):
        raise ValueError('Not a recognized ASCII Gowin FS bitstream.')
    bits=sum(len(line.strip()) for line in lines if line.strip() and set(line.strip())<=set(b'01'))
    if bits//8>0x200000:raise ValueError('FPGA configuration overlaps the Nokia ROM region.')
    return path

def run(loader,args,log,timeout=None):
    # USB driver calls can hang without producing another output line.
    # Bound the child lifetime independently of the stdout reader.
    if timeout is None:timeout=30 if '--detect' in args else 600
    env=os.environ.copy()
    base=Path(loader).parent
    env['PATH']=str(base)+os.pathsep+str(base.parent/'lib')+os.pathsep+env.get('PATH','')
    log('openFPGALoader '+' '.join(map(str,args)))
    with subprocess.Popen([str(loader),'-b','tangnano20k',*map(str,args)],stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT,text=True,errors='replace',env=env,
                          creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)) as proc:
        expired=threading.Event()
        def stop_stalled():
            if proc.poll() is None:
                expired.set()
                try:proc.kill()
                except ProcessLookupError:pass
        watchdog=threading.Timer(timeout,stop_stalled)
        watchdog.daemon=True
        watchdog.start()
        try:
            for line in proc.stdout:
                if line.strip():log(line.rstrip())
            result=proc.wait()
        finally:
            watchdog.cancel()
        if expired.is_set():
            raise RuntimeError('Programmer timed out. USB may have disconnected. No later installation steps were run; flash contents may be incomplete. Reconnect Tang and check the backup before retrying.')
        if result:raise RuntimeError('Programmer failed. See the log; do not assume the write succeeded.')

def backup(loader,folder,log):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    target=folder/f'tang-flash-{time.strftime("%Y%m%d-%H%M%S")}-{time.time_ns()%1000000:06d}.bin'
    run(loader,['--dump-flash','-o','0','--file-size',str(FLASH_SIZE),target],log)
    if not target.exists() or target.stat().st_size!=FLASH_SIZE:
        raise RuntimeError('Incomplete backup; flash writing has been stopped.')
    digest=hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix('.sha256').write_text(digest+'  '+target.name+'\n')
    log('Full flash backup saved: '+str(target));return target

def program(loader,action,image,eeprom,folder,log,rom=''):
    if not Path(loader).is_file():raise ValueError('Select openFPGALoader.exe first.')
    if action=='Detect board':run(loader,['--detect'],log);return
    if action=='Back up full flash':backup(loader,folder,log);return
    if action=='Install complete Nokia':
        from prepare_firmware import prepare
        image=validate_fpga(image)
        if not rom:raise ValueError('Choose your Nokia ROM before installing the complete system.')
        prepared=Path(folder)/('prepared-'+str(time.time_ns())+'.bin')
        manifest=prepare(Path(rom),prepared,Path(eeprom) if eeprom else None)
        log('Validated ROM SHA256: '+manifest['sha256'])
        backup(loader,folder,log)
        # ROM first: if preparation/backup/ROM programming fails, do not replace FPGA.
        run(loader,['-f','--verify','-o','0x200000','--file-type','bin',prepared],log)
        run(loader,['-f','--verify',image],log)
        run(loader,[image],log)
        log('Flash writes verified and FPGA loaded into SRAM. Reconnect the remote to check phone boot; power-cycle separately to check flash boot.');return
    if action in ('Test FPGA in SRAM','Install FPGA in flash'):
        image=validate_fpga(image)
        if action=='Test FPGA in SRAM':run(loader,[image],log);return
        backup(loader,folder,log)
        run(loader,['-f','--verify',image],log);return
    if action=='Install Nokia ROM':
        from prepare_firmware import prepare
        # Validate and prepare before touching the board; never overwrite the source.
        prepared=Path(folder)/('prepared-'+str(time.time_ns())+'.bin')
        prepare(Path(image),prepared,Path(eeprom) if eeprom else None)
        backup(loader,folder,log)
        run(loader,['-f','--verify','-o','0x200000','--file-type','bin',prepared],log)
        log('ROM verified. Load a Nokia FPGA .fs into SRAM, or power-cycle if already installed.');return
    raise ValueError('Unknown operation.')
