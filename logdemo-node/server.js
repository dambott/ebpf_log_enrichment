const http = require("http");

function log(level, msg, fields = {}) {
  process.stdout.write(JSON.stringify({ level, msg, ...fields }) + "\n");
}

const server = http.createServer((req, res) => {
  const path = req.url?.split("?")[0] ?? "/";
  if (path === "/health" || path === "/smoke") {
    res.writeHead(200, { "Content-Type": "text/plain", Connection: "close" });
    res.end("ok");
    return;
  }
  if (path !== "/work") {
    res.writeHead(404, { Connection: "close" });
    res.end();
    return;
  }

  const start = Date.now();
  while (Date.now() - start < 50) {
    // sync wait on request thread (required for OBI log enricher)
  }
  log("info", "request complete", { route: "/work", duration_ms: 50 });
  res.writeHead(200, { "Content-Type": "application/json", Connection: "close" });
  res.end(JSON.stringify({ status: "ok" }));
});

server.listen(8083, "0.0.0.0", () => {
  log("info", "server start", { port: 8083 });
});
