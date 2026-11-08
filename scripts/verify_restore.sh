#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/opt/forprint-utils/disk-health-audit
[[ -f "$ROOT/utils/disk_health_audit.sh" ]] || { echo NO_CANONICAL_SCRIPT;exit 2; }
bash -n "$ROOT/utils/disk_health_audit.sh"
for f in disk-health-audit@.service disk-health-audit-short.timer disk-health-audit-long.timer; do
  [[ -f "/etc/systemd/system/$f" ]] || { echo "MISSING_UNIT=$f";exit 2; }
done
systemctl show disk-health-audit@short.service -p ExecStart -p User -p Group -p Result --no-pager
systemctl list-timers --all --no-pager | grep disk-health-audit || true
echo STATIC_RESTORE_CHECK=PASS_NO_SMART_TEST_STARTED
