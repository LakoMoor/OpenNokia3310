"""Run a bounded original-firmware diagnostic on the ARM/MAD2 RTL."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
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
a=p.parse_args()
os.chdir(ROOT)
out=Path("build/boot_trace")
out.mkdir(parents=True,exist_ok=True)
prepare(a.firmware,out/"flash.bin")
os.environ["PATH"]=os.pathsep.join([str(Path(a.tools)/"bin"),str(Path(a.tools)/"lib"),os.environ["PATH"]])
vroot=Path(a.tools)/"share/verilator/include"
os.environ["VERILATOR_ROOT"]=str(vroot.parent)
sources=cpu_sources()+["rtl/nokia/keypad_3310.sv","rtl/nokia/sim_chv.sv","rtl/nokia/sim_card.sv", "rtl/nokia/mad2_mmio.sv","rtl/nokia/nor_bus.sv","rtl/nokia/dsp_service.sv","rtl/nokia/nokia_sound.sv", "rtl/nokia/nokia_core.sv"]
sources += ["rtl/nokia/dsp_network.sv","rtl/nokia/virtual_access.sv","rtl/nokia/virtual_dedicated.sv","rtl/nokia/virtual_cell.sv","rtl/nokia/mdi_injector.sv"]
if not a.reuse and not a.cpp_only:
  with (out/"lint.log").open("w") as log:
    subprocess.run([shutil.which("verilator_bin") or "verilator","--cc","-DNOKIA_TRACE","-Wno-fatal",f"-GCLK_HZ={a.clock_hz}",f"-GVIRTUAL_NETWORK={int(a.virtual_network)}",
                    "--top-module","nokia_core","--Mdir",str(out),*sources],check=True,stdout=log,stderr=log)
exe=out/("trace.exe" if os.name=="nt" else "trace")
if not a.reuse:
    build_cpp([*out.glob("*.cpp"),Path("tools/trace_firmware.cpp"),vroot/"verilated.cpp",vroot/"verilated_threads.cpp"],
              [vroot,vroot/"vltstd",out],out,exe)
with (out/"trace.log").open("w") as log:
    subprocess.run([str(exe.resolve()),str((out/"flash.bin").resolve()),str(a.cycles),str(a.hold_power_cycles),*([str(a.keys.resolve())] if a.keys else [])],check=True,stdout=log,stderr=log,timeout=1800)
print((out/"trace.log").read_text())
