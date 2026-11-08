#!/usr/bin/env bash
# Explicit operator-only action: creates encrypted snapshot and optionally pushes GitHub.
set -Eeuo pipefail
umask 077
[[ "$(id -u)" == 0 ]] || { echo ROOT_REQUIRED; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ "$HERE" == /root/* && -f "$HERE/STAGING_SOURCE_PROVENANCE.json" ]] || { echo STAGING_NOT_READY; exit 2; }
SNAPSHOT='/root/forprint-disk-health-backups/disk-health-snapshot-20261108T193152Z/DISK_HEALTH_PRIVATE_FULL_20261108T193152Z.tar.gz'
SUM='8ad9e4d21a7498716b6f6cdb98f5edbfd066f781ca1cdf835d29c4f12b44a0f3'
CIPHER="$HERE/private-backup/DISK_HEALTH_PRIVATE_FULL_20261108T193152Z.tar.gz.gpg"
REMOTE='https://github.com/Kovalchuk-PrintMaster/System_Administrator_Dedian_HDD-SDD_Healht.git'
for cmd in sha256sum gpg git python3 bash; do command -v "$cmd" >/dev/null || { echo "MISSING=$cmd"; exit 3; }; done
printf '%s  %s\n' "$SUM" "$SNAPSHOT" | sha256sum -c - >/dev/null || { echo SNAPSHOT_MISSING_OR_CHANGED; exit 3; }
bash -n "$HERE/utils/disk_health_audit.sh" || exit 3
grep -Fxq 'TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"' "$HERE/utils/disk_health_audit.sh" || { echo SOURCE_NOT_SANITIZED; exit 3; }
if [[ ! -f "$CIPHER" ]]; then
  [[ -r /dev/tty ]] || { echo TTY_REQUIRED; exit 4; }
  echo 'Choose a unique passphrase of at least 10 characters. Keep it OFF the server and GitHub. Random characters are strongly recommended.'
  IFS= read -r -s -p 'GPG passphrase (hidden): ' PASS </dev/tty; echo
  IFS= read -r -s -p 'Repeat passphrase (hidden): ' PASS2 </dev/tty; echo
  if [[ "$PASS" != "$PASS2" ]]; then unset PASS PASS2; echo PASSPHRASE_MISMATCH; exit 4; fi
  if [[ ${#PASS} -lt 10 ]]; then unset PASS PASS2; echo PASSPHRASE_TOO_SHORT_MIN_10; exit 4; fi
  unset PASS2
  TMP="$CIPHER.tmp.$$"
  trap 'rm -f "${TMP:-}"; unset PASS PASS2' EXIT
  printf '%s\n' "$PASS" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 --output "$TMP" "$SNAPSHOT" 2>/dev/null || { echo ENCRYPT_FAILED;exit 4; }
  ACTUAL="$(printf '%s\n' "$PASS" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --decrypt "$TMP" 2>/dev/null | sha256sum | awk '{print $1}')"
  [[ "$ACTUAL" == "$SUM" ]] || { echo CIPHER_ROUNDTRIP_FAILED; exit 4; }
  chmod 600 "$TMP"; mv "$TMP" "$CIPHER"; unset PASS; trap - EXIT
fi
echo PRIVATE_ENCRYPTED=YES
echo "ENCRYPTED_SHA256=$(sha256sum "$CIPHER" | cut -d' ' -f1)"
if [[ "${1:-}" != --publish ]]; then echo 'NOT_PUSHED: re-run --publish when ready'; exit 0; fi
[[ -r /dev/tty ]] || { echo TTY_REQUIRED; exit 4; }
echo 'WARNING: The destination GitHub repository is PUBLIC. Only the encrypted backup will be pushed.'
printf 'Type PUBLISH to commit and push: '
IFS= read -r ACTION </dev/tty
[[ "$ACTION" == PUBLISH ]] || { echo PUBLISH_CANCELLED; exit 0; }
cd "$HERE"
if [[ ! -d .git ]]; then git init -b main >/dev/null; fi
if git remote get-url origin >/dev/null 2>&1; then
  [[ "$(git remote get-url origin)" == "$REMOTE" ]] || { echo REMOTE_MISMATCH;exit 5; }
else git remote add origin "$REMOTE"; fi
if [[ -z "$(git config user.name || true)" || -z "$(git config user.email || true)" ]]; then
  echo 'GIT_IDENTITY_REQUIRED: configure git user.name and user.email then rerun';exit 5
fi
git add -- .gitignore README.md STAGING_SOURCE_PROVENANCE.json \
  utils/disk_health_audit.sh config/disk-health-audit.env.example legacy/config_disk_health_audit_INACTIVE.sh \
  docs/*.md systemd/* scripts/*.sh scripts/restore_private_config.py private-backup/*.gpg
if git diff --cached --name-only | grep -E '(^logs/|^tmp/|^backups/|^config/disk-health-audit\.env$|\.tar\.gz$|\.zip$|\.pem$|\.key$)'; then
  echo PROHIBITED_PLAINTEXT_PATH; exit 6
fi
if git diff --cached --name-only | grep -E '^private-backup/' | grep -v -E '\.gpg$'; then echo PLAIN_BACKUP_BLOCKED;exit 6; fi
# Allow-listed token placeholders only. No values are displayed.
python3 - <<'PY'
from pathlib import Path
import re,sys
bad=[]
for parent in ['utils','legacy','docs']:
 for f in Path(parent).glob('*'):
  if not f.is_file():continue
  for line in f.read_text().splitlines():
   if '<REDACTED_KEY_VALUE>' in line:bad.append(str(f))
   if re.match(r'^\s*TELEGRAM_BOT_TOKEN=',line):
    value=line.partition('=')[2].strip()
    if value not in ['"${TELEGRAM_BOT_TOKEN:-}"','YOUR_BOT_TOKEN','""']:bad.append(str(f))
if bad:print('SUSPECT_SENSITIVE_FILES='+','.join(sorted(set(bad))));sys.exit(6)
PY
if ! git diff --cached --quiet; then git commit -m 'Recoverable Debian disk audit with encrypted snapshot' || exit 7; fi
git push -u origin main || { echo PUSH_FAILED_COMMIT_LOCAL_ONLY_NO_FORCE;exit 8; }
echo GITHUB_BACKUP_PUSH=PASS
git rev-parse HEAD
