import sys
import tempfile
import unittest
import wave
from array import array
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from render_audio_trace import render


class AudioTraceTests(unittest.TestCase):
    def test_original_register_timing_pitch_and_mute(self):
        with tempfile.TemporaryDirectory() as folder:
            trace = Path(folder) / "trace.log"
            output = Path(folder) / "sound.wav"
            trace.write_text("\n".join([
                "AUDIO-W pc=1 addr=2001c byte=32 cycle=0",
                "AUDIO-W pc=1 addr=2001d byte=c8 cycle=0",
                "AUDIO-W pc=1 addr=2001e byte=ff cycle=0",
                "AUDIO-W pc=1 addr=20015 byte=20 cycle=0",
                "AUDIO-W pc=1 addr=2001e byte=0 cycle=24000",
            ]))
            result = render(trace, output, 24000, 0, 48000)
            self.assertEqual(result["frames"], 48000)
            with wave.open(str(output), "rb") as wav:
                samples = array("h", wav.readframes(wav.getnframes()))
            self.assertEqual(set(samples[:24000]), {-2200, 2200})
            self.assertEqual(set(samples[24000:]), {0})
            rises = sum(a < 0 < b for a,b in zip(samples[:23999], samples[1:24000]))
            self.assertTrue(999 <= rises <= 1001)

    def test_bad_interval_rejected(self):
        with self.assertRaises(ValueError):
            render(Path("unused"), Path("unused.wav"), 0, 0, 10)
