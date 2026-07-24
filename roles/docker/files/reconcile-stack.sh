#!/bin/bash
# reconcile-stack.sh <project> <working_dir> — per-stack resilience reconciler.
#
# Installed by amun-docker (roles/docker). Invoked per stack by
# /etc/cron.d/<stack>-reconcile every few minutes. Repairs the four container
# states that survive an ungraceful reboot / sidecar restart but that Docker's
# own restart policy does NOT recover:
#
#   1. EXITED or CREATED non-oneshot service containers → start them. EXITED is
#      the class the old host-wide netns-reconcile missed (the 2026-07-03
#      outage). CREATED is a compose `up` that died between its create and
#      start phases (the 2026-07-24 passwords.lan outage: boot unit collided
#      with this cron's force-recreate) — Docker's restart policy never acts
#      on a container that has not run at least once, so only we can heal it.
#   2. NETNS DRIFT — running `network_mode: container:<id>` dependent whose
#      sidecar is gone (dead target) OR alive-but-restarted-into-a-new-netns
#      (stale: dependent stuck in the sidecar's old dead netns, so it's
#      unreachable via the sidecar's current netns / published ports — the
#      cn-fitness case the 2026-07-03 reboot test surfaced) → force-recreate.
#   3. NET-DETACHED — running container on a bridge/named network but with 0
#      attached endpoints (started before its network existed on an ungraceful
#      boot; `up -d` then saw it "running" and left it) → force-recreate. This
#      is the loki/promtail failure the 2026-07-03 reboot test surfaced.
#   4. STUCK UNHEALTHY — Up + unhealthy for ≥ STUCK_AGE_SECONDS → force-recreate.
#
# All repairs use `docker compose -p <project> up -d [--force-recreate] --no-deps`.
# Idempotent: silent no-op when the stack is clean. Emits a node-exporter
# textfile metric each run so execution is observable (Resilience dashboard).
#
# One-shot / init containers are never touched (they're *meant* to be Exited(0)).
set -o pipefail

PROJECT="$1"
WDIR="$2"
# Boot-unit basename. Defaults to basename(WDIR), which equals the stack name
# for a normally-located stack; passed explicitly when working_dir differs from
# the discovered dir (e.g. a stub cn-* dir with working_dir=/opt/<x>), so the
# boot-unit health metric checks docker-compose@<stack>, not @<working-dir>.
UNIT_NAME="${3:-}"
TEXTFILE_DIR="${RESILIENCE_TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
STUCK_AGE_SECONDS="${RESILIENCE_STUCK_AGE_SECONDS:-300}"
HOSTLABEL="$(hostname -s 2>/dev/null || hostname)"

# Compose service names that are intentionally short-lived — never "repair".
SKIP_RE='(^|[-_])(init|migrate|migrations|db-migrations|waitforinfra|mount-precheck|portainer-init|ca-bundle|ca-cert|pg-dump|mysql-dump|outline-init)([-_]|$)'

log() { logger -t "reconcile-stack[$PROJECT]" -- "$*" 2>/dev/null; echo "[reconcile-stack:$PROJECT] $*"; }

[ -n "$PROJECT" ] && [ -d "$WDIR" ] || { echo "usage: $0 <project> <working_dir>" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 2; }
cd "$WDIR" || exit 2

dc()      { docker compose -p "$PROJECT" "$@"; }
svc_of()  { docker inspect -f '{{index .Config.Labels "com.docker.compose.service"}}' "$1" 2>/dev/null; }
by_proj() { docker ps "$@" --filter "label=com.docker.compose.project=$PROJECT" -q; }

start_ts=$(date +%s)
repairs=0
success=1

# ── 1. EXITED / CREATED non-oneshot service containers ──────────────────────
# (repeated --filter status= flags OR together)
unstarted=""
for cid in $(by_proj -a --filter status=exited --filter status=created); do
  s=$(svc_of "$cid"); [ -z "$s" ] && continue
  printf '%s\n' "$s" | grep -Eq "$SKIP_RE" && continue
  unstarted="$unstarted $s"
done
unstarted=$(printf '%s\n' $unstarted | sort -u | tr '\n' ' ')
if [ -n "${unstarted// /}" ]; then
  log "starting exited/created service(s): $unstarted"
  if dc up -d --no-deps $unstarted; then repairs=$((repairs + $(printf '%s\n' $unstarted | grep -c .))); else success=0; log "ERROR starting exited/created"; fi
fi

