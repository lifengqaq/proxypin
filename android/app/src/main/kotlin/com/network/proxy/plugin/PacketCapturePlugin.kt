package com.network.proxy.plugin

import android.util.Base64
import com.network.proxy.vpn.util.PacketUtil
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * TCP/UDP 数据包捕获插件
 * 将 VPN 层拦截到的原始数据包转发到 Flutter 端
 */
class PacketCapturePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/packetCapture"
        var instance: PacketCapturePlugin? = null
            private set
    }

    private var channel: MethodChannel? = null
    private var enabled = true
    private var maxPayloadSize = 4096

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = this
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCaptureEnabled" -> {
                    enabled = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "setMaxPayloadSize" -> {
                    maxPayloadSize = call.argument<Int>("size") ?: 4096
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /**
     * 转发数据包到 Flutter
     */
    fun forwardPacket(
        protocol: String,
        sourceIp: String,
        sourcePort: Int,
        destIp: String,
        destPort: Int,
        direction: String,
        data: ByteArray,
        maxLen: Int = maxPayloadSize,
        seqNum: Long? = null,
        ackNum: Long? = null,
        syn: Boolean? = null,
        fin: Boolean? = null,
        rst: Boolean? = null,
        psh: Boolean? = null
    ) {
        if (!enabled || channel == null) return

        val payloadSize = minOf(data.size, maxLen)
        val payload = if (data.size > maxLen) data.copyOf(maxLen) else data

        channel?.invokeMethod("onPacket", mapOf(
            "protocol" to protocol,
            "sourceIp" to sourceIp,
            "sourcePort" to sourcePort,
            "destIp" to destIp,
            "destPort" to destPort,
            "direction" to direction,
            "data" to Base64.encodeToString(payload, Base64.NO_WRAP),
            "timestamp" to System.currentTimeMillis(),
            "sequenceNumber" to seqNum?.toInt(),
            "ackNumber" to ackNum?.toInt(),
            "syn" to syn,
            "ack" to ack,
            "fin" to fin,
            "rst" to rst,
            "psh" to psh
        ))
    }
}
