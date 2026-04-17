#!/bin/bash

set -u

#########################################################
# This MacOS bash script can be run with the paired
# LaunchAgent plist to provide resilient SMB reconnection
# over LAN with a fallback IP (e.g., Tailscale).
#
# Edit the obvious parts for your use case
#########################################################

export HOME="/Users/username"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

MOUNT_POINT="/Users/username/mountpoint"
USER="username"
SHARE="share_name"
MOUNT_CMD="/sbin/mount_smbfs"

PRIMARY_HOST="smb_host_name.local"
FALLBACK_HOST="100.100.100.100"

LOGFILE="/tmp/org.username.remount-smb.log"
STATEFILE="/tmp/org.username.remount-smb.state"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"
}

is_mounted() {
  mount | grep -q "on $MOUNT_POINT "
}

host_resolves() {
  local host="$1"
  dscacheutil -q host -a name "$host" >/dev/null 2>&1
}

smb_reachable() {
  local host="$1"
  nc -zw 3 "$host" 445 >/dev/null 2>&1
}

attempt_mount() {
  local host="$1"

  log "Attempting mount via //$USER@$host/$SHARE"
  "$MOUNT_CMD" "//$USER@$host/$SHARE" "$MOUNT_POINT" >> "$LOGFILE" 2>&1

  if is_mounted; then
    log "Mount succeeded via $host"
    return 0
  fi

  log "Mount attempt failed via $host"
  return 1
}

load_state() {
  FAIL_COUNT=0
  NEXT_ALLOWED=0

  if [ -f "$STATEFILE" ]; then
    # shellcheck disable=SC1090
    . "$STATEFILE"
  fi
}

save_state() {
  cat > "$STATEFILE" <<EOF
FAIL_COUNT=$FAIL_COUNT
NEXT_ALLOWED=$NEXT_ALLOWED
EOF
}

clear_state() {
  rm -f "$STATEFILE"
}

# avoid bugging the server every 45 seconds in the case
# of unreachable resources (if you're on a VPN or whatever)
compute_backoff() {
  case "$FAIL_COUNT" in
    1) echo 45 ;;
    2) echo 90 ;;
    3) echo 180 ;;
    4) echo 300 ;;
    *) echo 600 ;;
  esac
}

record_failure() {
  local now delay
  now=$(date +%s)
  FAIL_COUNT=$((FAIL_COUNT + 1))
  delay=$(compute_backoff)
  NEXT_ALLOWED=$((now + delay))
  save_state
  log "Failure count=$FAIL_COUNT; backing off for ${delay}s until epoch $NEXT_ALLOWED"
}

record_success() {
  if [ -f "$STATEFILE" ]; then
    log "Clearing backoff state after successful mount"
  fi
  clear_state
}

mkdir -p "$MOUNT_POINT"

# if the SMB is already mounted, clear old failure state and do nothing
if is_mounted; then
  record_success
  exit 0
fi
    
load_state
NOW=$(date +%s)
 
if [ "$NOW" -lt "$NEXT_ALLOWED" ]; then
  log "Backoff active; skipping attempt until epoch $NEXT_ALLOWED"
  exit 0
fi

# biased toward the hostname path
if host_resolves "$PRIMARY_HOST"; then
  if smb_reachable "$PRIMARY_HOST"; then
    if attempt_mount "$PRIMARY_HOST"; then
      record_success
      exit 0
    fi

    log "Primary host reachable but mount failed; skipping fallback"
    record_failure
    exit 0
  else
    log "Primary host resolves but SMB is not reachable on $PRIMARY_HOST:445"
  fi  
else
  log "Primary host does not resolve: $PRIMARY_HOST"
fi
  
# use fallback only if primary path is truly unavailable
if smb_reachable "$FALLBACK_HOST"; then
  if attempt_mount "$FALLBACK_HOST"; then
    record_success
    exit 0  
  fi
else
  log "Fallback SMB is not reachable on $FALLBACK_HOST:445"
fi
  
record_failure
exit 0
