require "json"
require "socket"

# OBI: sync JSON to stdout on the request thread.
def log_json(level : String, msg : String, **fields)
  line = IO::Memory.new
  line << '{'
  line << %("level":#{level.to_json},"msg":#{msg.to_json})
  fields.each { |k, v| line << ",#{k.to_json}:#{v.to_json}" }
  line << '}'
  puts line.to_s
end

log_json("INFO", "server start", port: 8092)

server = TCPServer.new("0.0.0.0", 8092)
while client = server.accept
  begin
    req = client.gets
    path = req.to_s.split[1]? || "/"
    if path == "/health" || path == "/smoke"
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
    elsif path == "/work"
      sleep 0.05
      log_json("INFO", "request complete", route: "/work", duration_ms: 50)
      body = %({"status":"ok"})
      client.print "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    else
      client.print "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    end
  ensure
    client.close
  end
end
