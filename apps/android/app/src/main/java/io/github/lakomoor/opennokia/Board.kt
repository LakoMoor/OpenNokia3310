// SPDX-License-Identifier: GPL-3.0-or-later
// FTDI port selection follows Open Pocket GBC; Nokia protocol/lifecycle are new.
package io.github.lakomoor.opennokia

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager
import android.os.Build
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import com.hoho.android.usbserial.util.SerialInputOutputManager
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object Board : SerialInputOutputManager.Listener {
    const val ACTION = "io.github.lakomoor.opennokia.USB_PERMISSION"
    data class State(val connected: Boolean=false, val message: String="Connect Tang with USB-C OTG", val legacy: Boolean=false,
        val flags: Int=0, val address: String="—", val lcdWrites: Int=0, val frames: Int=0,
        val volume:Int=5,val menuOpen:Boolean=false,val gray:Boolean=false)
    val state = MutableStateFlow(State())
    val screen = MutableStateFlow(ByteArray(504))
    val log = MutableStateFlow("")
    @Volatile private var port: UsbSerialPort?=null
    private var io: SerialInputOutputManager?=null
    @Volatile private var mask=0
    @Volatile private var lastRx=0L
    private val pressedAt=LongArray(17)
    private val generation=IntArray(17)
    private var frames=0
    private val executor=Executors.newSingleThreadScheduledExecutor()
    private var parser=Protocol(::packet)
    init { executor.scheduleAtFixedRate({
        val p=port
        if(p!=null) try { p.write(Protocol.keys(mask),200) } catch(e:Exception) { failed(e) }
        if(System.currentTimeMillis()-lastRx>700) Sound.silence()
    },0,100,TimeUnit.MILLISECONDS) }
    private fun append(s:String) { log.value=(log.value+s+"\n").takeLast(6000) }
    fun connect(ctx:Context) {
        if(port!=null) return
        val mgr=ctx.getSystemService(Context.USB_SERVICE) as UsbManager
        val d=UsbSerialProber.getDefaultProber().findAllDrivers(mgr).firstOrNull { it.device.vendorId==0x0403 && it.device.productId==0x6010 }
        if(d==null) { state.value=State(); return }
        if(!mgr.hasPermission(d.device)) {
            val flags=if(Build.VERSION.SDK_INT>=31) PendingIntent.FLAG_MUTABLE else 0
            mgr.requestPermission(d.device,PendingIntent.getBroadcast(ctx,0,Intent(ACTION).setPackage(ctx.packageName),flags))
            state.value=State(message="Allow access to the Tang USB device"); return
        }
        executor.execute {
            var candidate:UsbSerialPort?=null
            try {
                check(d.ports.size>=2) { "FTDI UART channel B not found; JTAG channel A will not be opened" }
                val conn=mgr.openDevice(d.device) ?: error("USB permission or connection lost")
                candidate=d.ports[1]
                try { candidate.open(conn) } catch(e:Exception) { conn.close(); throw e }
                candidate.setParameters(115200,8,UsbSerialPort.STOPBITS_1,UsbSerialPort.PARITY_NONE)
                mask=0;frames=0;parser=Protocol(::packet);lastRx=System.currentTimeMillis();port=candidate
                state.value=State(true,"Connected · FTDI B · 115200 baud")
                io=SerialInputOutputManager(candidate,this).also { it.start() }
                candidate.write(Protocol.keys(0)+Protocol.command(5,1),500)
                append("Connected to UART B. Requesting live LCD.")
            } catch(e:Exception) { try { candidate?.close() } catch(_:Exception) {}; failed(e) }
        }
    }
    fun key(key:Int,down:Boolean) {
        if(key !in 0..16 || port==null) return
        synchronized(this) {
            if(down) {
                generation[key]++;pressedAt[key]=System.nanoTime();mask=mask or (1 shl key)
                sendMask(mask)
            } else {
                val version=generation[key]
                val delay=(60_000_000-(System.nanoTime()-pressedAt[key])).coerceAtLeast(0)
                executor.schedule({synchronized(this) { if(generation[key]==version) { mask=mask and (1 shl key).inv();sendMask(mask) } }},delay,TimeUnit.NANOSECONDS)
            }
        }
    }
    private fun sendMask(value:Int) { executor.execute { try { port?.write(Protocol.keys(value),200) } catch(e:Exception) { failed(e) } } }
    fun release() { synchronized(this) { for(i in generation.indices)generation[i]++;mask=0;sendMask(0) } }
    fun command(op:Int,value:Int) { executor.execute { try { port?.write(Protocol.command(op,value),250) } catch(e:Exception) { failed(e) } } }
    fun disconnect() { release(); executor.execute {
        try { port?.write(Protocol.keys(0)+Protocol.command(5,0),200) } catch(_:Exception) {}
        close()
    } }
    private fun close() {
        io?.stop();io=null;try { port?.close() } catch(_:Exception) {};port=null
        Sound.silence();screen.value=ByteArray(504);state.value=State()
    }
    private fun failed(e:Exception) { append("USB: ${e.message}");close();state.value=State(message="USB disconnected: ${e.message}") }
    override fun onRunError(e:Exception) { executor.execute { failed(e) } }
    override fun onNewData(data:ByteArray) { parser.feed(data) }
    private fun packet(type:Int,b:ByteArray) {
        lastRx=System.currentTimeMillis()
        when(type) {
            0 -> if(b.size==7) { val addr=b.sliceArray(1..4).joinToString("") { "%02x".format(it.toInt() and 255) }
                state.value=state.value.copy(legacy=true,message="Connected · legacy firmware (update for live LCD)",flags=b[0].toInt() and 255,address="0x$addr",lcdWrites=Protocol.u16(b,5)) }
            1 -> if(b.size==504) { screen.value=b.copyOf();frames++;state.value=state.value.copy(frames=frames,legacy=false,message="Connected · live LCD · FTDI B") }
            2 -> if(b.size>=7) { val addr=b.sliceArray(1..4).joinToString("") { "%02x".format(it.toInt() and 255) }
                state.value=state.value.copy(flags=b[0].toInt() and 255,address="0x$addr",lcdWrites=Protocol.u16(b,5),legacy=false,
                    volume=if(b.size>=10)b[7].toInt() and 255 else state.value.volume,
                    menuOpen=b.size>=10 && b[8].toInt() and 1!=0,gray=b.size>=10 && b[8].toInt() and 2!=0) }
            3 -> if(b.size==11) { Sound.update(b);state.value=state.value.copy(volume=(b[10].toInt() and 255).coerceIn(0,10)) }
        }
    }
}