# ── 2/3/4. netns drift + net-detachment + stuck-unhealthy among RUNNING ──────
now=$(date +%s)
recreate=""
for cid in $(by_proj); do
  reason=""
  nm=$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid" 2>/dev/null)
  if [[ "$nm" =~ ^container:([a-f0-9]+) ]]; then
    tgt="${BASH_REMATCH[1]}"
    if ! docker inspect "$tgt" >/dev/null 2>&1; then
      reason="netns-drift"                    # sidecar target is gone entirely
    else
      # Target alive — but if it RESTARTED it owns a NEW netns while this
      # dependent is still bound to the target's old (dead) netns: it serves on
      # its own localhost yet is unreachable via the sidecar's current netns /
      # published ports. Compare actual netns inodes; only act on a definite
      # mismatch (both readable — needs root, which the cron has), never on a
      # read failure, so a non-root/racy run can't false-recreate.
      tpid=$(docker inspect "$tgt" -f '{{.State.Pid}}' 2>/dev/null)
      dpid=$(docker inspect "$cid" -f '{{.State.Pid}}' 2>/dev/null)
      if [ -n "$tpid" ] && [ "$tpid" != 0 ] && [ -n "$dpid" ] && [ "$dpid" != 0 ]; then
        tns=$(readlink "/proc/$tpid/ns/net" 2>/dev/null)
        dns=$(readlink "/proc/$dpid/ns/net" 2>/dev/null)
        [ -n "$tns" ] && [ -n "$dns" ] && [ "$tns" != "$dns" ] && reason="netns-stale"
      fi
    fi
  elif [ "$nm" != host ] && [ "$nm" != none ]; then
    # On a bridge/named network but with NO attached endpoint: the container is
    # running yet unreachable by peers (ungraceful-reboot glitch — it started
    # before its network existed, then `up -d` saw it "running" and left it).
    nets=$(docker inspect -f '{{len .NetworkSettings.Networks}}' "$cid" 2>/dev/null)
    [ "$nets" = 0 ] && reason="net-detached"
  fi
  if [ -z "$reason" ]; then
    h=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid" 2>/dev/null)
    if [ "$h" = "unhealthy" ]; then
      st=$(docker inspect -f '{{.State.StartedAt}}' "$cid" 2>/dev/null)
      se=$(date -d "$st" +%s 2>/dev/null || echo "$now")
      [ $((now - se)) -ge "$STUCK_AGE_SECONDS" ] && reason="stuck-unhealthy"
    fi
  fi
  [ -z "$reason" ] && continue
  s=$(svc_of "$cid"); [ -z "$s" ] && continue
  log "$s: $reason"
  recreate="$recreate $s"
done
recreate=$(printf '%s\n' $recreate | sort -u | tr '\n' ' ')
if [ -n "${recreate// /}" ]; then
  log "force-recreating: $recreate"
  if dc up -d --force-recreate --no-deps $recreate; then repairs=$((repairs + $(printf '%s\n' $recreate | grep -c .))); else success=0; log "ERROR force-recreating"; fi
fi

# ── emit node-exporter textfile metrics ─────────────────────────────────────
if mkdir -p "$TEXTFILE_DIR" 2>/dev/null; then
  state="$TEXTFILE_DIR/.resilience_${PROJECT}.count"
  prev=$(cat "$state" 2>/dev/null || echo 0); case "$prev" in ''|*[!0-9]*) prev=0;; esac
  total=$((prev + repairs)); echo "$total" > "$state" 2>/dev/null
  dur=$(( $(date +%s) - start_ts ))
  # Boot-unit health (avoids needing node-exporter's systemd collector): the
  # unit name is docker-compose@<dir-basename>.service.
  unit="docker-compose@${UNIT_NAME:-$(basename "$WDIR")}.service"
  boot_active=0; systemctl is-active --quiet "$unit" 2>/dev/null && boot_active=1
  boot_enabled=0; systemctl is-enabled --quiet "$unit" 2>/dev/null && boot_enabled=1
  tmp="$TEXTFILE_DIR/.resilience_${PROJECT}.prom.$$"
  {
    echo '# HELP resilience_boot_unit_active 1 if the docker-compose@<stack> boot unit is active.'
    echo '# TYPE resilience_boot_unit_active gauge'
    echo "resilience_boot_unit_active{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $boot_active"
    echo '# HELP resilience_boot_unit_enabled 1 if the boot unit is enabled at boot.'
    echo '# TYPE resilience_boot_unit_enabled gauge'
    echo "resilience_boot_unit_enabled{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $boot_enabled"
    echo '# HELP resilience_reconcile_last_run_seconds Unix time of the last reconcile run.'
    echo '# TYPE resilience_reconcile_last_run_seconds gauge'
    echo "resilience_reconcile_last_run_seconds{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $(date +%s)"
    echo '# HELP resilience_reconcile_success 1 if the last run completed without error, else 0.'
    echo '# TYPE resilience_reconcile_success gauge'
    echo "resilience_reconcile_success{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $success"
    echo '# HELP resilience_reconcile_repairs_total Cumulative container repairs performed.'
    echo '# TYPE resilience_reconcile_repairs_total counter'
    echo "resilience_reconcile_repairs_total{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $total"
    echo '# HELP resilience_reconcile_duration_seconds Duration of the last reconcile run.'
    echo '# TYPE resilience_reconcile_duration_seconds gauge'
    echo "resilience_reconcile_duration_seconds{stack=\"$PROJECT\",host=\"$HOSTLABEL\"} $dur"
  } > "$tmp" && mv "$tmp" "$TEXTFILE_DIR/resilience_${PROJECT}.prom"
fi

[ "$repairs" -gt 0 ] && log "done: $repairs repair(s)"
exit 0
