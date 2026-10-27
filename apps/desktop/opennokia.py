"""Open Nokia 3310 desktop remote. Python 3 + pyserial; no browser or server required."""
import queue
import sys
import threading
import time
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from nokia_protocol import Parser, command, keys, status
import serial
from serial.tools import list_ports
from firmware_ui import FirmwarePage
from pc_audio import Audio
from async_serial_open import AsyncSerialOpen


class Remote:
    def __init__(self,root):
        self.root=root
        self.port=None
        self.opening=AsyncSerialOpen()
        self.mask=0
        self.pressed_at={};self.key_versions={}
        self.lock=threading.Lock()
        self.events=queue.Queue(maxsize=16)
        self.stopping=False
        self.picture=None
        self.gray=False
        self.lcd=bytes(504)
        self.audio=Audio()
        root.title('Open Nokia 3310')
        root.configure(bg='#080908')
        root.protocol('WM_DELETE_WINDOW',self.close)
        style=ttk.Style();style.theme_use('clam')
        style.configure('.',background='#080908',foreground='#cbdba5',font=('Segoe UI',11))
        style.configure('TButton',padding=10,background='#1c2119')
        notebook=ttk.Notebook(root);notebook.pack(fill='both',expand=True)
        main=ttk.Frame(notebook,padding=18);notebook.add(main,text='Remote')
        self.firmware=FirmwarePage(notebook,self);notebook.add(self.firmware,text='Firmware')
        notebook.bind('<<NotebookTabChanged>>',lambda e:self.release())
        ttk.Label(main,text='Open Nokia 3310',font=('Segoe UI',22)).pack(anchor='w')
        row=ttk.Frame(main);row.pack(fill='x',pady=10)
        choices=[p.device for p in list_ports.comports()]
        self.device=tk.StringVar(value=next((p.device for p in list_ports.comports() if p.vid==0x0403 and p.pid==0x6010),'COM6'))
        ttk.Combobox(row,textvariable=self.device,values=choices,width=14).pack(side='left')
        ttk.Button(row,text='Connect / Disconnect',command=self.connect).pack(side='right')
        self.display=tk.Label(main,bg='#c4cfa1',width=72,height=17)
        self.display.pack(fill='x',pady=8)
        self.info=tk.StringVar(value='Connect the Tang USB-UART channel B at 115200 baud.')
        ttk.Label(main,textvariable=self.info,wraplength=520).pack(fill='x')
        buttons=ttk.Frame(main);buttons.pack(fill='x',pady=10)
        layout=[ [('Menu / OK',12),('Up',14),('C / Back',13)],
                 [('Left / 4',4),('Down',15),('Right / 6',6)],
                 [('1',1),('2 ABC',2),('3 DEF',3)], [('4 GHI',4),('5 JKL',5),('6 MNO',6)],
                 [('7 PQRS',7),('8 TUV',8),('9 WXYZ',9)],[('*',10),('0',0),('#',11)] ]
        for y,row in enumerate(layout):
            for x,(label,code) in enumerate(row):
                b=ttk.Button(buttons,text=label);b.grid(row=y,column=x,padx=3,pady=3,sticky='ew')
                b.bind('<ButtonPress-1>',lambda e,k=code:self.key(k,True))
                b.bind('<ButtonRelease-1>',lambda e,k=code:self.key(k,False))
        for x in range(3):buttons.columnconfigure(x,weight=1)
        row=ttk.Frame(main);row.pack(fill='x')
        ttk.Button(row,text='System menu',command=lambda:self.send(command(5,3))).pack(side='left')
        ttk.Button(row,text='Audio test',command=self.audio_test).pack(side='left',padx=8)
        b=ttk.Button(row,text='Power (hold)');b.pack(side='right')
        b.bind('<ButtonPress-1>',lambda e:self.key(16,True));b.bind('<ButtonRelease-1>',lambda e:self.key(16,False))
        self.volume=tk.IntVar(value=5)
        ttk.Scale(main,from_=0,to=10,variable=self.volume,command=lambda v:self.send(command(6,round(float(v))))).pack(fill='x',pady=12)
        self.palette=tk.StringVar(value='Green LCD')
        palette=ttk.Combobox(main,textvariable=self.palette,values=['Green LCD','Gray LCD'],state='readonly')
        palette.pack(fill='x')
        palette.bind('<<ComboboxSelected>>',lambda e:self.send(command(7,int(self.palette.get()=='Gray LCD'))))
        self.pc_audio=tk.BooleanVar(value=True)
        ttk.Checkbutton(main,text='Play Tang audio on PC speakers',variable=self.pc_audio,command=self.toggle_audio).pack(anchor='w',pady=6)
        root.bind('<FocusOut>',lambda e:self.release() if e.widget==root else None)
        keymap={'Up':14,'Down':15,'Left':4,'Right':6,'Return':12,'BackSpace':13,'Escape':13,'asterisk':10,'numbersign':11}
        keymap.update({str(i):i for i in range(10)})
        root.bind('<KeyPress>',lambda e:self.key(keymap[e.keysym],True) if notebook.index('current')==0 and e.keysym in keymap else None)
        root.bind('<KeyRelease>',lambda e:self.key(keymap[e.keysym],False) if notebook.index('current')==0 and e.keysym in keymap else None)
        threading.Thread(target=self.worker,daemon=True).start()
        self.draw_lcd()
        root.after(40,self.poll)

    def send(self,data):
        with self.lock:
            if self.port:
                try:self.port.write(data)
                except serial.SerialException:self.disconnect()

    def key(self,key,pressed):
        if not self.port:return
        if pressed:
            if self.mask & (1<<key):return
            self.key_versions[key]=self.key_versions.get(key,0)+1
            self.pressed_at[key]=time.monotonic();self.mask|=1<<key;self.send(keys(self.mask))
        else:
            version=self.key_versions.get(key,0)
            delay=max(0,60-int((time.monotonic()-self.pressed_at.get(key,0))*1000))
            def release_key():
                if self.key_versions.get(key,0)==version:
                    self.mask&=~(1<<key);self.send(keys(self.mask))
            self.root.after(delay,release_key)

    def release(self):
        for k in self.key_versions:self.key_versions[k]+=1
        self.mask=0;self.send(keys(0))

    def connect(self):
        if self.firmware.busy:return
        if self.opening.pending:
            self.opening.cancel();self.info.set('Connection attempt cancelled.');return
        if self.port:self.release();self.send(command(5,0));self.disconnect();return
        device=self.device.get()
        if self.opening.begin(device,lambda name:serial.Serial(name,115200,timeout=.05,write_timeout=.3)):
            self.info.set('Connecting to '+device+'… Click again to cancel.')

    def disconnect(self):
        self.opening.cancel()
        self.audio.stop()
        port=self.port;self.port=None;self.mask=0
        if port:
            try:port.close()
            except OSError:pass

    def worker(self):
        parser=Parser();last=0
        while not self.stopping:
            port=self.port
            if not port:time.sleep(.05);parser=Parser();continue
            try:
                for packet in parser.feed(port.read(1024)):
                    self.audio.synth.heartbeat()
                    if packet[0]==3:self.audio.synth.update(packet[1])
                    try:self.events.put_nowait(packet)
                    except queue.Full:pass
                if time.monotonic()-last>.1:self.send(keys(self.mask));last=time.monotonic()
            except (serial.SerialException,OSError):self.disconnect()

    def poll(self):
        if self.stopping:return
        opened=self.opening.poll()
        if opened:
            kind,value=opened
            if kind=='connected':
                self.port=value;self.send(keys(0)+command(5,1));self.info.set('Connected · requesting live LCD');self.start_audio()
            else:
                self.info.set(value);messagebox.showerror('USB connection',value)
        while not self.events.empty():
            kind,body=self.events.get_nowait()
            if kind==1 and len(body)==504:
                self.lcd=body;self.draw_lcd()
            elif kind in (0,2) and len(body)>=7:
                s=status(body)
                if 'gray' in s:
                    self.gray=s['gray'];self.palette.set('Gray LCD' if self.gray else 'Green LCD');self.draw_lcd()
                    self.volume.set(s['volume'])
                self.info.set(f"{'Legacy N3 (controls only)' if kind==0 else 'N4 live link'} · ROM {'ready' if s['rom_done'] else 'loading'} · LCD writes {s['lcd_writes']} · {s['address']}")
        self.root.after(40,self.poll)

    def start_audio(self):
        try:self.audio.start()
        except Exception as e:messagebox.showerror('PC audio',f'Cannot open the default PC output: {e}')

    def toggle_audio(self):
        self.audio.enabled=self.pc_audio.get()
        if self.audio.enabled and self.port:self.start_audio()
        else:self.audio.stop()

    def audio_test(self):
        if not self.port:
            self.info.set('Connect Tang before running the audio test.');return
        self.pc_audio.set(True);self.audio.enabled=True;self.start_audio()
        self.send(command(5,1)+command(8,1))

    def draw_lcd(self):
        ink,paper=(b'\x25\x25\x25',b'\xde\xde\xd3') if self.gray else (b'\x26\x35\x1c',b'\xc4\xcf\xa1')
        rgb=bytearray()
        for y in range(48):
            for x in range(84):rgb.extend(ink if self.lcd[y//8*84+x]&(1<<(y%8)) else paper)
        self.picture=tk.PhotoImage(data=b'P6\n84 48\n255\n'+rgb,format='PPM').zoom(6,6)
        self.display.configure(image=self.picture,width=504,height=288)

    def close(self):
        if self.firmware.busy:
            messagebox.showinfo('Operation in progress','Wait for the programmer operation to finish before closing.');return
        self.release();self.send(command(5,0));self.stopping=True;self.disconnect();self.root.destroy()


if __name__=='__main__':
    if '--audio-smoke-test' in sys.argv:
        import json
        player=Audio()
        player.synth.update(bytes.fromhex('0fa000000001000000000a'))
        player.start()
        for _ in range(10):player.synth.heartbeat();time.sleep(.1)
        report={'audio_stream_active':bool(player.stream.active),'pcm_frames_written':player.frames_written,'test_hz':1000}
        player.stop()
        Path(sys.argv[sys.argv.index('--audio-smoke-test')+1]).write_text(json.dumps(report,indent=2))
        raise SystemExit(0 if report['pcm_frames_written']>=16000 else 1)
    root=tk.Tk()
    if '--smoke-test' in sys.argv:
        import json
        from flasher import find_loader
        root.withdraw();app=Remote(root);root.update_idletasks()
        report={'title':root.title(),'lcd_bytes':len(app.lcd),'lcd_width':app.picture.width(),
                'firmware_page':app.firmware.winfo_exists(),'programmer':find_loader()}
        Path(sys.argv[sys.argv.index('--smoke-test')+1]).write_text(json.dumps(report,indent=2))
        app.close()
    else:
        Remote(root);root.mainloop()
