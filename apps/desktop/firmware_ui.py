"""Firmware page: UI stays responsive, all programmer output is queued."""
from pathlib import Path
import queue
import threading
import webbrowser
import tkinter as tk
from tkinter import filedialog,messagebox,ttk
from flasher import find_loader,program
import sys
import preferences

class FirmwarePage(ttk.Frame):
    def __init__(self,parent,remote):
        super().__init__(parent,padding=18)
        self.remote=remote;self.busy=False;self.events=queue.Queue()
        self.action=tk.StringVar(value='Test FPGA in SRAM')
        self.loader=tk.StringVar(value=find_loader());self.image=tk.StringVar();self.eeprom=tk.StringVar();self.rom=tk.StringVar()
        bundled=Path(sys.executable).parent/'images/nokia_top.fs'
        if getattr(sys,'frozen',False) and bundled.is_file():self.image.set(str(bundled))
        self.folder=tk.StringVar(value=str(Path.home()/'OpenNokia3310'/'backups'))
        for name,value in preferences.load().items():
            # Prefer the programmer and FPGA shipped with this release over old paths.
            if name=='loader' and self.loader.get():continue
            if name=='image' and bundled.is_file():continue
            getattr(self,name).set(value)
        ttk.Label(self,text='Firmware manager',font=('Segoe UI',20)).pack(anchor='w')
        ttk.Label(self,text='SRAM testing is temporary. Flash installation survives power-off.\nFlash writes require a successful full 8 MiB backup and use read-back verification.',wraplength=550).pack(anchor='w',pady=8)
        self.actions=ttk.Combobox(self,textvariable=self.action,state='readonly',values=[
            'Install complete Nokia','Detect board','Test FPGA in SRAM','Install FPGA in flash','Install Nokia ROM','Back up full flash'])
        self.actions.pack(fill='x',pady=6)
        for label,var,kind in [('FPGA .fs / Nokia .bin or .fls',self.image,'image'),
                               ('Nokia ROM for complete installation',self.rom,'image'),
                               ('EEPROM / PM (optional, 192 KiB)',self.eeprom,'file'),
                               ('Programmer executable',self.loader,'loader'),('Backup folder',self.folder,'folder')]:
            ttk.Label(self,text=label).pack(anchor='w',pady=(8,0))
            row=ttk.Frame(self);row.pack(fill='x')
            ttk.Entry(row,textvariable=var).pack(side='left',fill='x',expand=True)
            ttk.Button(row,text='Browse',command=lambda v=var,k=kind:self.browse(v,k)).pack(side='right')
        self.start=ttk.Button(self,text='Run selected operation',command=self.begin);self.start.pack(fill='x',pady=12)
        ttk.Button(self,text='Install complete Nokia (FPGA + ROM)',command=self.complete).pack(fill='x',pady=(0,8))
        ttk.Button(self,text='Download FPGA builds / Android app',command=lambda:webbrowser.open(
            'https://github.com/LakoMoor/OpenNokia3310/releases')).pack(anchor='w',pady=(0,8))
        self.progress=ttk.Progressbar(self,mode='indeterminate');self.progress.pack(fill='x')
        self.output=tk.Text(self,height=13,wrap='word',bg='#10150f',fg='#cbdba5',state='disabled')
        self.output.pack(fill='both',expand=True,pady=10)
        ttk.Label(self,text='Nokia ROM: fixed SPI offset 0x200000. No whole-chip erase.\nJTAG operations interrupt the running FPGA. Do not unplug during a flash write.',wraplength=550).pack(anchor='w')
        self.after(80,self.poll)

    def browse(self,var,kind):
        value=filedialog.askdirectory() if kind=='folder' else filedialog.askopenfilename(
            filetypes=[('Gowin FS or Nokia ROM','*.fs *.bin *.fls'),('All files','*.*')] if kind=='image' else [('All files','*.*')])
        if value:var.set(value)

    def begin(self):
        if self.busy:return
        action=self.action.get()
        if action.startswith('Install') and not messagebox.askokcancel('Install firmware',
            f'{action}\n\nFPGA/image: {self.image.get()}\nROM: {self.rom.get()}\nBackup: {self.folder.get()}\n\nA complete flash backup will be required before writing. Continue?'):return
        self.remote.release();self.remote.send(bytes.fromhex('a50500'));self.remote.disconnect()
        self.busy=True;self.start.configure(state='disabled');self.progress.start()
        values=(self.loader.get(),action,self.image.get(),self.eeprom.get(),self.folder.get())
        rom=self.rom.get()
        try:preferences.save({name:getattr(self,name).get() for name in ('loader','image','rom','eeprom','folder')})
        except OSError as e:self.events.put(('log','Could not remember installer paths: '+str(e)))
        def job():
            try:program(*values,lambda s:self.events.put(('log',s)),rom=rom);self.events.put(('done','Operation completed successfully.'))
            except Exception as e:self.events.put(('error',str(e)))
        threading.Thread(target=job,daemon=True).start()

    def complete(self):
        if self.busy:return
        self.action.set('Install complete Nokia');self.begin()

    def poll(self):
        while not self.events.empty():
            kind,text=self.events.get_nowait()
            self.output.configure(state='normal');self.output.insert('end',text+'\n');self.output.see('end');self.output.configure(state='disabled')
            if kind in ('done','error'):
                self.busy=False;self.start.configure(state='normal');self.progress.stop()
                if kind=='error':messagebox.showerror('Firmware operation',text)
        self.after(80,self.poll)
