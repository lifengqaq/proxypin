package com.network.proxy.transparent

import android.util.Log
import java.io.*
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 透明代理 TCP 服务器
 * 配合 iptables REDIRECT 规则，接收被劫持的 TCP 连接
 * 通过 /proc/net/tcp 获取原始目标地址，转发到 Flutter 代理
 */
class TransparentProxyServer(private val proxyPort: Int) {
    companion object {
        private const val TAG = "TransparentProxy"
        private const val IPTABLES_CMD = "iptables"
    }

    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var thread: Thread? = null
    private var listenPort: Int = 0

    val isRunning: Boolean get() = running.get()
    val port: Int get() = listenPort

    fun start() {
        if (running.getAndSet(true)) return

        serverSocket = ServerSocket(0).also {
            listenPort = it.localPort
        }
        thread = Thread({ acceptLoop() }, "TransparentProxy").also { it.start() }

        // 添加 iptables 规则：重定向所有非本地 TCP 到透明代理
        setupIptables()
    }

    fun stop() {
        running.set(false)

        // 移除 iptables 规则
        removeIptables()

        try {
            serverSocket?.close()
        } catch (_: Exception) {}

        thread?.interrupt()
        thread = null
        serverSocket = null
    }

    private fun acceptLoop() {
        Log.i(TAG, "Accept loop started on port $listenPort, forwarding to $proxyPort")
        while (running.get()) {
            try {
                val clientSocket = serverSocket?.accept() ?: break
                Thread({ handleConnection(clientSocket) }, "TP-${clientSocket.port}").start()
            } catch (e: InterruptedException) {
                break
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "Accept error: ${e.message}")
            }
        }
        Log.i(TAG, "Accept loop stopped")
    }

    private fun handleConnection(client: Socket) {
        try {
            // 获取原始目标地址
            val originalDest = getOriginalDestination(client)
            if (originalDest == null) {
                Log.w(TAG, "Could not find original destination for ${client.inetAddress}:${client.port}")
                client.close()
                return
            }

            Log.d(TAG, "Connection from ${client.inetAddress}:${client.port} -> ${originalDest.host}:${originalDest.port}")

            // 连接到 Flutter 代理
            val proxy = Socket().also {
                it.connect(InetSocketAddress("127.0.0.1", proxyPort), 5000)
            }

            // 发送原始目标信息（HTTP CONNECT 方式）
            val preamble = "CONNECT ${originalDest.host}:${originalDest.port} HTTP/1.0\r\n" +
                    "X-Transparent: 1\r\n" +
                    "\r\n"
            proxy.getOutputStream().write(preamble.toByteArray())

            // 双向桥接
            bridge(client, proxy)
        } catch (e: Exception) {
            Log.w(TAG, "Connection error: ${e.message}")
            try { client.close() } catch (_: Exception) {}
        }
    }

    private fun bridge(client: Socket, server: Socket) {
        val threads = listOf(
            threadCopy(client.getInputStream(), server.getOutputStream(), "C->S"),
            threadCopy(server.getInputStream(), client.getOutputStream(), "S->C"),
        )
        threads.forEach { it.join(30_000) }
        threads.forEach { it.interrupt() }
        try { client.close() } catch (_: Exception) {}
        try { server.close() } catch (_: Exception) {}
    }

    private fun threadCopy(input: InputStream, output: OutputStream, name: String): Thread {
        return Thread({
            val buf = ByteArray(8192)
            try {
                while (true) {
                    val len = input.read(buf)
                    if (len <= 0) break
                    output.write(buf, 0, len)
                    output.flush()
                }
            } catch (_: Exception) {}
        }, name).also { it.start() }
    }

    /**
     * 从 /proc/net/tcp 获取连接的原始目标地址
     */
    private fun getOriginalDestination(socket: Socket): InetSocketAddress? {
        val localPort = socket.localPort
        val remoteAddr = socket.inetAddress.hostAddress
        val remotePort = socket.port

        try {
            File("/proc/net/tcp").bufferedReader().use { reader ->
                reader.readLine() // skip header
                reader.forEachLine { line ->
                    val parts = line.trim().split("\\s+".toRegex())
                    if (parts.size < 10) return@forEachLine

                    val localAddr = parseAddress(parts[1]) // original destination
                    val remAddr = parseAddress(parts[2])   // source (the app)
                    val localP = parsePort(parts[1])
                    val remP = parsePort(parts[2])

                    if (remP == remotePort && remAddr == remoteAddr && localP == localPort) {
                        return InetSocketAddress(localAddr, localP)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error reading /proc/net/tcp: ${e.message}")
        }
        return null
    }

    private fun parseAddress(hex: String): String {
        val parts = hex.split(":")
        val ipHex = parts[0]
        // Network byte order (big-endian) to host byte order
        val ip = StringBuilder()
        for (i in ipHex.length - 2 downTo 0 step 2) {
            val octet = ipHex.substring(i, i + 2).toInt(16)
            ip.append(octet)
            if (i > 1) ip.append(".")
        }
        return ip.toString()
    }

    private fun parsePort(field: String): Int {
        val parts = field.split(":")
        return parts[1].toInt(16)
    }

    private fun setupIptables() {
        try {
            // 清除旧规则
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -F proxy_pin 2>/dev/null"))
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -X proxy_pin 2>/dev/null"))

            // 创建自定义链 + 规则
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -N proxy_pin"))
            // 绕过本地代理端口
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -A proxy_pin -p tcp --dport $proxyPort -j RETURN"))
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -A proxy_pin -p tcp --dport $listenPort -j RETURN"))
            // 重定向到透明代理
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -A proxy_pin -p tcp -j REDIRECT --to-port $listenPort"))
            // 加入 OUTPUT 链
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -A OUTPUT -j proxy_pin"))

            Log.i(TAG, "iptables rules set up (nat OUTPUT redirect to $listenPort)")
        } catch (e: Exception) {
            Log.e(TAG, "iptables setup failed: ${e.message}")
        }
    }

    private fun removeIptables() {
        try {
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -D OUTPUT -j proxy_pin 2>/dev/null"))
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -F proxy_pin 2>/dev/null"))
            Runtime.getRuntime().exec(arrayOf("su", "-c", "$IPTABLES_CMD -t nat -X proxy_pin 2>/dev/null"))
            Log.i(TAG, "iptables rules removed")
        } catch (_: Exception) {}
    }
}
