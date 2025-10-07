#!/bin/bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Defaults
COMPOSE_FILE_DEFAULT="$REPO_ROOT/podman-compose.yml"
CONTAINER_DEFAULT="crypto-scout-mq"

COMPOSE_FILE="$COMPOSE_FILE_DEFAULT"
CONTAINER="$CONTAINER_DEFAULT"
TIMEOUT=120
DETACH=1            # up: default detached (daemon)
WAIT=1              # wait for health after up/restart (detached only)
PRUNE_VOLUMES=0     # down: do not remove volumes by default
TAIL_LINES=200      # logs: default tail lines
FOLLOW=0            # logs: do not follow by default
VERBOSE=0

SECRETS_FILE="$REPO_ROOT/secrets/rabbitmq.env"

log()    { printf "%s\n" "$*"; }
info()   { printf "[INFO] %s\n" "$*"; }
warn()   { printf "[WARN] %s\n" "$*" 1>&2; }
error()  { printf "[ERROR] %s\n" "$*" 1>&2; }
die()    { error "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <command> [options]

Commands:
  up            Start the stack (detached by default); waits for health unless --no-wait
  down          Stop the stack (keeps volumes by default)
  restart       Restart the stack (detached) and wait for health
  logs          Show service logs (use -f to follow)
  ps|status     Show compose and container health status
  wait|health   Wait until container health=healthy (or timeout)
  help          Show this help and exit

Global options:
  -f, --file FILE        Compose file (default: ${COMPOSE_FILE_DEFAULT})
  -c, --container NAME   Container name (default: ${CONTAINER_DEFAULT})
  --timeout SEC          Health wait timeout in seconds (default: ${TIMEOUT})
  --verbose              Verbose logging

up options:
  -d, --detached         Run in background (default)
  -a, --attach           Run attached (foreground); implies --no-wait
  --no-wait              Do not wait for health after start

down options:
  --prune                Remove volumes (data will be deleted!)

logs options:
  -f, --follow           Follow logs
  -n, --tail N           Number of lines to show from the end (default: ${TAIL_LINES})

Examples:
  ./${SCRIPT_NAME} up -d                                # start detached and wait for health
  ./${SCRIPT_NAME} up --attach                          # start attached (foreground)
  ./${SCRIPT_NAME} down                                 # stop (keep volumes)
  ./${SCRIPT_NAME} down --prune                         # stop and remove volumes (DANGER)
  ./${SCRIPT_NAME} logs -f                              # follow logs
  ./${SCRIPT_NAME} status                               # show status and health
  ./${SCRIPT_NAME} restart                              # restart and wait for health
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }

COMPOSE_CMD=()

detect_compose() {
  require_cmd podman
  if podman compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(podman compose)
  elif command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(podman-compose)
  else
    die "Podman Compose plugin not found. Install Podman with compose support or 'podman-compose'."
  fi
}

compose() {
  # shellcheck disable=SC2068
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" $@
}

podman_health_status() {
  podman inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true
}

container_running() {
  podman inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true || return 1
}

wait_for_health() {
  local elapsed=0
  local step=2
  if ! container_running; then
    info "Waiting up to ${TIMEOUT}s for container '$CONTAINER' to start..."
  fi
  while (( elapsed < TIMEOUT )); do
    if container_running; then
      local status
      status=$(podman_health_status)
      if [[ -z "$status" || "$status" == "healthy" ]]; then
        info "Container '$CONTAINER' is healthy."
        return 0
      fi
      [[ $VERBOSE -eq 1 ]] && info "Health: $status (waiting)..."
    fi
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  die "Container '$CONTAINER' not healthy after ${TIMEOUT}s"
}

print_endpoints() {
  cat <<EOF
RabbitMQ endpoints:
- Management UI: http://localhost:15672/
- AMQP: amqp://localhost:5672
- Streams: localhost:5552
- Prometheus metrics: http://localhost:15692/metrics
EOF
}

ensure_secrets() {
  if [[ ! -f "$SECRETS_FILE" ]]; then
    cat 1>&2 <<EOF
[ERROR] Missing secrets file: $SECRETS_FILE
See '$REPO_ROOT/secrets/README.md' to create it. Example:
  mkdir -p "$REPO_ROOT/secrets"
  cp "$REPO_ROOT/secrets/rabbitmq.env.example" "$REPO_ROOT/secrets/rabbitmq.env"
EOF
    exit 1
  fi
}

