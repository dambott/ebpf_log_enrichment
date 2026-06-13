package com.ebpflogs.logdemo;

import java.util.Map;
import net.logstash.logback.argument.StructuredArguments;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class WorkController {
  private static final Logger log = LoggerFactory.getLogger(WorkController.class);

  @GetMapping({"/health", "/smoke"})
  public ResponseEntity<String> health() {
    return ResponseEntity.ok("ok");
  }

  @GetMapping("/work")
  public ResponseEntity<Map<String, String>> work() throws InterruptedException {
    Thread.sleep(50);
    log.info("request complete", StructuredArguments.kv("route", "/work"), StructuredArguments.kv("duration_ms", 50));
    return ResponseEntity.ok(Map.of("status", "ok"));
  }
}
