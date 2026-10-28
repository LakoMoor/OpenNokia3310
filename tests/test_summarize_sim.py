import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from summarize_sim import summarize

class SimSummaryTest(unittest.TestCase):
    def test_completion_and_errors(self):
        result = summarize('SIM RESULT ins=a4 fid=6f07 sw=9f0f length=0 offset=0\n'
                           'SIM RESULT ins=b0 fid=6f07 sw=9402 length=10 offset=1\n'
                           'SIM RESULT ins=f2 fid=6f07 sw=9000 length=0 offset=0')
        self.assertEqual(result['completions'], 3)
        self.assertEqual(result['non_success_responses'][0]['status'], '9402')
        self.assertEqual(len(result['non_success_responses']), 1)
        self.assertEqual(result['last_response']['instruction'], 'f2')

    def test_missing_trace_is_not_success(self):
        result = summarize('PROGRESS cycle=1')
        self.assertEqual(result['completions'], 0)
        self.assertIsNone(result['last_response'])

if __name__ == '__main__':
    unittest.main()