cmd_up() {
  [[ $DETACH -eq 1 ]] || WAIT=0  # attached implies no wait
  ensure_secrets
  detect_compose
  info "Starting stack using: $COMPOSE_FILE"
  if [[ $DETACH -eq 1 ]]; then
    compose up -d
    if [[ $WAIT -eq 1 ]]; then
      wait_for_health
      print_endpoints
    else
      info "Started detached. Skipping health wait (--no-wait)."
    fi
  else
    info "Starting in attached (foreground) mode..."
    compose up
  fi
}

cmd_down() {
  detect_compose
  info "Stopping stack using: $COMPOSE_FILE"
  if [[ $PRUNE_VOLUMES -eq 1 ]]; then
    warn "Removing volumes. This will delete RabbitMQ data in ./data/rabbitmq."
    compose down -v
  else
    compose down
  fi
}

cmd_restart() {
  detect_compose
  info "Restarting stack..."
  compose restart || {
    warn "Restart failed or containers not created yet; trying 'up -d'"
    ensure_secrets
    compose up -d
  }
  if [[ $WAIT -eq 1 ]]; then
    wait_for_health
    print_endpoints
  fi
}

cmd_logs() {
  detect_compose
  local args=(logs)
  if [[ $FOLLOW -eq 1 ]]; then args+=( -f ); fi
  args+=( --tail "$TAIL_LINES" )
  compose "${args[@]}"
}

cmd_ps() {
  detect_compose
  compose ps || true
  if container_running; then
    local status
    status=$(podman_health_status)
    info "Container '$CONTAINER' health: ${status:-unknown}"
  else
    info "Container '$CONTAINER' is not running."
  fi
}

cmd_wait() {
  wait_for_health
}

parse_global_opts() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file) COMPOSE_FILE="${2:-}"; shift 2 ;;
      -c|--container) CONTAINER="${2:-}"; shift 2 ;;
      --timeout) TIMEOUT="${2:-}"; shift 2 ;;
      --verbose) VERBOSE=1; shift ;;
      help|-h|--help) usage; exit 0 ;;
      up|down|restart|logs|ps|status|wait|health) CMD="$1"; shift; CMD_ARGS=("$@"); return 0 ;;
      *) die "Unknown option or command: $1" ;;
    esac
  done
  die "No command provided. See 'help'."
}

parse_up_opts() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--detached) DETACH=1; shift ;;
      -a|--attach) DETACH=0; shift ;;
      --no-wait) WAIT=0; shift ;;
      -f|--file|--timeout|-c|--container|--verbose) # handled globally, skip here
        shift; [[ $# -gt 0 && $1 != -* ]] && shift || true; ;;
      *) die "Unknown option for 'up': $1" ;;
    esac
  done
}

parse_down_opts() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) shift; break ;;
      --prune) PRUNE_VOLUMES=1; shift ;;
      -f|--file|-c|--container|--verbose) # handled globally
        shift; [[ $# -gt 0 && $1 != -* ]] && shift || true; ;;
      -h|--help) usage; exit 0 ;;
      *)
        # Ignore stray positional/whitespace-like args for 'down' (robust to NBSP, etc.)
        if [[ "$1" == "-"* ]]; then
          die "Unknown option for 'down': $1"
        else
          warn "Ignoring extra argument for 'down': '$1'"
          shift
        fi
        ;;
    esac
  done
}

parse_logs_opts() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--follow) FOLLOW=1; shift ;;
      -n|--tail) TAIL_LINES="${2:-}"; shift 2 ;;
      -f|--file|-c|--container|--verbose) # compose file handled globally; note: -f already used; no conflict here
        shift; [[ $# -gt 0 && $1 != -* ]] && shift || true; ;;
      *) die "Unknown option for 'logs': $1" ;;
    esac
  done
}

main() {
  CMD=""
  CMD_ARGS=()
  parse_global_opts "$@"

  case "${CMD:-}" in
    up)
      parse_up_opts "${CMD_ARGS[@]:-}"
      cmd_up
      ;;
    down)
      parse_down_opts "${CMD_ARGS[@]:-}"
      cmd_down
      ;;
    restart)
      cmd_restart
      ;;
    logs)
      parse_logs_opts "${CMD_ARGS[@]:-}"
      cmd_logs
      ;;
    ps|status)
      cmd_ps
      ;;
    wait|health)
      cmd_wait
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

trap 'error "An error occurred. See messages above."; exit 1' ERR

main "$@"
