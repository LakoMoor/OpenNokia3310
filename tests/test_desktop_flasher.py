import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'apps/desktop'),str(ROOT/'tools')]
import flasher

class FlashTests(unittest.TestCase):
    def setUp(self):
        (ROOT/'build').mkdir(exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=ROOT/'build');self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name);self.loader=self.home/'loader.exe';self.loader.touch()
        self.fs=self.home/'test.fs';self.fs.write_bytes(b'00111011100000000000100000111110\n'+b'0'*1100)

    def test_sram_never_writes_flash(self):
        with patch.object(flasher,'run') as run,patch.object(flasher,'backup') as backup:
            flasher.program(self.loader,'Test FPGA in SRAM',self.fs,'',self.home,print)
            backup.assert_not_called();self.assertEqual(run.call_args.args[1],[self.fs])

    def test_failed_backup_blocks_write(self):
        with patch.object(flasher,'run') as run,patch.object(flasher,'backup',side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):flasher.program(self.loader,'Install FPGA in flash',self.fs,'',self.home,print)
            run.assert_not_called()

    def test_incomplete_actual_backup_blocks_write(self):
        with patch.object(flasher,'run') as run:
            with self.assertRaisesRegex(RuntimeError,'Incomplete backup'):
                flasher.program(self.loader,'Install FPGA in flash',self.fs,'',self.home,print)
            self.assertEqual(run.call_count,1)
            self.assertIn('--dump-flash',run.call_args.args[1])

    def test_rom_validation_before_backup_and_fixed_offset(self):
        source=self.home/'rom.bin';source.write_bytes(b'NHM-5'+bytes(0x200000-5))
        with patch.object(flasher,'run') as run,patch.object(flasher,'backup') as backup:
            flasher.program(self.loader,'Install Nokia ROM',source,'',self.home,lambda s:None)
            backup.assert_called_once()
            self.assertEqual(run.call_args.args[1][:6],['-f','--verify','-o','0x200000','--file-type','bin'])
            self.assertEqual(source.read_bytes()[:5],b'NHM-5')
        source.write_bytes(b'bad')
        with patch.object(flasher,'backup') as backup:
            with self.assertRaises(ValueError):flasher.program(self.loader,'Install Nokia ROM',source,'',self.home,print)
            backup.assert_not_called()

    def test_reject_non_bitstream(self):
        self.fs.write_bytes(b'x'*2000)
        with self.assertRaises(ValueError):flasher.validate_fpga(self.fs)

if __name__=='__main__':unittest.main()
