"""Open-source Gowin build. Python 3, OSS CAD Suite (yosys-slang/nextpnr/Apicula)."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import hashlib
import json
import time

ROOT = Path(__file__).resolve().parents[1]


def cpu_sources():
    base = ROOT / "third_party/arm7tdmi-sv"
    return [str(base / line)
            for line in (base / "files.f").read_text().splitlines()
            if line.startswith("rtl/")]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("target", choices=["arm7_probe", "nokia_core", "nokia_io_top", "nokia_top", "nokia_memtest", "nokia_romtest"])
    p.add_argument("--lut4-only",action="store_true",help="Avoid wide-LUT placement clusters on crowded boards")
    p.add_argument("--synth-only", action="store_true")
    p.add_argument("--tools", default=os.environ.get("TOOLS", "E:/tools/oss-cad-suite"))
    args = p.parse_args()
    args.lut4_only = args.lut4_only or args.target=="nokia_top"
    os.chdir(ROOT)
    tools = Path(args.tools)
    os.environ["PATH"] = os.pathsep.join([str(tools / "bin"), str(tools / "lib"), os.environ["PATH"]])
    out = Path("build") / (args.target+("_lut4" if args.lut4_only else ""))
    out.mkdir(parents=True, exist_ok=True)
    # A failed synthesis/placement must never leave an older image under the
    # expected output name. Preserve it separately before starting this build.
    bitstream=out/(args.target+'.fs')
    if bitstream.exists():
        previous=out/(args.target+'-previous-'+str(time.time_ns())+'.fs')
        bitstream.rename(previous)
        print('Previous image preserved:',previous,flush=True)
    receipt=out/'build-result.json'
    receipt.write_text(json.dumps({'target':args.target,'status':'in_progress'},indent=2)+'\n')
    if args.target in ("nokia_memtest","nokia_romtest"):
        sources=["rtl/board/gowin_prims.v","rtl/board/pll_nokia.v",
                 "third_party/open-pocket-gbc/rtl/sdram_ctrl.sv","rtl/nokia/uart_status.sv","rtl/nokia/uart_lcd.sv","rtl/nokia/flash_boot.sv",f"rtl/top/{args.target}.sv"]
    elif args.target == "arm7_probe":
        sources = cpu_sources() + ["rtl/nokia/arm7_probe.sv"]
    elif args.target == "nokia_core":
        sources = cpu_sources() + ["rtl/nokia/keypad_3310.sv", "rtl/nokia/sim_chv.sv", "rtl/nokia/sim_card.sv", "rtl/nokia/mad2_mmio.sv", "rtl/nokia/nor_bus.sv", "rtl/nokia/dsp_service.sv", "rtl/nokia/nokia_sound.sv", "rtl/nokia/nokia_core.sv"]
        sources += ["rtl/nokia/dsp_network.sv","rtl/nokia/virtual_cell.sv","rtl/nokia/mdi_injector.sv"]
    else:
        sources = ["rtl/board/gowin_prims.v", "rtl/board/pll_hdmi480.v"]
        sources += [str(f) for f in sorted(Path("third_party/open-pocket-gbc/rtl").rglob("*.sv"))]
        sources += [str(f) for f in sorted(Path("rtl/nokia").glob("*.sv")) if f.stem != "arm7_probe"]
        if args.target=="nokia_top":
            sources += cpu_sources()+["rtl/board/pll_nokia.v"]
        sources += [f"rtl/top/{args.target}.sv"]
    # Slang receives Yosys tokens literally; -F handles paths with spaces.
    manifest = out / "sources.f"
    manifest.write_text("\n".join('"' + str(s).replace("\\", "/") + '"' for s in sources))
    script = (f"read_slang -I. --top {args.target} --allow-use-before-declare "
              f"--ignore-assertions -f {manifest.as_posix()};\n"
              f"hierarchy -check -top {args.target};\n"
              f"synth_gowin {'-nowidelut ' if args.lut4_only else ''}-top {args.target} -family gw2a -json {out.as_posix()}/synth.json;\n"
              f"tee -o {out.as_posix()}/stat.txt stat;\n"
              "check -assert;\n")
    (out / "synth.ys").write_text(script)
    def run(argv, logfile):
        print(" ".join(map(str, argv)), flush=True)
        with open(out / logfile, "w") as log:
            try:
                subprocess.run(argv, check=True, stdout=log, stderr=subprocess.STDOUT)
            except subprocess.CalledProcessError:
                receipt.write_text(json.dumps({'target':args.target,'status':'failed',
                    'stage':argv[0],'bitstream':None},indent=2)+'\n')
                log.flush()
                print("\n".join((out/logfile).read_text(errors="replace").splitlines()[-35:]), file=sys.stderr)
                print("Full log:", ROOT/out/logfile, file=sys.stderr)
                raise
    run(["yosys", "-Q", "-T", "-m", "slang", "-s", str(out / "synth.ys")], "yosys.log")
    print((out / "stat.txt").read_text(), flush=True)
    if args.synth_only:
        receipt.write_text(json.dumps({'target':args.target,'status':'synthesis_only','bitstream':None},indent=2)+'\n')
        return
    if args.target not in ("nokia_io_top","nokia_top","nokia_memtest","nokia_romtest"):
        p.error("This target has external buses, not board pins; use --synth-only")
    cst="rtl/board/tangnano20k.cst";sdc="rtl/board/clocks.sdc"
    if args.target in ("nokia_memtest","nokia_romtest"):
        cst=str(out/'memory.cst');sdc=str(out/'clocks.sdc')
        Path(cst).write_text('\n'.join(line for line in Path('rtl/board/tangnano20k.cst').read_text().splitlines()
            if any('"'+name in line for name in ('sys_clk','uart_tx','O_sdram','IO_sdram','flash_')+(('uart_rx',) if args.target=='nokia_romtest' else ())))+'\n')
        Path(sdc).write_text('create_clock -name clk_sys -period 59.259 [get_nets {clk_sys}]\n')
    run(["nextpnr-himbaechel", "--json", str(out / "synth.json"),
         "--write", str(out / "pnr.json"), "--device", "GW2AR-LV18QN88C8/I7",
         "--vopt", "family=GW2A-18C", "--vopt", "cst="+cst,
         "--pre-pack", "rtl/board/place.py", "--sdc", sdc,
         "--seed", "1"], "nextpnr.log")
    run(["gowin_pack", "-d", "GW2A-18C", *(["--mspi_as_gpio"] if args.target in ("nokia_top","nokia_romtest") else []), "-o", str(out / (args.target + ".fs")),
         str(out / "pnr.json")], "pack.log")
    print("Bitstream:", (ROOT / out / (args.target + ".fs")), flush=True)
    receipt.write_text(json.dumps({'target':args.target,'status':'built',
        'bitstream':str(bitstream),'sha256':hashlib.sha256(bitstream.read_bytes()).hexdigest(),
        'hardware_qualified':False},indent=2)+'\n')


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
