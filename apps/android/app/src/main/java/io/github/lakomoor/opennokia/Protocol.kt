// SPDX-License-Identifier: GPL-3.0-or-later
package io.github.lakomoor.opennokia

/** N4,type,u16 big-endian payload length,payload,XOR of all preceding bytes.
 * N3 legacy telemetry is accepted for boards running the original bitstream.
 * Corrupt/oversized frames resynchronize without allocating from untrusted lengths. */
class Protocol(private val receive: (Int, ByteArray) -> Unit) {
    private val bytes = ArrayList<Int>()
    @Synchronized fun feed(data: ByteArray) {
        for (v in data) bytes.add(v.toInt() and 255)
        while (bytes.size >= 2) {
            if (bytes[0] != 0x4e || bytes[1] !in listOf(0x33,0x34)) { bytes.removeAt(0); continue }
            val legacy = bytes[1] == 0x33
            if (bytes.size < if (legacy) 10 else 5) break
            val length = if (legacy) 10 else 6 + (bytes[3] shl 8) + bytes[4]
            if (length > 1030) { bytes.removeAt(0); continue }
            if (bytes.size < length) break
            var crc = 0
            for (i in 0 until length) crc = crc xor bytes[i]
            if (crc != 0) { bytes.removeAt(0); continue }
            val type = if (legacy) 0 else bytes[2]
            val body = if (legacy) ByteArray(7) { bytes[it+2].toByte() }
                else ByteArray(length-6) { bytes[it+5].toByte() }
            repeat(length) { bytes.removeAt(0) }
            receive(type,body)
        }
        if (bytes.size > 2060) bytes.clear()
    }
    companion object {
        fun command(op: Int, value: Int) = byteArrayOf(0xa5.toByte(),op.toByte(),value.toByte())
        fun keys(mask: Int) = command(2,mask and 255) + command(3,(mask ushr 8) and 255) + command(4,(mask ushr 16) and 1)
        fun u16(b: ByteArray,i: Int) = ((b[i].toInt() and 255) shl 8) or (b[i+1].toInt() and 255)
    }
}
