package com.ebpflogs.logdemo

import com.sun.net.httpserver.{HttpExchange, HttpServer}
import java.net.InetSocketAddress
import java.nio.charset.StandardCharsets

// OBI: sync JSON to stdout on the request thread.
object Main {
  def logJson(level: String, msg: String, fields: (String, Any)*): Unit = {
    val sb = new StringBuilder(s"""{"level":"$level","msg":"$msg"""")
    fields.foreach { case (k, v) =>
      sb.append(',')
      v match {
        case n: Number => sb.append(s""""$k":$n""")
        case s: String => sb.append(s""""$k":"$s"""")
        case other     => sb.append(s""""$k":"$other"""")
      }
    }
    sb.append("}\n")
    print(sb.toString)
    System.out.flush()
  }

  def text(ex: HttpExchange, code: Int, body: String): Unit = {
    val bytes = body.getBytes(StandardCharsets.UTF_8)
    ex.getResponseHeaders.add("Content-Type", "text/plain")
    ex.sendResponseHeaders(code, bytes.length)
    ex.getResponseBody.write(bytes)
    ex.close()
  }

  def main(args: Array[String]): Unit = {
    logJson("INFO", "server start", "port" -> 8091)
    val server = HttpServer.create(new InetSocketAddress("0.0.0.0", 8091), 0)
    server.createContext("/health", (ex: HttpExchange) => text(ex, 200, "ok"))
    server.createContext("/smoke", (ex: HttpExchange) => text(ex, 200, "ok"))
    server.createContext("/work", (ex: HttpExchange) => {
      Thread.sleep(50)
      logJson("INFO", "request complete", "route" -> "/work", "duration_ms" -> 50)
      val bytes = """{"status":"ok"}""".getBytes(StandardCharsets.UTF_8)
      ex.getResponseHeaders.add("Content-Type", "application/json")
      ex.sendResponseHeaders(200, bytes.length)
      ex.getResponseBody.write(bytes)
      ex.close()
    })
    server.setExecutor(null)
    server.start()
    Thread.currentThread().join()
  }
}
