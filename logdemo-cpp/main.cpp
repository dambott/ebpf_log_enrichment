#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstring>
#include <iostream>
#include <string>
#include <thread>

// OBI: synchronous JSON writes to stdout on the request thread.
void log_json(const char* level, const char* msg, const char* extra) {
  std::cout << "{\"level\":\"" << level << "\",\"msg\":\"" << msg << "\"," << extra
            << "}" << std::endl;
  std::cout.flush();
}

void handle_client(int fd) {
  char buf[1024];
  ssize_t n = read(fd, buf, sizeof(buf) - 1);
  if (n <= 0) {
    close(fd);
    return;
  }
  buf[n] = '\0';
  std::string req(buf);
  std::string path;
  if (req.rfind("GET ", 0) == 0) {
    size_t start = 4;
    size_t end = req.find(' ', start);
    if (end != std::string::npos) path = req.substr(start, end - start);
  }

  const char* response;
  if (path == "/health" || path == "/smoke") {
    response =
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: "
        "close\r\n\r\nok";
  } else if (path == "/work") {
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    log_json("INFO", "request complete", "\"route\":\"/work\",\"duration_ms\":50");
    response =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
        "15\r\nConnection: close\r\n\r\n{\"status\":\"ok\"}";
  } else {
    response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
  }
  write(fd, response, strlen(response));
  close(fd);
}

int main() {
  log_json("INFO", "server start", "\"port\":8089");
  int server_fd = socket(AF_INET, SOCK_STREAM, 0);
  int opt = 1;
  setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_ANY;
  addr.sin_port = htons(8089);
  bind(server_fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr));
  listen(server_fd, SOMAXCONN);
  while (true) {
    int client = accept(server_fd, nullptr, nullptr);
    if (client >= 0) handle_client(client);
  }
}
