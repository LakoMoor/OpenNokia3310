"""Run fail-hard local RTL tests with Verilator and a C++20 compiler."""
import argparse
import os
from pathlib import Path
import subprocess
import shutil
from build import cpu_sources
from sim_build import build_cpp

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tools", default=os.environ.get("TOOLS", "E:/tools/oss-cad-suite"))
    p.add_argument("--case", action="append", help="Run only the named case(s)")
    a = p.parse_args()
    os.chdir(ROOT)
    os.environ["PATH"] = os.pathsep.join([str(Path(a.tools)/"bin"), str(Path(a.tools)/"lib"), os.environ["PATH"]])
    Path("build/tests").mkdir(parents=True, exist_ok=True)
    cases = {
        "virtual_cell": ["rtl/nokia/virtual_cell.sv"],
        "mdi_injector": ["rtl/nokia/virtual_cell.sv","rtl/nokia/mdi_injector.sv"],
        "sound": ["rtl/nokia/nokia_sound.sv"],
        "controls": ["rtl/nokia/nokia_controls.sv"],
        "link": ["rtl/nokia/nokia_overlay.sv", "rtl/nokia/nokia_link.sv"],
        "pcd8544": ["rtl/nokia/pcd8544.sv"],
        "keypad": ["rtl/nokia/keypad_3310.sv", "rtl/nokia/pad_3310.sv"],
        "mad2": ["rtl/nokia/keypad_3310.sv", "rtl/nokia/sim_card.sv", "rtl/nokia/mad2_mmio.sv"],
        "uart": ["rtl/nokia/uart_lcd.sv"],
        "ds2": ["rtl/nokia/ds2_pad.sv", "rtl/nokia/pad_3310.sv", "rtl/nokia/keypad_3310.sv"],
        "video": ["rtl/nokia/nokia_overlay.sv", "rtl/nokia/pcd8544.sv", "rtl/nokia/nokia_video.sv", "third_party/open-pocket-gbc/rtl/video/gb_color.sv", "third_party/open-pocket-gbc/rtl/video/lcd_st7735.sv"],
        "core_smoke": cpu_sources() + ["rtl/nokia/keypad_3310.sv", "rtl/nokia/sim_card.sv", "rtl/nokia/mad2_mmio.sv", "rtl/nokia/nor_bus.sv", "rtl/nokia/dsp_service.sv", "rtl/nokia/nokia_sound.sv", "rtl/nokia/nokia_core.sv"],
        "flash_boot": ["rtl/nokia/flash_boot.sv"],
        "flash_stream": ["rtl/nokia/flash_boot.sv"],
        "arm_bus": ["rtl/nokia/arm_sdram_bus.sv"],
        "cdc_fifo": ["rtl/nokia/async_lcd_fifo.sv"],
        "nor": ["rtl/nokia/nor_bus.sv"],
        "dsp": ["rtl/nokia/dsp_service.sv"],
        "sim": ["rtl/nokia/sim_card.sv"],
        "status": ["rtl/nokia/uart_status.sv"],
        "arm_fiq": cpu_sources()+["rtl/nokia/arm7_probe.sv"],
    }
    if a.case and set(a.case)-cases.keys():
        p.error("unknown case(s): "+", ".join(sorted(set(a.case)-cases.keys())))
    vroot = Path(a.tools)/"share/verilator/include"
    os.environ["VERILATOR_ROOT"] = str(vroot.parent)
    for name, sources in cases.items():
        if a.case and name not in a.case:
            continue
        output = Path("build/tests") / name
        output.mkdir(exist_ok=True)
        subprocess.run([shutil.which("verilator_bin") or "verilator", "--cc", "--timing", "--main",
                        "-Wno-fatal", "--top-module", name+"_tb", "--Mdir", str(output),
                        *sources, f"tests/{name}_tb.sv"], check=True,
                       stdout=subprocess.DEVNULL, stderr=(output/"lint.log").open("w"))
        exe = output / ("test.exe" if os.name == "nt" else "test")
        cpp = [str(x) for x in output.glob("*.cpp")]
        build_cpp([*map(Path,cpp),vroot/"verilated.cpp",vroot/"verilated_timing.cpp",vroot/"verilated_threads.cpp"],
                  [vroot,vroot/"vltstd",output],output,exe)
        subprocess.run([str(exe.resolve())], check=True, timeout=30)


if __name__ == "__main__":
    main()
