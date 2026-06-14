# OBI trace-log enrichment demo

Multi-language demo for [OpenTelemetry eBPF Instrumentation (OBI)](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation) **trace-log correlation** on EKS. Each app writes synchronous JSON logs to stdout; OBI injects `trace_id` and `span_id` into those lines when a request carries W3C trace context.

Logs ship to **Coralogix** via the official Helm chart (`helm/values.yaml`).

## Languages (13)

| Key | Language | Port | Deployment |
|-----|----------|------|------------|
| `go` | Go | 8080 | `logdemo-go` |
| `java` | Java | 8081 | `logdemo-java` |
| `python` | Python | 8082 | `logdemo-python` |
| `node` | Node.js | 8083 | `logdemo-node` |
| `ruby` | Ruby | 8084 | `logdemo-ruby` |
| `dotnet` | .NET | 8085 | `logdemo-dotnet` |
| `rust` | Rust | 8086 | `logdemo-rust` |
| `php` | PHP | 8087 | `logdemo-php` |
| `perl` | Perl | 8088 | `logdemo-perl` |
| `cpp` | C++ | 8089 | `logdemo-cpp` |
| `kotlin` | Kotlin | 8090 | `logdemo-kotlin` |
| `scala` | Scala | 8091 | `logdemo-scala` |
| `crystal` | Crystal | 8092 | `logdemo-crystal` |

All apps expose `/health`, `/smoke`, and `/work`. The `/work` handler sleeps ~50 ms on the request thread, then logs a single JSON `request complete` line.

## Quick start

```bash
# One-time cluster setup (EKS 1.33+, kernel 6.12+)
make eks-up

# Deploy everything (requires CORALOGIX_PRIVATE_KEY)
export CORALOGIX_PRIVATE_KEY='cxtp_...'
make deploy-eks

# Verify enrichment
make test
```

## Selecting which demos to run

Running all 13 apps on a small cluster uses a lot of pod IPs. Use **`select-demos.sh`** to enable only the languages you care about.

### Interactive picker (recommended)

```bash
./select-demos.sh
# or
make select-demos
```

You'll see a checklist menu:

```
OBI logdemo — select languages to enable
────────────────────────────────────────
  1) [x] go        Go  (:8080)
  2) [x] java      Java  (:8081)
  ...

Toggle a number ·  a=all ·  c=clear ·  d=done
Presets:  p1=original 5 ·  p2=+dotnet ·  p3=JVM ·  p4=scripting ·  p5=systems
```

| Key | Action |
|-----|--------|
| `1`–`13` | Toggle a language on/off |
| `a` | Select all |
| `c` | Clear all |
| `d` | Done — save and optionally apply to cluster |
| `p1` | Original five: go, java, python, node, ruby |
| `p2` | Original five + dotnet |
| `p3` | JVM family: go, java, kotlin, scala, dotnet |
| `p4` | Scripting: go, python, node, ruby, php, perl, crystal |
| `p5` | Systems: go, rust, cpp |

Your choice is saved to **`.demo-selection`** (gitignored, one language key per line).

### Commands

```bash
./select-demos.sh apply go,rust,php     # enable only these (non-interactive)
./select-demos.sh apply                 # re-apply saved .demo-selection
./select-demos.sh status                # saved selection + live replica counts
./select-demos.sh test                  # trace tests for selected languages
./select-demos.sh deploy rust,java      # apply + build/deploy only those
./select-demos.sh list                  # print enabled keys (for APPS=...)
```

Makefile shortcuts:

```bash
make demos-status
make demos-apply LANGS=go,rust,php
make test              # tests selected languages if .demo-selection exists
make test-all          # tests all 13 regardless of selection
```

### What “apply” changes on the cluster

1. **Deployment scale** — enabled languages get `replicas=1`, disabled get `replicas=0`.
2. **Traffic sidecar** — the `traffic` container on `logdemo-go` reads targets from the `demo-traffic-targets` ConfigMap and only curls enabled apps every 60 s (alternating unprimed / traceparent-primed requests).
3. **`logdemo-go` restart** — picks up the updated ConfigMap.

`go` is always included when you apply a selection, because the traffic sidecar runs on that pod.

After a full `make deploy-eks`, the saved selection is re-applied automatically so deploy does not leave every language at `replicas=1`.

### Testing with a selection

```bash
# Test only what's in .demo-selection
./scripts/test-traces.sh

# Test one app
APP=logdemo-rust ./scripts/test-traces.sh

# Ignore .demo-selection and test everything
TEST_ALL=1 ./scripts/test-traces.sh
```

### Deploying only selected languages

Build and push images only for chosen languages (others reuse existing ECR tags):

```bash
APPS=rust,php,perl ./scripts/deploy-eks.sh
# or
./select-demos.sh deploy rust,php,perl
```

## Watching enriched logs

```bash
# Traffic sidecar output (shows ok/FAIL per enabled target)
make traffic

# App logs with trace_id
kubectl -n ebpflogs logs -l app=logdemo-rust -f | tr -d '\000' | grep trace_id

# OBI agent on the node
kubectl -n ebpflogs logs -l app.kubernetes.io/name=opentelemetry-ebpf-instrumentation -f
```

## Requirements

- **Kernel 6.12+** on EKS nodes (Amazon Linux 2023). OBI log enrichment fails on 6.1.
- **Coralogix private key** at deploy time (`CORALOGIX_PRIVATE_KEY` env var — never commit it).
- **Cluster capacity**: 13 apps + OBI + agent needs more than one `t3.medium` node; use `./select-demos.sh` or scale the node group (`eks/cluster.yaml` supports `maxSize: 2`).

## Project layout

```
logdemo-{go,java,...}/   # one directory per language
k8s/apps.yaml            # core deployments (+ traffic sidecar)
k8s/apps-more.yaml       # rust, php, perl, cpp, kotlin, scala, crystal
k8s/traffic-config.yaml  # ConfigMap template for traffic targets
helm/values.yaml         # Coralogix + OBI Helm values
scripts/
  select-demos.sh        # language picker (also ./select-demos.sh at repo root)
  languages.sh           # shared language registry
  deploy-eks.sh          # build, push, helm upgrade
  test-traces.sh         # enrichment smoke tests
  setup-eks.sh           # eksctl cluster create
select-demos.sh          # convenience wrapper
.demo-selection          # your enabled languages (created by select-demos)
```

## OBI logging rules (why apps look odd)

OBI enriches **synchronous writes to stdout on the request thread**. Patterns that break enrichment:

- Async loggers (Winston, Pino, `ILogger`, Logback async appenders)
- `php -S` router scripts (stdout becomes HTTP response body)
- Buffered logging without flush

Each demo uses the simplest sync JSON write pattern for its runtime. See existing apps before adding a new language.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CORALOGIX_PRIVATE_KEY` | — | Required for `deploy-eks` |
| `CLUSTER_NAME` | `ebpflogs` | EKS cluster |
| `AWS_REGION` | `us-west-2` | AWS region |
| `NAMESPACE` | `ebpflogs` | Kubernetes namespace |
| `APPS` | (all) | Comma-separated build list for deploy |
| `APP` | — | Single app for `test-traces.sh` |
| `TEST_ALL` | — | Set to `1` to test all languages |
| `SKIP_DEMO_SELECTION` | — | Set to `1` to skip re-applying selection after deploy |
