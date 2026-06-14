use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::Duration;

fn log_json(level: &str, msg: &str, extra: &str) {
    let mut out = std::io::stdout().lock();
    writeln!(out, "{{\"level\":\"{level}\",\"msg\":\"{msg}\",{extra}}}").unwrap();
    out.flush().unwrap();
}

fn handle(mut socket: TcpStream) {
    let mut reader = BufReader::new(socket.try_clone().unwrap());
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    let path = request_line.split_whitespace().nth(1).unwrap_or("");
    let response = if path == "/health" || path == "/smoke" {
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
    } else if path == "/work" {
        thread::sleep(Duration::from_millis(50));
        log_json("INFO", "request complete", "\"route\":\"/work\",\"duration_ms\":50");
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"status\":\"ok\"}"
    } else {
        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    };
    let _ = socket.write_all(response.as_bytes());
    let _ = socket.shutdown(std::net::Shutdown::Write);
}

fn main() {
    log_json("INFO", "server start", "\"port\":8086");
    let listener = TcpListener::bind("0.0.0.0:8086").expect("bind");
    for stream in listener.incoming().flatten() {
        handle(stream);
    }
}
