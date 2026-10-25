package io.github.lakomoor.opennokia
import org.junit.Assert.*
import org.junit.Test

class ProtocolTest {
    private fun frame(type:Int,body:ByteArray):ByteArray {
        val b=byteArrayOf(0x4e,0x34,type.toByte(),(body.size shr 8).toByte(),body.size.toByte())+body
        return b+byteArrayOf(b.fold(0){a,v->a xor (v.toInt() and 255)}.toByte())
    }
    @Test fun arbitraryUsbChunkBoundaries() {
        val lcd=ByteArray(504){(it xor 0xa5).toByte()}
        val bytes=frame(1,lcd)
        for(chunk in listOf(1,2,3,7,64,255,510)) {
            val received=mutableListOf<ByteArray>();val parser=Protocol { t,b->assertEquals(1,t);received.add(b) }
            bytes.toList().chunked(chunk).forEach { parser.feed(it.toByteArray()) }
            assertEquals(1,received.size);assertArrayEquals(lcd,received.single())
        }
    }
    @Test fun noiseCorruptionAndOversizedLengthsRecover() {
        val good=frame(2,ByteArray(10){it.toByte()})
        val bad=good.copyOf().also { it[it.lastIndex]=(it.last().toInt() xor 1).toByte() }
        val out=mutableListOf<Int>();val parser=Protocol{t,_->out.add(t)}
        parser.feed(byteArrayOf(0x11,0x4e,0x34,1,0x7f,0x7f)+bad+good+good)
        assertEquals(listOf(2,2),out)
    }
    @Test fun legacyTelemetryAndKeys() {
        val b=byteArrayOf(0x4e,0x33,0x13,0,0x20,0,0x40,0x12,0x34)
        val packet=b+byteArrayOf(b.fold(0){a,v->a xor (v.toInt() and 255)}.toByte())
        var count=0
        Protocol { type,payload->assertEquals(0,type);assertEquals(0x1234,Protocol.u16(payload,5));count++ }.feed(packet)
        assertEquals(1,count)
        assertArrayEquals(byteArrayOf(0xa5.toByte(),2,0,0xa5.toByte(),3,0x10,0xa5.toByte(),4,1),Protocol.keys((1 shl 12) or (1 shl 16)))
        assertArrayEquals(byteArrayOf(0xa5.toByte(),2,0,0xa5.toByte(),3,0,0xa5.toByte(),4,0),Protocol.keys(0))
    }
}
