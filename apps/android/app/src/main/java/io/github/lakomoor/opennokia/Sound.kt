// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.lakomoor.opennokia
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.sin
import kotlinx.coroutines.flow.MutableStateFlow

/** Synthesizes device-reported oscillator state, never invents keypad beeps. */
object Sound {
    val enabledState=MutableStateFlow(false)
    var enabled:Boolean
        get()=enabledState.value
        set(value) { enabledState.value=value;if(value)start() else silence() }
    @Volatile private var tone=IntArray(5)
    @Volatile private var running=false
    fun update(b:ByteArray) {
        val div=Protocol.u16(b,6)
        tone=intArrayOf(Protocol.u16(b,0)/4,Protocol.u16(b,2)/4,Protocol.u16(b,4),
            if(b[8].toInt()!=0 && div!=0) 13_000_000/div else 0,(b[10].toInt() and 255).coerceIn(0,10))
        start()
    }
    fun silence() { tone=IntArray(5) }
    @Synchronized private fun start() {
        if(running || !enabled) return
        running=true
        Thread {
            var track:AudioTrack?=null
            try {
                track=AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(24000).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                    .setBufferSizeInBytes(4096).setTransferMode(AudioTrack.MODE_STREAM).build()
                track.play();val phase=DoubleArray(3);val samples=ShortArray(240)
                while(enabled) {
                    val t=tone
                    for(i in samples.indices) {
                        var v=0.0
                        for(j in 0..2) {
                            val hz=if(j==2)t[3] else if(t[2]!=0)t[j] else 0
                            if(hz in 20..11000) { phase[j]=(phase[j]+hz/24000.0)%1.0;v+=sin(phase[j]*Math.PI*2)*2200 }
                        }
                        samples[i]=(v*t[4]/10).toInt().coerceIn(-32768,32767).toShort()
                    }
                    track.write(samples,0,samples.size)
                }
            } finally { try { track?.stop();track?.release() } catch(_:Exception) {};running=false }
        }.apply { isDaemon=true;name="Nokia audio";start() }
    }
}
