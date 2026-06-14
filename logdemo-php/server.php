#!/usr/bin/env php
<?php
ini_set('output_buffering', '0');
ini_set('implicit_flush', '1');
while (ob_get_level()) {
    ob_end_flush();
}

$stdout = fopen('php://stdout', 'wb');
stream_set_write_buffer($stdout, 0);

// OBI: sync JSON to stdout on the request thread. Avoid php -S router (stdout goes to HTTP).
function log_json(string $level, string $msg, array $fields = []): void
{
    global $stdout;
    $payload = array_merge(['level' => $level, 'msg' => $msg], $fields);
    fwrite($stdout, json_encode($payload, JSON_UNESCAPED_SLASHES) . "\n");
    fflush($stdout);
}

log_json('INFO', 'server start', ['port' => 8087]);

$server = stream_socket_server('tcp://0.0.0.0:8087', $errno, $errstr);
if ($server === false) {
    fwrite(STDERR, "bind failed: $errstr\n");
    exit(1);
}

while ($client = stream_socket_accept($server)) {
    $req = fgets($client);
    $path = '/';
    if ($req !== false && preg_match('#GET (\S+)#', $req, $m)) {
        $path = $m[1];
    }
    if ($path === '/health' || $path === '/smoke') {
        $resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";
    } elseif ($path === '/work') {
        usleep(50_000);
        log_json('INFO', 'request complete', ['route' => '/work', 'duration_ms' => 50]);
        $body = '{"status":"ok"}';
        $resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " . strlen($body)
            . "\r\nConnection: close\r\n\r\n" . $body;
    } else {
        $resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
    }
    fwrite($client, $resp);
    fclose($client);
}
