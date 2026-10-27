"""Run a bounded original-firmware diagnostic on the ARM/MAD2 RTL."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import hashlib
import json
import uuid
from datetime import datetime,timezone
from build import ROOT, cpu_sources
from prepare_firmware import prepare
from sim_build import build_cpp

p=argparse.ArgumentParser(description=__doc__)
p.add_argument("firmware",type=Path)
p.add_argument("--tools",default=os.environ.get("TOOLS","E:/tools/oss-cad-suite"))
p.add_argument("--cycles",type=int,default=10000000)
p.add_argument("--clock-hz",type=int,default=16875000,help="Device-model clock; match the Tang system PLL")
p.add_argument("--virtual-network",action="store_true",help="Experimental DSP SCH/SI3/SI2/SI4 search responses; not full GSM")
p.add_argument("--hold-power-cycles",type=int,default=27000000)
p.add_argument("--keys",type=Path,help="Live text stimulus: absolute cycle, hexadecimal Nokia key mask; sorted rows")
p.add_argument("--reuse",action="store_true",help="Reuse an already compiled diagnostic executable")
p.add_argument("--cpp-only",action="store_true",help="Recompile the harness without re-elaborating RTL")
p.add_argument("--output-dir",type=Path,help="New empty run directory; default: unique build/trace-runs directory")
a=p.parse_args()
os.chdir(ROOT)
out=Path("build/boot_trace")
out.mkdir(parents=True,exist_ok=True)
run_dir=a.output_dir or Path('build/trace-runs')/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8])
if run_dir.exists() and any(run_dir.iterdir()):p.error('Run directory must be empty; old evidence must not mix with a new run')
run_dir.mkdir(parents=True,exist_ok=True)
prepare(a.firmware,run_dir/"flash.bin")
os.environ["PATH"]=os.pathsep.join([str(Path(a.tools)/"bin"),str(Path(a.tools)/"lib"),os.environ["PATH"]])
vroot=Path(a.tools)/"share/verilator/include"
os.environ["VERILATOR_ROOT"]=str(vroot.parent)
sources=cpu_sources()+["rtl/nokia/keypad_3310.sv","rtl/nokia/sim_chv.sv","rtl/nokia/sim_card.sv", "rtl/nokia/mad2_mmio.sv","rtl/nokia/nor_bus.sv","rtl/nokia/dsp_service.sv","rtl/nokia/nokia_sound.sv", "rtl/nokia/nokia_core.sv"]
sources += ["rtl/nokia/dsp_network.sv","rtl/nokia/lapdm_ua.sv","rtl/nokia/lapdm_rx.sv","rtl/nokia/l3_header.sv","rtl/nokia/mm_registration.sv","rtl/nokia/virtual_access.sv","rtl/nokia/virtual_dedicated.sv","rtl/nokia/virtual_cell.sv","rtl/nokia/mdi_injector.sv"]
fingerprint=hashlib.sha256()
for source in sorted({Path(x) for x in sources} | set(Path('rtl/nokia').glob('*.svh')) | set(Path('rtl/nokia').glob('*.hex')) | set(Path('third_party/arm7tdmi-sv').rglob('*.svh'))):
    fingerprint.update(str(source).encode());fingerprint.update(source.read_bytes())
compiled={'clock_hz':a.clock_hz,'virtual_network':a.virtual_network,'rtl_sha256':fingerprint.hexdigest()}
harness_hash=hashlib.sha256(Path('tools/trace_firmware.cpp').read_bytes()).hexdigest()
compile_record=out/'compile-options.json'
if a.reuse or a.cpp_only:
    previous=json.loads(compile_record.read_text()) if compile_record.exists() else {}
    if any(previous.get(key)!=value for key,value in compiled.items()):
        p.error('Compiled RTL does not match requested options/source; rebuild without --reuse/--cpp-only')
    if a.reuse and previous.get('harness_sha256')!=harness_hash:
        p.error('Compiled harness changed; rebuild without --reuse')
if not a.reuse and not a.cpp_only:
  with (out/"lint.log").open("w") as log:
    subprocess.run([shutil.which("verilator_bin") or "verilator","--cc","-DNOKIA_TRACE","-Wno-fatal",f"-GCLK_HZ={a.clock_hz}",f"-GVIRTUAL_NETWORK={int(a.virtual_network)}",
                    "--top-module","nokia_core","--Mdir",str(out),*sources],check=True,stdout=log,stderr=log)
exe=out/("trace.exe" if os.name=="nt" else "trace")
if not a.reuse:
    build_cpp([*out.glob("*.cpp"),Path("tools/trace_firmware.cpp"),vroot/"verilated.cpp",vroot/"verilated_threads.cpp"],
              [vroot,vroot/"vltstd",out],out,exe)
    compile_record.write_text(json.dumps({**compiled,'harness_sha256':harness_hash},indent=2)+'\n')
manifest={**compiled,'cycles':a.cycles,'hold_power_cycles':a.hold_power_cycles,
          'rom_sha256':hashlib.sha256((run_dir/'flash.bin').read_bytes()).hexdigest(),
          'memory_wait':os.environ.get('NOKIA_MEM_WAIT','0'),'status':'running',
          'harness_sha256':harness_hash}
if a.keys:
    manifest['keys_path']=str(a.keys.resolve())
    manifest['initial_keys_sha256']=hashlib.sha256(a.keys.read_bytes()).hexdigest()
record=run_dir/'run.json'
record.write_text(json.dumps(manifest,indent=2)+'\n')
env=os.environ.copy();env['NOKIA_TRACE_OUTPUT']=str(run_dir.resolve())
print('Run directory:',run_dir.resolve(),flush=True)
try:
    with (run_dir/'trace.log').open('w') as log:
        subprocess.run([str(exe.resolve()),str((run_dir/'flash.bin').resolve()),str(a.cycles),str(a.hold_power_cycles),*([str(a.keys.resolve())] if a.keys else [])],check=True,stdout=log,stderr=log,timeout=1800,env=env)
except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as error:
    manifest.update(status='failed',error=str(error));raise
else:manifest['status']='completed'
finally:
    if a.keys:
        final_keys=a.keys.read_bytes()
        manifest['final_keys_sha256']=hashlib.sha256(final_keys).hexdigest()
        (run_dir/'final-keys.txt').write_bytes(final_keys)
    record.write_text(json.dumps(manifest,indent=2)+'\n')
print((run_dir/'trace.log').read_text())
