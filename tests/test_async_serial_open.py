import sys
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'apps'/'desktop'))
from async_serial_open import AsyncSerialOpen

class FakePort:
    def __init__(self):self.closed=threading.Event()
    def reset_input_buffer(self):pass
    def close(self):self.closed.set()

class AsyncOpenTest(unittest.TestCase):
    def wait_result(self,opener):
        end=time.monotonic()+2
        while time.monotonic()<end:
            result=opener.poll()
            if result:return result
            time.sleep(.005)
        self.fail('open result not delivered')

    def test_success_and_failure(self):
        opener=AsyncSerialOpen();port=FakePort()
        self.assertTrue(opener.begin('COM6',lambda name:port))
        self.assertEqual(self.wait_result(opener),('connected',port))
        self.assertFalse(opener.pending)
        def fail(_):raise OSError('port unavailable')
        opener.begin('COM6',fail)
        self.assertEqual(self.wait_result(opener),('error','port unavailable'))

    def test_timeout_and_cancel_close_late_port(self):
        now=[0];opener=AsyncSerialOpen(timeout=5,clock=lambda:now[0]);gate=threading.Event();port=FakePort()
        def blocked(_):gate.wait(2);return port
        opener.begin('COM6',blocked);self.assertFalse(opener.begin('COM6',blocked))
        now[0]=6;self.assertEqual(opener.poll()[0],'timeout');self.assertFalse(opener.pending)
        gate.set();self.assertTrue(port.closed.wait(2));self.assertIsNone(opener.poll())
        gate2=threading.Event();port2=FakePort()
        opener.begin('COM6',lambda _: (gate2.wait(2),port2)[1]);opener.cancel();gate2.set()
        self.assertTrue(port2.closed.wait(2));self.assertIsNone(opener.poll())

    def test_cancel_after_open_before_poll(self):
        opener=AsyncSerialOpen();port=FakePort();opened=threading.Event()
        def factory(_):opened.set();return port
        opener.begin('COM6',factory);self.assertTrue(opened.wait(2))
        # Wait for the worker to publish, then cancel before the UI accepts it.
        end=time.monotonic()+2
        while opener.result is None and time.monotonic()<end:time.sleep(.005)
        opener.cancel();self.assertTrue(port.closed.wait(2));self.assertIsNone(opener.poll())

if __name__=='__main__':unittest.main()
