package com.ebpflogs.logdemo

import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets

// OBI: sync JSON to stdout on the request thread. No SLF4J/Logback.
fun logJson(level: String, msg: String, vararg fields: Pair<String, Any>) {
    val sb = StringBuilder("{\"level\":\"$level\",\"msg\":\"$msg\"")
    for ((k, v) in fields) {
        sb.append(",\"$k\":")
        sb.append(if (v is Number) v else "\"$v\"")
    }
    sb.append("}\n")
    print(sb.toString())
    System.out.flush()
}

fun main() {
    logJson("INFO", "server start", "port" to 8090)
    val server = HttpServer.create(InetSocketAddress("0.0.0.0", 8090), 0)
    server.createContext("/health") { ex ->
        val body = "ok".toByteArray(StandardCharsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "text/plain")
        ex.sendResponseHeaders(200, body.size.toLong())
        ex.responseBody.use { it.write(body) }
    }
    server.createContext("/smoke") { ex ->
        val body = "ok".toByteArray(StandardCharsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "text/plain")
        ex.sendResponseHeaders(200, body.size.toLong())
        ex.responseBody.use { it.write(body) }
    }
    server.createContext("/work") { ex ->
        Thread.sleep(50)
        logJson("INFO", "request complete", "route" to "/work", "duration_ms" to 50)
        val body = """{"status":"ok"}""".toByteArray(StandardCharsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "application/json")
        ex.sendResponseHeaders(200, body.size.toLong())
        ex.responseBody.use { it.write(body) }
    }
    server.executor = null
    server.start()
    Thread.currentThread().join()
}
