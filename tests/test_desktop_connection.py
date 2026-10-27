import queue
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'apps'/'desktop'))
from async_serial_open import AsyncSerialOpen
from opennokia import Remote

class Value:
    def __init__(self,value=''):self.value=value
    def get(self):return self.value
    def set(self,value):self.value=value

class Root:
    def after(self,*_):pass

class DesktopConnectionTest(unittest.TestCase):
    def test_hung_open_leaves_poll_responsive_and_timeout_visible(self):
        now=[0];gate=threading.Event();entered=threading.Event();closed=threading.Event()
        class Port:
            def reset_input_buffer(self):pass
            def close(self):closed.set()
        def hung(*args,**kwargs):entered.set();gate.wait(2);return Port()
        app=object.__new__(Remote);app.root=Root();app.firmware=type('F',(),{'busy':False})()
        app.port=None;app.opening=AsyncSerialOpen(timeout=5,clock=lambda:now[0]);app.device=Value('COM6')
        app.info=Value();app.events=queue.Queue();app.stopping=False
        try:
            with patch('opennokia.serial.Serial',side_effect=hung),patch('opennokia.messagebox.showerror') as error:
                app.connect();self.assertTrue(entered.wait(1));self.assertTrue(app.opening.pending)
                app.poll();self.assertIn('Connecting',app.info.get())
                now[0]=6;app.poll();self.assertFalse(app.opening.pending)
                self.assertIn('did not open',app.info.get());error.assert_called_once()
        finally:gate.set()
        self.assertTrue(closed.wait(2));self.assertIsNone(app.port)

if __name__=='__main__':unittest.main()
