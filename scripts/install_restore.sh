#!/usr/bin/env bash
# Fresh Debian host. Never triggers SMART tests unless timers separately authorized.
set -Eeuo pipefail
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET=/opt/forprint-utils/disk-health-audit
case "${1:---dry-run}" in
  --dry-run)
    bash -n "$SOURCE/utils/disk_health_audit.sh" || exit 2
    missing=0
    for tool in smartctl lsblk findmnt flock awk grep sed curl numfmt; do
      command -v "$tool" >/dev/null || { echo "MISSING_TOOL=$tool"; missing=1; }
    done
    [[ $missing == 0 ]] || { echo RESTORE_DRY_RUN=MISSING_DEPENDENCIES; exit 3; }
    [[ ! -e "$TARGET" ]] || echo "EXISTING_INSTALL_PROTECTED=$TARGET"
    echo 'RESTORE_DRY_RUN=PASS_NO_CHANGES';;
  --apply)
    [[ "$(id -u)" == 0 ]] || { echo ROOT_REQUIRED;exit 2; }
    [[ $# -eq 1 && ! -e "$TARGET" && ! -L "$TARGET" ]] || { echo TARGET_EXISTS_OR_BAD_ARGS;exit 3; }
    for tool in smartctl lsblk findmnt flock awk grep sed curl numfmt; do
      command -v "$tool" >/dev/null || { echo "MISSING_TOOL=$tool";exit 3; }
    done
    bash -n "$SOURCE/utils/disk_health_audit.sh"
    install -d -m 0755 "$TARGET" "$TARGET/config" "$TARGET/docs" "$TARGET/systemd" "$TARGET/utils" "$TARGET/logs" "$TARGET/logs/runs"
    install -m 0644 "$SOURCE/utils/disk_health_audit.sh" "$TARGET/utils/disk_health_audit.sh"
    install -m 0644 "$SOURCE/config/disk-health-audit.env.example" "$TARGET/config/disk-health-audit.env.example"
    install -m 0644 "$SOURCE/docs/"*.md "$TARGET/docs/"
    install -m 0644 "$SOURCE/systemd/"* "$TARGET/systemd/"
    install -m 0644 "$SOURCE/systemd/"* /etc/systemd/system/
    systemctl daemon-reload
    echo RESTORE_APPLIED_TIMERS_NOT_ENABLED;;
  --enable-timers)
    [[ "$(id -u)" == 0 && $# -eq 1 ]] || { echo ROOT_OR_ARGS_ERROR;exit 2; }
    [[ -f "$TARGET/utils/disk_health_audit.sh" && -f "$TARGET/config/disk-health-audit.env" ]] || { echo NO_PRIVATE_CONFIG;exit 3; }
    [[ "$(stat -c '%a' "$TARGET/config/disk-health-audit.env")" == 600 ]] || { echo ENV_MODE_MUST_BE_600;exit 3; }
    [[ -r /dev/tty ]] || { echo TTY_REQUIRED;exit 3; }
    echo 'WARNING: Persistent timers may launch missed real SMART tests immediately.'
    printf 'Type ENABLE_DISK_TESTS: '
    IFS= read -r confirm </dev/tty
    [[ "$confirm" == ENABLE_DISK_TESTS ]] || { echo CANCELLED;exit 0; }
    systemctl enable --now disk-health-audit-short.timer disk-health-audit-long.timer
    echo TIMER_ACTIVATION_REQUESTED;;
  *) echo 'Usage: install_restore.sh --dry-run | --apply | --enable-timers';exit 2;;
esac
