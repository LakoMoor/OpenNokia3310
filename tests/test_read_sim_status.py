import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from read_sim_status import decode

class SimStatusTest(unittest.TestCase):
    def test_instruction_and_full_24_bit_counter(self):
        self.assertEqual(decode(bytes.fromhex('13a41234560000')),
                         {'last_instruction':'0xa4','sim_commands_mod_2_24':0x123456})
        self.assertEqual(decode(bytes.fromhex('13000000000000')),
                         {'last_instruction':'0x00','sim_commands_mod_2_24':0})

if __name__=='__main__':unittest.main()
