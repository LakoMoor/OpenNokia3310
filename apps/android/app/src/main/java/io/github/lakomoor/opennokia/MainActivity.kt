// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.lakomoor.opennokia

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Green=Color(0xffcbdba5)
private val Bg=Color(0xff080908)
private val Panel=Color(0xff1c2119)

class MainActivity:ComponentActivity() {
    private val usb=object:BroadcastReceiver() {
        override fun onReceive(c:Context,i:Intent) {
            if(i.action==UsbManager.ACTION_USB_DEVICE_DETACHED) Board.disconnect() else Board.connect(c)
        }
    }
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        val filter=IntentFilter(Board.ACTION).apply { addAction(UsbManager.ACTION_USB_DEVICE_DETACHED) }
        if(Build.VERSION.SDK_INT>=33) registerReceiver(usb,filter,RECEIVER_NOT_EXPORTED) else registerReceiver(usb,filter)
        Board.connect(this)
        setContent { NokiaApp() }
    }
    override fun onNewIntent(intent:Intent) { super.onNewIntent(intent);Board.connect(this) }
    override fun onPause() { Board.release();Board.command(5,0);Sound.enabled=false;Sound.silence();super.onPause() }
    override fun onResume() { super.onResume();if(Board.state.value.connected)Board.command(5,1) }
    override fun onDestroy() { unregisterReceiver(usb);Board.disconnect();super.onDestroy() }
}

@Composable fun NokiaApp() {
    val state by Board.state.collectAsState()
    var tab by remember { mutableStateOf(0) }
    val ctx=LocalContext.current
    MaterialTheme(colorScheme=darkColorScheme(primary=Green,background=Bg,surface=Panel,onSurface=Color.White)) {
        Column(Modifier.fillMaxSize().background(Bg).systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(18.dp),verticalAlignment=Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Open Nokia 3310",fontSize=21.sp,fontWeight=FontWeight.Medium,color=Green)
                    Text(state.message,fontSize=12.sp,color=Color.LightGray)
                }
                TextButton(onClick={if(state.connected) Board.disconnect() else Board.connect(ctx)}) { Text(if(state.connected)"Disconnect" else "Connect") }
            }
            Box(Modifier.weight(1f)) { when(tab) { 0->Remote();1->BoardPage();2->CallsPage();else->AboutPage() } }
            Row(Modifier.fillMaxWidth().padding(8.dp),horizontalArrangement=Arrangement.SpaceEvenly) {
                listOf("Remote","Board","Calls","About").forEachIndexed { i,label ->
                    if(tab==i) FilledTonalButton(onClick={tab=i},contentPadding=PaddingValues(horizontal=15.dp)) { Text(label) }
                    else TextButton(onClick={Board.release();tab=i}) { Text(label) }
                }
            }
        }
    }
}

@Composable private fun Remote() {
    val pixels by Board.screen.collectAsState()
    val s by Board.state.collectAsState()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Panel).padding(16.dp)) {
            Canvas(Modifier.fillMaxWidth().aspectRatio(84f/48f).semantics { contentDescription="Live Nokia LCD, 84 by 48 pixels" }) {
                drawRect(if(s.gray)Color(0xffdeded3) else Color(0xffc4cfa1))
                val dx=size.width/84;val dy=size.height/48
                for(y in 0 until 48) for(x in 0 until 84)
                    if(((pixels[(y/8)*84+x].toInt() ushr (y%8)) and 1)!=0)
                        drawRect(if(s.gray)Color(0xff252525) else Color(0xff26351c),Offset(x*dx,y*dy),Size(dx+.2f,dy+.2f))
            }
        }
        Text(if(s.frames==0)"Waiting for live LCD · controls also work with legacy firmware" else "LIVE LCD · ${if(s.gray)"Gray LCD" else "Green LCD"} · ${s.frames} frames",color=Color.Gray,fontSize=12.sp)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            Key("Menu / OK",12,Modifier.weight(1f));Key("↑",14,Modifier.weight(.6f));Key("C / Back",13,Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            Key("← 4",4,Modifier.weight(1f));Key("↓",15,Modifier.weight(.6f));Key("6 →",6,Modifier.weight(1f))
        }
        val labels=listOf(listOf("1","2 ABC","3 DEF"),listOf("4 GHI","5 JKL","6 MNO"),listOf("7 PQRS","8 TUV","9 WXYZ"),listOf("*","0","#"))
        val codes=listOf(listOf(1,2,3),listOf(4,5,6),listOf(7,8,9),listOf(10,0,11))
        labels.forEachIndexed { row,items -> Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            items.forEachIndexed { col,label -> Key(label,codes[row][col],Modifier.weight(1f)) }
        } }
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick={Board.command(5,3)},modifier=Modifier.weight(1f)) { Text("System menu") }
            Key("Power (hold)",16,Modifier.weight(1f))
        }
        Text("Buttons support press, hold and release. USB timeout releases stuck keys.",color=Color.Gray,fontSize=12.sp)
        Spacer(Modifier.height(6.dp))
    }
}

