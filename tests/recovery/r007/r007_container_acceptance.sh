#!/usr/bin/env bash
# Runs INSIDE a fresh disposable Docker container, with NO bind-mounts, NO network,
# NO block devices attached, dropped caps and no-new-privileges.
# The ONLY mocked systemctl command is daemon-reload; no systemd PID 1.
set -Eeuo pipefail
export LC_ALL=C.UTF-8
SRC=/root/disk-health-restore
DEST=/opt/forprint-utils/disk-health-audit
[[ "$(. /etc/os-release; echo "$VERSION_ID")" == 12 ]] || { echo R007_DEBIAN_VERSION=FAIL; exit 11; }
[[ -f "$SRC/scripts/install_restore.sh" && ! -e "$DEST" ]] || { echo R007_FRESH_ROOT=FAIL; exit 12; }
echo R007_DEBIAN12_USERSPACE=PASS

echo '=== NATIVE INSTALLER DRY RUN ==='
DRYRUN_LOG=/tmp/r007_dryrun.log
bash "$SRC/scripts/install_restore.sh" --dry-run | tee "$DRYRUN_LOG"
grep -Fxq 'RESTORE_DRY_RUN=PASS_NO_CHANGES' "$DRYRUN_LOG" || { echo R007_DRY_RUN=FAIL; exit 13; }
echo R007_DRY_RUN=PASS

# The actual installer executes systemctl daemon-reload, which cannot contact PID 1
# in a standard Debian Docker container. Stub ONLY this command, fail closed on all others.
install -d -m 0700 /tmp/r007-systemctl-stub
cat > /tmp/r007-systemctl-stub/systemctl <<'STUB'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$#" == 1 && "$1" == daemon-reload ]]; then
    echo called >> /tmp/r007-systemctl-daemon-reload.log
    echo R007_SYSTEMCTL_DAEMON_RELOAD=STUB_ONLY_NO_PID1
else
    echo "R007_FORBIDDEN_SYSTEMCTL_ACTION=BLOCKED" >&2
    exit 97
fi
STUB
chmod 0700 /tmp/r007-systemctl-stub/systemctl

echo '=== APPLY INSIDE DISPOSABLE CONTAINER ==='
PATH="/tmp/r007-systemctl-stub:$PATH" bash "$SRC/scripts/install_restore.sh" --apply
[[ "$(wc -l < /tmp/r007-systemctl-daemon-reload.log)" == 1 ]] || { echo R007_DAEMON_RELOAD_BOUNDARY=FAIL; exit 14; }

echo '=== CHECK INSTALLED BYTES AND MODES ==='
for rel in utils/disk_health_audit.sh config/disk-health-audit.env.example; do
    cmp -s "$SRC/$rel" "$DEST/$rel" || { echo "R007_FILE_DIFF=$rel"; exit 15; }
done
for src in "$SRC/docs/"*.md "$SRC/systemd/"*; do
    rel="${src#"$SRC/"}"
    cmp -s "$src" "$DEST/$rel" || { echo "R007_FILE_DIFF=$rel"; exit 16; }
done
for unit in disk-health-audit@.service disk-health-audit-short.timer disk-health-audit-long.timer; do
    cmp -s "$SRC/systemd/$unit" "/etc/systemd/system/$unit" || { echo "R007_UNIT_DIFF=$unit"; exit 17; }
done
[[ ! -e "$DEST/config/disk-health-audit.env" ]] || { echo R007_PRIVATE_ENV_SHOULD_NOT_EXIST; exit 18; }
[[ -d "$DEST/logs/runs" ]] || { echo R007_LOG_DIR_MISSING; exit 19; }
bash -n "$DEST/utils/disk_health_audit.sh"
echo R007_INSTALL_FILES=PASS_BYTE_EXACT

echo '=== REAL SYSTEMD FILE/CALENDAR PARSER WITHOUT SYSTEMD PID1 ==='
systemd-analyze verify \
    /etc/systemd/system/disk-health-audit@.service \
    /etc/systemd/system/disk-health-audit-short.timer \
    /etc/systemd/system/disk-health-audit-long.timer
systemd-analyze calendar 'Sat *-*-* 14:00:00' >/dev/null
systemd-analyze calendar 'Sat *-*-01..07 14:00:00' >/dev/null
grep -Fxq 'Persistent=true' /etc/systemd/system/disk-health-audit-short.timer
grep -Fxq 'Persistent=true' /etc/systemd/system/disk-health-audit-long.timer
echo R007_SYSTEMD_STATIC_PARSER=PASS

# No stateful systemd manager exists. Confirm that no enable symlinks were created.
for unit in disk-health-audit-short.timer disk-health-audit-long.timer; do
    [[ ! -e "/etc/systemd/system/timers.target.wants/$unit" ]] || { echo R007_TIMER_ENABLE_UNEXPECTED; exit 20; }
done

echo '=== INSTALLER SAFETY GUARDS ==='
set +e
PATH="/tmp/r007-systemctl-stub:$PATH" bash "$SRC/scripts/install_restore.sh" --apply > /tmp/r007_second_apply.log 2>&1
rc=$?
set -e
[[ "$rc" != 0 ]] && grep -Fq 'TARGET_EXISTS_OR_BAD_ARGS' /tmp/r007_second_apply.log || { echo R007_REPEAT_APPLY_GUARD=FAIL; exit 21; }
set +e
PATH="/tmp/r007-systemctl-stub:$PATH" bash "$SRC/scripts/install_restore.sh" --enable-timers > /tmp/r007_enable.log 2>&1
rc=$?
set -e
[[ "$rc" != 0 ]] && grep -Fq 'NO_PRIVATE_CONFIG' /tmp/r007_enable.log || { echo R007_TIMER_GUARD=FAIL; exit 22; }
echo R007_REINSTALL_GUARD=PASS
echo R007_NO_PRIVATE_CONFIG_TIMER_GUARD=PASS

echo '=== FINAL CLASSIFICATION ==='
echo R007_REAL_DEBIAN12_FILESYSTEM_APPLY=PASS_CONTAINER_ONLY
echo R007_SYSTEMD_PID1=NOT_TESTED
 echo R007_PRIVATE_ENV=NOT_IMPORTED_BY_DESIGN
 echo R007_SMART_TESTS=NOT_STARTED
 echo R007_LIVE_S01_PATHS=NOT_MOUNTED
 echo R007_CONTAINER_ACCEPTANCE=PASS
 echo R007_CLEAN_DEBIAN_VM=NOT_PERFORMED
