from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'apps/desktop'))
import preferences

class PreferenceTests(unittest.TestCase):
    def test_remember_paths_and_ignore_unknown_data(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'build') as folder:
            path=Path(folder)/'installer.json'
            self.assertEqual(preferences.load(path),{})
            preferences.save({'rom':'E:/My ROM/phone.bin','folder':'E:/backups','token':'ignored'},path)
            self.assertEqual(preferences.load(path),{'rom':'E:/My ROM/phone.bin','folder':'E:/backups'})
            path.write_text('{broken')
            self.assertEqual(preferences.load(path),{})
            path.write_text('[]')
            self.assertEqual(preferences.load(path),{})

if __name__=='__main__':unittest.main()
