#!/usr/bin/env bash
# One-shot R007 Docker Debian 12 container acceptance. DOES NOT run on host /opt or /etc.
set -Eeuo pipefail
umask 077
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
EXPECTED_HEAD=dcd164fb6b40eea2de7d6ddc2469bbb17d6ccb1e
BASE_HEAD=d45ab30619e17104c3340f5ec3d4dc7531fe559e
EXPECTED_CIPHER_SHA=130d95aaa3b8c733e350b7db9b901025eb783968ef6860f32f914e58878ab629
REPO_URL=https://github.com/Kovalchuk-PrintMaster/System_Administrator_Dedian_HDD-SDD_Healht.git
CIPHER=private-backup/DISK_HEALTH_PRIVATE_FULL_20261108T193152Z.tar.gz.gpg
[[ "$(id -u)" == 0 ]] || { echo R007_ROOT_REQUIRED;exit 2; }
for cmd in bash sha256sum python3 git docker mktemp cp tar; do
  command -v "$cmd" >/dev/null || { echo "R007_MISSING=$cmd";exit 2; }
done
cd "$ROOT"
echo '=== R007 PACKAGE INTEGRITY ==='
sha256sum -c SHA256SUMS || { echo R007_PACKAGE_INTEGRITY=FAIL; exit 3; }
python3 -m unittest -q test_r007 || { echo R007_SELFTEST=FAIL;exit 3; }
echo R007_PACKAGE_AND_SELFTEST=PASS

echo '=== R007 DOCKER PREFLIGHT ==='
# docker info exports OSType at the top level, not under .Server.
DOCKER_OS_TYPE="$(docker info --format '{{.OSType}}' 2>/dev/null || true)"
if [[ "$DOCKER_OS_TYPE" != linux ]]; then
  echo "R007_DOCKER_OS_TYPE=${DOCKER_OS_TYPE:-UNAVAILABLE}"
  echo R007_DOCKER_DAEMON=UNAVAILABLE_OR_NOT_LINUX
  exit 4
fi
echo R007_DOCKER_DAEMON=PASS_LINUX

TMP="$(mktemp -d /root/disk-health-r007.XXXXXXXX)"
IMAGE="forprint-disk-health-r007-check:$(basename "$TMP" | tr '[:upper:]' '[:lower:]')"
REPORT_DIR=/root/forprint-disk-health-reports
install -d -m 0700 "$REPORT_DIR"
REPORT="$REPORT_DIR/R007_Debian12_Container_$(date -u +%Y%m%dT%H%M%SZ).txt"
cleanup() {
  docker image rm "$IMAGE" >/dev/null 2>&1 || true
  rm -rf -- "$TMP"
}
trap cleanup EXIT

echo '=== R007 GITHUB SOURCE PIN ==='
if ! git -c credential.helper= -c core.askPass= clone --quiet --depth 1 --single-branch --branch main "$REPO_URL" "$TMP/repo"; then
  echo R007_GITHUB_CLONE=FAIL
  exit 5
fi
ACTUAL="$(git -C "$TMP/repo" rev-parse HEAD)"
[[ "$ACTUAL" == "$EXPECTED_HEAD" ]] || { echo "R007_REMOTE_CHANGED_HEAD=$ACTUAL EXPECTED=$EXPECTED_HEAD";exit 5; }
[[ "$(git -C "$TMP/repo" rev-list --count HEAD)" == 1 ]] || { echo R007_SHALLOW_CLONE_UNEXPECTED;exit 5; }
printf '%s  %s\n' "$EXPECTED_CIPHER_SHA" "$TMP/repo/$CIPHER" | sha256sum -c - >/dev/null || { echo R007_ENCRYPTED_BACKUP_SHA=FAIL; exit 5; }
[[ -f "$TMP/repo/docs/ACCEPTANCE_R005_20261108_UA.md" ]] || { echo R007_R006_CLOSEOUT_MISSING;exit 5; }
bash -n "$TMP/repo/utils/disk_health_audit.sh"
echo R007_GITHUB_SOURCE=PASS_PINNED_HEAD_AND_CIPHER

mkdir -p "$TMP/build/repo"
cp -a "$TMP/repo/." "$TMP/build/repo/"
rm -rf "$TMP/build/repo/.git"
cp "$ROOT/Dockerfile" "$ROOT/r007_container_acceptance.sh" "$TMP/build/"
echo '=== BUILD DISPOSABLE DEBIAN 12 IMAGE (APT NETWORK MAY BE NEEDED) ==='
if ! docker build --pull --tag "$IMAGE" "$TMP/build" >"$TMP/docker_build.log" 2>&1; then
  echo R007_DOCKER_BUILD=FAIL
  tail -n 35 "$TMP/docker_build.log" || true
  exit 6
fi
echo R007_DOCKER_BUILD=PASS

echo '=== RUN IN NO-NETWORK / NO-DEVICE-MOUNT CONTAINER ==='
set +e
docker run --rm --pull=never \
    --network=none --cap-drop=ALL --security-opt=no-new-privileges \
    --pids-limit=128 --memory=768m --cpus=1 \
    "$IMAGE" >"$TMP/acceptance.log" 2>&1
rc=$?
set -e
cat "$TMP/acceptance.log"
if [[ $rc -ne 0 ]] || ! grep -Fxq 'R007_CONTAINER_ACCEPTANCE=PASS' "$TMP/acceptance.log"; then
  echo "R007_RESULT=FAIL_CONTAINER_EXIT_$rc"
  exit 7
fi
{
  echo R007_DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo R007_GITHUB_HEAD="$ACTUAL"
  echo R007_CIPHER_SHA256="$EXPECTED_CIPHER_SHA"
  echo R007_CONTEXT="Docker Debian 12 userspace, no privileged access, no host bind mounts"
  cat "$TMP/acceptance.log"
} > "$REPORT"
chmod 0600 "$REPORT"
echo R007_RESULT=PASS_DEBIAN12_CONTAINER_INSTALL_STATIC_SYSTEMD
echo R007_REPORT="$REPORT"
echo R007_CLEAN_DEBIAN_VM=NOT_PERFORMED
