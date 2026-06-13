package com.network.proxy.plugin

import android.util.Log
import com.network.proxy.transparent.TransparentProxyServer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * 透明代理插件（root + iptables 模式）
 * 无需 VPN，通过 iptables REDIRECT 劫持流量到本地代理
 */
class TransparentProxyPlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/transparent"
        var instance: TransparentProxyPlugin? = null
            private set
    }

    private var channel: MethodChannel? = null
    private var server: TransparentProxyServer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = this
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val proxyPort = call.argument<Int>("proxyPort") ?: 9091
                    val started = start(proxyPort)
                    result.success(started)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "isRunning" -> {
                    result.success(server?.isRunning ?: false)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        instance = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun start(proxyPort: Int): Boolean {
        if (server?.isRunning == true) return true

        try {
            server = TransparentProxyServer(proxyPort).also { it.start() }
            Log.i("TransparentProxy", "Started on port ${server?.port}, forwarding to $proxyPort")
            return true
        } catch (e: Exception) {
            Log.e("TransparentProxy", "Failed to start: ${e.message}")
            stop()
            return false
        }
    }

    private fun stop() {
        try {
            server?.stop()
        } catch (_: Exception) {}
        server = null
    }
}
