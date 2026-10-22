"""Incremental C++ build for the local Verilator harnesses."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
from pathlib import Path
import subprocess


def build_cpp(sources, includes, output, exe):
    output=Path(output)
    obj=output/"objects"
    obj.mkdir(exist_ok=True)
    flags=["-std=c++20","-O1","-pthread","-DVL_TIME_CONTEXT",*["-I"+str(x) for x in includes]]
    header_hash=hashlib.sha256()
    for header in sorted(output.glob("*.h")):
        header_hash.update(header.read_bytes())
    def compile_one(source):
        source=Path(source)
        signature=hashlib.sha256(source.read_bytes()+header_hash.digest()+str(flags).encode()).hexdigest()
        target=obj/(source.stem+".o")
        stamp=target.with_suffix(".sha256")
        if not target.exists() or not stamp.exists() or stamp.read_text()!=signature:
            with target.with_suffix(".log").open("w") as log:
                subprocess.run(["g++",*flags,"-c",str(source),"-o",str(target)],check=True,stdout=log,stderr=log)
            stamp.write_text(signature)
        return str(target)
    with ThreadPoolExecutor(max_workers=4) as pool:
        objects=list(pool.map(compile_one,sources))
    with (output/"link.log").open("w") as log:
        subprocess.run(["g++","-pthread",*objects,"-o",str(exe)],check=True,stdout=log,stderr=log)
