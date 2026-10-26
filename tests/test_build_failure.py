"""A failed FPGA build must not expose a stale .fs as its result."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build

class BuildFailureTest(unittest.TestCase):
    def test_failed_synthesis_preserves_previous_image_separately(self):
        previous_cwd=Path.cwd()
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as directory:
            root=Path(directory)
            output=root/'build/nokia_memtest'
            output.mkdir(parents=True)
            image=output/'nokia_memtest.fs'
            image.write_bytes(b'previous successful image')
            try:
                with patch.object(build,'ROOT',root),patch.object(sys,'argv',['build.py','nokia_memtest']), \
                     patch.object(build.subprocess,'run',side_effect=subprocess.CalledProcessError(1,'yosys')), \
                     patch.dict(os.environ,{},clear=False):
                    with self.assertRaises(subprocess.CalledProcessError):build.main()
                self.assertFalse(image.exists())
                saved=list(output.glob('nokia_memtest-previous-*.fs'))
                self.assertEqual(len(saved),1)
                self.assertEqual(saved[0].read_bytes(),b'previous successful image')
                receipt=json.loads((output/'build-result.json').read_text())
                self.assertEqual(receipt['status'],'failed')
                self.assertIsNone(receipt['bitstream'])
            finally:
                os.chdir(previous_cwd)

if __name__=='__main__':unittest.main()
