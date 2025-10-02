#!/bin/bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")

# Defaults
CONTAINER_DEFAULT="crypto-scout-mq"
CONTAINER="$CONTAINER_DEFAULT"
VHOST="/"
PERM_CONF=".*"
PERM_WRITE=".*"
PERM_READ=".*"
TAGS=""
RMQ_USER=""
RMQ_PASS=""
TIMEOUT=120
ASSUME_YES=0
LIST_ONLY=0
CREATE_VHOST=0
VERBOSE=0

log()    { printf "%s\n" "$*"; }
info()   { printf "[INFO] %s\n" "$*"; }
warn()   { printf "[WARN] %s\n" "$*" 1>&2; }
error()  { printf "[ERROR] %s\n" "$*" 1>&2; }
die()    { error "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Create or update a RabbitMQ user in a Podman container.

Options:
  -u, --user USER           Username (required)
  -p, --password PASS       Password (prompted if omitted)
  -t, --tags TAGS           Comma-separated tags (e.g. administrator,monitoring)
  -v, --vhost VHOST         VHost to set permissions on (default: /)
  -P, --permissions C:W:R   Permission regex triplet (default: .*:.*:.*)
  -c, --container NAME      Podman container name (default: ${CONTAINER_DEFAULT})
  --create-vhost            Create VHost if it does not exist
  --timeout SEC             Wait up to SEC seconds for container health (default: ${TIMEOUT})
  -y, --yes                 Non-interactive; change password if user exists
  -l, --list                List users and exit
  --verbose                 Verbose logging
  -h, --help                Show this help and exit

Examples:
  ./${SCRIPT_NAME} -u app -p secret -t administrator -v / -P '.*:.*:.*'
  ./${SCRIPT_NAME} --user app --tags monitoring,management --vhost /streams
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user) RMQ_USER="${2:-}"; shift 2 ;;
      -p|--password) RMQ_PASS="${2:-}"; shift 2 ;;
      -t|--tags) TAGS="${2:-}"; shift 2 ;;
      -v|--vhost) VHOST="${2:-}"; shift 2 ;;
      -P|--permissions)
        IFS=':' read -r PERM_CONF PERM_WRITE PERM_READ <<< "${2:-}"
        shift 2 ;;
      -c|--container) CONTAINER="${2:-}"; shift 2 ;;
      --create-vhost) CREATE_VHOST=1; shift ;;
      --timeout) TIMEOUT="${2:-}"; shift 2 ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      -l|--list) LIST_ONLY=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }

podman_health_status() {
  podman inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true
}

container_running() {
  podman inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true
}

wait_for_container() {
  local elapsed=0
  local step=2
  if ! container_running; then
    warn "Container '$CONTAINER' not running. Waiting up to ${TIMEOUT}s for it to become healthy..."
  fi
  while (( elapsed < TIMEOUT )); do
    if container_running; then
      local status
      status=$(podman_health_status)
      if [[ -z "$status" || "$status" == "healthy" ]]; then
        return 0
      fi
      [[ $VERBOSE -eq 1 ]] && info "Health: $status (waiting)..."
    fi
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  die "Container '$CONTAINER' not healthy after ${TIMEOUT}s"
}

rmqexec() {
  [[ $VERBOSE -eq 1 ]] && info "rabbitmqctl $*"
  podman exec -i "$CONTAINER" rabbitmqctl "$@"
}

rmqdiag() {
  podman exec -i "$CONTAINER" rabbitmq-diagnostics -q ping >/dev/null 2>&1
}

user_exists() {
  rmqexec -q list_users | awk '{print $1}' | grep -Fxq "$RMQ_USER"
}

ensure_vhost() {
  if [[ $CREATE_VHOST -eq 1 ]]; then
    if ! rmqexec -q list_vhosts | grep -Fxq "$VHOST"; then
      info "Creating vhost '$VHOST'..."
      rmqexec add_vhost "$VHOST"
    fi
  fi
}

main() {
  parse_args "$@"

  if [[ $LIST_ONLY -eq 1 ]]; then
    require_cmd podman
    wait_for_container
    rmqexec list_users
    exit 0
  fi

  [[ -n "$RMQ_USER" ]] || die "Username is required. Use -u|--user"
  if [[ -z "${RMQ_PASS:-}" ]]; then
    read -r -s -p "Enter password for user '$RMQ_USER': " RMQ_PASS; echo
    [[ -n "$RMQ_PASS" ]] || die "Password cannot be empty"
  fi

  require_cmd podman
  wait_for_container

  if ! rmqdiag; then
    warn "Broker not ready yet; waiting for diagnostics ping..."
    local tries=0
    while ! rmqdiag && (( tries < TIMEOUT/2 )); do
      sleep 2; tries=$((tries+1))
    done
    rmqdiag || die "RabbitMQ is not responding to ping"
  fi

  ensure_vhost

  if user_exists; then
    info "User '$RMQ_USER' exists."
    if [[ $ASSUME_YES -eq 1 ]]; then
      info "Changing password..."
      rmqexec change_password "$RMQ_USER" "$RMQ_PASS"
    else
      read -r -p "Change password for '$RMQ_USER'? [y/N]: " ans
      if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
        rmqexec change_password "$RMQ_USER" "$RMQ_PASS"
      else
        info "Password unchanged."
      fi
    fi
  else
    info "Creating user '$RMQ_USER'..."
    rmqexec add_user "$RMQ_USER" "$RMQ_PASS"
  fi

  if [[ -n "$TAGS" ]]; then
    local _tags
    _tags=$(echo "$TAGS" | tr ',;' ' ')
    info "Setting tags: $_tags"
    rmqexec set_user_tags "$RMQ_USER" $_tags
  fi

  info "Setting permissions on vhost '$VHOST'..."
  rmqexec set_permissions -p "$VHOST" "$RMQ_USER" "$PERM_CONF" "$PERM_WRITE" "$PERM_READ"

  info "Done."
  rmqexec -q list_users | grep -E "^$RMQ_USER\b" || true
}

trap 'error "An error occurred. See messages above."; exit 1' ERR

main "$@"