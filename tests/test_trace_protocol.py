import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from trace_protocol import summarize

class TraceProtocolTests(unittest.TestCase):
    def test_actual_rom_prefix_and_acknowledgements(self):
        trace='\n'.join([
            'DSP message=62 opcode=1b sub=0 length=28 payload=0080013f4905087000f110ff... cycle=283242932',
            'DSP message=63 opcode=1b sub=0 length=28 payload=00800321012b2b2b2b2b2b2b... cycle=287212579',
            'DSP message=65 opcode=1b sub=0 length=28 payload=00800341012b2b2b2b2b2b2b... cycle=291183204',
            'DSP message=66 opcode=1b sub=0 length=28 payload=00800153012b2b2b2b2b2b2b... cycle=295155177'])
        result=summarize(trace);events=result['events']
        self.assertEqual([e['lapdm'] for e in events],['SABM','RR','RR','DISC'])
        self.assertEqual([events[1]['nr'],events[2]['nr']],[1,2])
        self.assertEqual(events[0]['initial_l3_type'],8)
        self.assertTrue(events[0]['truncated'])
        self.assertEqual(events[0]['information_length'],18)
        self.assertEqual(result['opcode_counts'],{'1b':4})
        self.assertNotIn('registered',result)

    def test_zero_length_stale_sub_and_iframe_continuation(self):
        events=summarize('DSP message=1 opcode=3 sub=3 length=0 payload= cycle=1\n'
                         'DSP message=2 opcode=1b sub=0 length=8 payload=0080032211052400 cycle=2')['events']
        self.assertNotIn('sub',events[0])
        self.assertEqual(events[1]['lapdm'],'I')
        self.assertEqual(events[1]['ns'],1)
        self.assertNotIn('initial_l3_type',events[1])
        self.assertFalse(events[1]['framing_valid']) # LI claims four bytes but only three fit

    def test_complete_cm_service_packet(self):
        payload='0080013f41052471033018810819101032547698102b2b2b2b000000'
        event=summarize(f'DSP message=78 opcode=1b sub=0 length=28 payload={payload} cycle=620871835')['events'][0]
        self.assertEqual(event['captured_bytes'],28)
        self.assertFalse(event['truncated'])
        self.assertTrue(event['framing_valid'])
        self.assertEqual(event['initial_l3_pd'],5)
        self.assertEqual(event['initial_l3_type'],0x24)
        self.assertEqual(event['information_prefix'],'05247103301881081910103254769810')

if __name__=='__main__':unittest.main()
