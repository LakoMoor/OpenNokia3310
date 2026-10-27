import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from sim_build import generated_cpp

class GeneratedSourcesTest(unittest.TestCase):
    def test_manifest_excludes_stale_sources_and_includes_support(self):
        (Path(__file__).resolve().parents[1]/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[1]/'build') as tmp:
            p=Path(tmp)
            (p/'Vphone_classes.mk').write_text('VM_CLASSES_FAST += \\\n  Vphone \\\n  Vphone__root \\\n\nVM_SUPPORT_SLOW += \\\n  Vphone__Syms__Slow \\\n\nVM_GLOBAL_FAST += \\\n  verilated \\\n')
            for name in ['Vphone','Vphone__root','Vphone__Syms__Slow','Vphone__stale']:
                (p/(name+'.cpp')).write_text('')
            self.assertEqual([x.name for x in generated_cpp(p,'phone')],['Vphone.cpp','Vphone__root.cpp','Vphone__Syms__Slow.cpp'])
            (p/'Vphone__root.cpp').unlink()
            with self.assertRaises(FileNotFoundError):generated_cpp(p,'phone')

if __name__=='__main__':unittest.main()
