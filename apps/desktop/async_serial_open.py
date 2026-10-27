"""Open a serial port off the Tk thread; abandon late results safely."""
import threading
import time


def _close_later(port):
    def close():
        try:port.close()
        except Exception:pass
    threading.Thread(target=close,daemon=True).start()


class AsyncSerialOpen:
    def __init__(self,timeout=5,clock=time.monotonic):
        self.timeout=timeout;self.clock=clock;self.lock=threading.Lock()
        self.generation=0;self.pending=False;self.result=None;self.deadline=0

    def begin(self,device,factory):
        with self.lock:
            if self.pending:return False
            self.generation+=1;generation=self.generation
            self.pending=True;self.result=None;self.deadline=self.clock()+self.timeout
        def run():
            port=None
            try:
                port=factory(device);port.reset_input_buffer();result=('connected',port)
            except Exception as error:
                if port is not None:_close_later(port)
                result=('error',str(error))
            with self.lock:
                stale=generation!=self.generation or not self.pending
                if not stale:self.result=result
            if stale and result[0]=='connected':_close_later(result[1])
        threading.Thread(target=run,daemon=True).start()
        return True

    def cancel(self):
        with self.lock:
            self.generation+=1;self.pending=False;result=self.result;self.result=None
        if result and result[0]=='connected':_close_later(result[1])

    def poll(self):
        with self.lock:
            if not self.pending:return None
            if self.result is not None:
                result=self.result;self.result=None;self.pending=False;return result
            if self.clock()>=self.deadline:
                self.generation+=1;self.pending=False
                return ('timeout','USB port did not open. Reconnect Tang and retry.')
        return None
