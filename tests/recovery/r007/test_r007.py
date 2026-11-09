#!/usr/bin/env python3
"""Static and package self-tests (do not require Docker or internet)."""
import pathlib, re, subprocess, unittest
ROOT=pathlib.Path(__file__).resolve().parent
class R007Tests(unittest.TestCase):
    def test_run_bash_syntax(self):
        for name in ('run_once.sh','r007_container_acceptance.sh'):
            subprocess.run(['bash','-n',str(ROOT/name)],check=True,capture_output=True)
    def test_pinned_commit(self):
        self.assertIn('dcd164fb6b40eea2de7d6ddc2469bbb17d6ccb1e', (ROOT/'run_once.sh').read_text())
    def test_encrypted_checksum_pinned(self):
        self.assertIn('130d95aaa3b8c733e350b7db9b901025eb783968ef6860f32f914e58878ab629', (ROOT/'run_once.sh').read_text())
    def test_debian12_base(self):
        self.assertRegex((ROOT/'Dockerfile').read_text(),r'(?m)^FROM debian:12-slim$')
    def test_no_privileged_or_host_mount(self):
        s=(ROOT/'run_once.sh').read_text()
        self.assertIn('--network=none',s)
        self.assertIn('--cap-drop=ALL',s)
        self.assertIn('--security-opt=no-new-privileges',s)
        self.assertNotIn('--privileged',s)
        docker_run = s.split('docker run --rm', 1)[1].split('>"$TMP/acceptance.log"', 1)[0]
        self.assertNotRegex(docker_run, r'--(?:volume|mount)\b|(?:\s-v\s)')
    def test_no_production_script_execution(self):
        s=(ROOT/'run_once.sh').read_text()
        self.assertNotIn('systemctl enable',s)
        self.assertNotIn('smartctl -t',s)
        self.assertNotIn('install_restore.sh --apply',s)
    def test_mock_only_reload(self):
        s=(ROOT/'r007_container_acceptance.sh').read_text()
        self.assertIn('"$1" == daemon-reload',s)
        self.assertIn('R007_FORBIDDEN_SYSTEMCTL_ACTION=BLOCKED',s)
        self.assertIn('R007_SYSTEMD_PID1=NOT_TESTED',s)
    def test_installation_and_guard_are_checked(self):
        s=(ROOT/'r007_container_acceptance.sh').read_text()
        for t in ('--dry-run','--apply','--enable-timers','NO_PRIVATE_CONFIG','cmp -s','systemd-analyze verify'):
            self.assertIn(t,s)
    def test_real_private_not_copied_as_plaintext(self):
        s=(ROOT/'run_once.sh').read_text()
        self.assertNotIn('gpg --decrypt',s)
        self.assertNotIn('TELEGRAM_BOT_TOKEN=',s)
    def test_docker_info_ostype_field_is_top_level(self):
        s=(ROOT/'run_once.sh').read_text()
        self.assertIn("docker info --format '{{.OSType}}'",s)
        self.assertNotIn('.Server.OSType',s)

    def test_docker_preflight_accepts_linux_and_rejects_wrong_os(self):
        s=(ROOT/'run_once.sh').read_text()
        section=s.split("echo '=== R007 DOCKER PREFLIGHT ==='",1)[1].split('\nTMP=',1)[0]
        for os_type, ok in [('linux',True),('windows',False),('',False)]:
            stub=(
                'docker() { '
                'if [[ "$#" == 3 && "$1" == info && "$2" == --format && "$3" == "{{.OSType}}" ]]; then '
                f'printf "%s\\n" "{os_type}"; '
                'else return 7; fi; }\n'
            )
            result=subprocess.run(['bash','-c','set -Eeuo pipefail\n'+stub+section],capture_output=True,text=True)
            self.assertEqual(result.returncode==0,ok,(os_type,result.stdout,result.stderr))
            self.assertIn('R007_DOCKER_DAEMON=PASS_LINUX' if ok else 'R007_DOCKER_DAEMON=UNAVAILABLE_OR_NOT_LINUX',result.stdout)

    def test_exit_status_is_verified(self):
        s=(ROOT/'run_once.sh').read_text()
        self.assertIn('[[ $rc -ne 0 ]]',s)
        self.assertIn('R007_CONTAINER_ACCEPTANCE=PASS',s)
if __name__=='__main__':unittest.main()
