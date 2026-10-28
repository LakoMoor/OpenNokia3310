import sys
from array import array
from pathlib import Path
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'apps/desktop'))
from pc_audio import Synth

def packet(f1=4000,f2=0,amp=1,divider=0,on=0,volume=10,buzzer_volume=255):
    return b''.join(x.to_bytes(2,'big') for x in (f1,f2,amp,divider))+bytes((on,buzzer_volume,volume))

class AudioTests(unittest.TestCase):
    def test_test_tone_pitch_and_amplitude(self):
        synth=Synth();synth.update(packet())
        samples=array('h');samples.frombytes(synth.render(24000,now=synth.last_rx))
        rises=sum(a<=0<b for a,b in zip(samples,samples[1:]))
        self.assertTrue(999<=rises<=1001,rises)
        self.assertGreater(max(samples),2100);self.assertLess(min(samples),-2100)

    def test_silence_volume_timeout_and_disconnect(self):
        synth=Synth();self.assertEqual(synth.render(480),bytes(960))
        synth.update(packet(volume=0));self.assertEqual(synth.render(480),bytes(960))
        synth.update(packet());self.assertEqual(synth.render(480,now=synth.last_rx+1),bytes(960))
        synth.heartbeat();self.assertNotEqual(synth.render(480),bytes(960))
        synth.silence();self.assertEqual(synth.render(480),bytes(960))

    def test_buzzer_divider_and_quarter_hz(self):
        synth=Synth();synth.update(packet(f1=4001,f2=3081))
        self.assertEqual(synth.tone[:2],(1000.25,770.25))
        synth.update(packet(f1=0,amp=0,divider=13000,on=1))
        self.assertEqual(synth.tone[3],1000)
        self.assertNotEqual(synth.render(480),bytes(960))

    def test_phone_buzzer_volume(self):
        synth=Synth()
        synth.update(packet(f1=0,amp=0,divider=13000,on=1,buzzer_volume=0))
        self.assertEqual(synth.render(480),bytes(960))
        synth.update(packet(f1=0,amp=0,divider=13000,on=1,buzzer_volume=255))
        samples=array('h');samples.frombytes(synth.render(480))
        self.assertEqual(set(samples),{-2200,2200})

if __name__=='__main__':unittest.main()