@Composable private fun Key(label:String,code:Int,modifier:Modifier=Modifier) {
    val connected by Board.state.collectAsState()
    var down by remember { mutableStateOf(false) }
    DisposableEffect(code) { onDispose { Board.key(code,false) } }
    Box(modifier.heightIn(min=52.dp).clip(RoundedCornerShape(16.dp))
        .background(if(down)Green else Panel)
        .semantics { contentDescription="Nokia key $label" }
        .pointerInput(code,connected.connected) {
            detectTapGestures(onPress={
                if(connected.connected) {
                    down=true;Board.key(code,true)
                    try { tryAwaitRelease() } finally { Board.key(code,false);down=false }
                }
            })
        }.padding(12.dp),contentAlignment=Alignment.Center) {
        Text(label,color=if(down)Bg else if(connected.connected)Color.White else Color.Gray,fontSize=15.sp)
    }
}

@Composable private fun BoardPage() {
    val s by Board.state.collectAsState()
    val log by Board.log.collectAsState()
    var volume by remember { mutableStateOf(5f) }
    val sound by Sound.enabledState.collectAsState()
    LaunchedEffect(s.volume) { volume=s.volume.toFloat().coerceIn(0f,10f) }
    var reset by remember { mutableStateOf(false) }
    if(reset) AlertDialog(onDismissRequest={reset=false},title={Text("Restart Nokia?")},text={Text("Unsaved phone settings in SDRAM will be lost.")},
        confirmButton={TextButton(onClick={Board.command(5,5);reset=false}){Text("Restart")}},dismissButton={TextButton(onClick={reset=false}){Text("Cancel")}})
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Text("Board settings",fontSize=26.sp,color=Green)
        Text("Volume: ${volume.toInt()} / 10")
        Slider(value=volume,onValueChange={volume=it},valueRange=0f..10f,steps=9,onValueChangeFinished={Board.command(6,volume.toInt())})
        Row(verticalAlignment=Alignment.CenterVertically) {
            Switch(checked=sound,onCheckedChange={Sound.enabled=it})
            Text(" Play board audio on this phone")
        }
        Text("Firmware-driven buzzer and DSP tones. Sound stops on USB loss or when the app leaves the foreground.",fontSize=13.sp,color=Color.Gray)
        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick={Board.command(7,0)}){Text("Green LCD")}
            OutlinedButton(onClick={Board.command(7,1)}){Text("Gray LCD")}
        }
        OutlinedButton(onClick={Board.command(8,1)}){Text("Audio output test (1 s)")}
        OutlinedButton(onClick={reset=true},enabled=s.connected){Text("Restart phone core")}
        Text("Diagnostics",fontSize=22.sp,color=Green)
        Text("Boot: ${if(s.flags and 2!=0)"ROM loaded" else "waiting"}\nMemory: ${if(s.flags and 0x84==0)"no fault reported" else "FAULT"}\nLCD writes: ${s.lcdWrites}\nBus: ${s.address}\nLink: ${if(s.legacy)"N3 legacy" else "N4"}",fontFamily=FontFamily.Monospace)
        if(s.legacy) Text("Install the new Nokia FPGA bitstream for live screen, sound and system menu commands.",color=Green)
        Text(log.ifEmpty { "No USB events yet." },fontSize=12.sp,color=Color.Gray,fontFamily=FontFamily.Monospace)
    }
}

@Composable private fun CallsPage() {
    val ctx=LocalContext.current
    var number by rememberSaveableString()
    var note by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
        Text("Calls via Android",fontSize=26.sp,color=Green)
        Text("No cellular modem is attached to the FPGA. This opens your Android phone’s dialer; the call uses its SIM and audio, not the emulated Nokia radio.")
        OutlinedTextField(value=number,onValueChange={number=it.filter { c->c.isDigit() || c in "+*#" }.take(40)},label={Text("Phone number")},singleLine=true,modifier=Modifier.fillMaxWidth())
        Button(enabled=number.isNotBlank(),onClick={
            try { ctx.startActivity(Intent(Intent.ACTION_DIAL,Uri.fromParts("tel",number,null)));note="" }
            catch(_:Exception){note="No Android dialer is installed on this device."}
        }) { Text("Open Android dialer") }
        OutlinedButton(enabled=number.isNotBlank(),onClick={
            try { ctx.startActivity(Intent(Intent.ACTION_SENDTO,Uri.fromParts("smsto",number,null)));note="" }
            catch(_:Exception){note="No Android SMS application is installed."}
        }) { Text("Open Android SMS") }
        if(note.isNotEmpty())Text(note,color=Green)
        Text("No call is placed and no message is sent automatically. Dial and Send are controlled in Android’s own apps.",color=Color.Gray,fontSize=13.sp)
    }
}

@Composable private fun rememberSaveableString() = androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }

@Composable private fun AboutPage() {
    val ctx=LocalContext.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        Text("Open Nokia 3310",fontSize=28.sp,color=Green)
        Text("Android USB-C OTG companion · 0.2.0\nTang Nano 20K · original Nokia NHM-5 firmware")
        Text("Connect the phone to the Tang USB-C port with a data-capable OTG cable. Allow USB access. The app opens FTDI channel B at 115200 baud and leaves channel A available for JTAG.")
        Text("Original Nokia menus are controlled by the phone keypad. System menu opens FPGA display/audio controls. A modem and a real subscriber SIM are needed for independent cellular calls from the board.")
        TextButton(onClick={ctx.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://github.com/LakoMoor/OpenNokia3310")))}) { Text("Project source and releases ↗") }
        Text("GPL-3.0-or-later. USB support is adapted from Open Pocket GBC and uses usb-serial-for-android. This independent project is not affiliated with Nokia.",fontSize=13.sp,color=Color.Gray)
    }
}
