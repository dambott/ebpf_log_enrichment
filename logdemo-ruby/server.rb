#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "socket"

$stdout.sync = true

def log_json(level, msg, fields = {})
  $stdout.write(JSON.generate({ level: level, msg: msg, **fields }) + "\n")
end

log_json("INFO", "server start", port: 8084)

server = TCPServer.new("0.0.0.0", 8084)
while (socket = server.accept)
  begin
    req = socket.gets.to_s
    path = req.split[1]
    if path.nil? || !req.start_with?("GET")
      socket.print "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
    elsif path == "/health" || path == "/smoke"
      socket.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
    elsif path == "/work"
      sleep 0.05
      log_json("INFO", "request complete", route: "/work", duration_ms: 50)
      body = '{"status":"ok"}'
      socket.print "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    else
      socket.print "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    end
  ensure
    socket.close
  end
end
