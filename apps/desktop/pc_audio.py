"""Play actual N4 oscillator state on the PC; no invented key sounds."""
from array import array
import math
import time

class Synth:
    rate=24000
    def __init__(self):
        self.tone=(0,0,0,0,0);self.phase=[0.,0.,0.];self.last_rx=0.

    def update(self,body):
        if len(body)!=11:return
        u16=lambda i:int.from_bytes(body[i:i+2],'big')
        divider=u16(6)
        self.tone=(u16(0)/4,u16(2)/4,u16(4),13000000/divider if body[8] and divider else 0,min(body[10],10))
        self.heartbeat()

    def heartbeat(self):self.last_rx=time.monotonic()
    def silence(self):self.tone=(0,0,0,0,0)

    def render(self,frames,now=None):
        now=time.monotonic() if now is None else now
        f1,f2,amp,buzzer,volume=self.tone
        if now-self.last_rx>.7 or volume==0:return bytes(frames*2)
        frequencies=[f1 if amp else 0,f2 if amp else 0,buzzer]
        if not any(20<=hz<=11000 for hz in frequencies):return bytes(frames*2)
        data=array('h')
        for _ in range(frames):
            value=0.
            for j,hz in enumerate(frequencies):
                if 20<=hz<=11000:
                    self.phase[j]=(self.phase[j]+hz/self.rate)%1
                    value+=math.sin(self.phase[j]*math.tau)*2200
            data.append(max(-32768,min(32767,round(value*volume/10))))
        return data.tobytes()

class Audio:
    def __init__(self):self.synth=Synth();self.stream=None;self.enabled=True;self.frames_written=0

    def start(self):
        if self.stream is not None or not self.enabled:return
        import sounddevice as sd
        stream=sd.RawOutputStream(samplerate=self.synth.rate,channels=1,dtype='int16',
                                 blocksize=480,latency='low',callback=self.callback)
        try:stream.start()
        except Exception:stream.close();raise
        self.stream=stream

    def callback(self,outdata,frames,_time,_status):
        outdata[:]=self.synth.render(frames) if self.enabled else bytes(frames*2)
        self.frames_written+=frames

    def stop(self):
        self.synth.silence()
        stream=self.stream;self.stream=None
        if stream is not None:
            try:stream.abort()
            finally:stream.close()
