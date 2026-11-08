#!/usr/bin/env python3
"""Restore a pinned private env and optional logs from a decrypted trusted snapshot.
Does not touch systemd; refuses to overwrite existing env or log files.
"""
import argparse,hashlib,os,pathlib,re,sys,tarfile
EXPECTED_ARCHIVE_SHA='8ad9e4d21a7498716b6f6cdb98f5edbfd066f781ca1cdf835d29c4f12b44a0f3'
EXPECTED_ENV_SHA='74e1187a7c417cd1ab48382872c8b855c3080fc165255cf017f489fe838af97c'
TARGET=pathlib.Path('/opt/forprint-utils/disk-health-audit')
def sha(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()
def safe_name(name):
 p=pathlib.PurePosixPath(name)
 return not p.is_absolute() and '..' not in p.parts and '\\' not in name and '\x00' not in name

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--archive',type=pathlib.Path,required=True,help='Decrypted full.tar.gz in /root')
 parser.add_argument('--restore-logs',action='store_true',help='Also restore 2026 historical logs (no overwrite)')
 args=parser.parse_args()
 if os.geteuid()!=0:sys.exit('ROOT_REQUIRED')
 if args.archive.is_symlink() or not args.archive.is_file() or sha(args.archive)!=EXPECTED_ARCHIVE_SHA:
  sys.exit('INVALID_OR_UNPINNED_PRIVATE_ARCHIVE')
 env_dest=TARGET/'config/disk-health-audit.env'
 if not TARGET.is_dir() or not env_dest.parent.is_dir():sys.exit('INSTALL_FIRST')
 if env_dest.exists() or env_dest.is_symlink():sys.exit('EXISTING_ENV_REFUSE_OVERWRITE')
 with tarfile.open(args.archive,'r:gz') as tar:
  members=tar.getmembers()
  if any(not safe_name(m.name) for m in members):sys.exit('UNSAFE_MEMBER_PATH')
  envs=[m for m in members if m.isfile() and m.name.endswith('/config/disk-health-audit.env')]
  if len(envs)!=1:sys.exit(f'ENV_CANDIDATE_COUNT={len(envs)}')
  source=tar.extractfile(envs[0]);data=source.read() if source else b''
  if hashlib.sha256(data).hexdigest()!=EXPECTED_ENV_SHA:sys.exit('ENV_CONTENT_HASH_MISMATCH')
  old=os.umask(0o077)
  try:
   fd=os.open(str(env_dest),os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
   with os.fdopen(fd,'wb') as f:f.write(data)
   os.chmod(env_dest,0o600)
  finally:os.umask(old)
  print('PRIVATE_ENV_RESTORED=PASS_0600')
  if args.restore_logs:
   log_root=TARGET/'logs/runs';log_root.mkdir(mode=0o750,parents=True,exist_ok=True)
   log_files=[]
   for m in members:
    parts=pathlib.PurePosixPath(m.name).parts
    for i in range(len(parts)-2):
     if parts[i:i+2]==('logs','runs') and m.isfile():
      rest=parts[i+2:]
      if len(rest)>=2 and all(re.fullmatch(r'[A-Za-z0-9_.-]+',piece) for piece in rest) and m.size<=100*1024*1024:
       log_files.append((m,rest))
      break
   count=0
   for m,rest in log_files:
    dest=log_root.joinpath(*rest)
    dest.parent.mkdir(mode=0o750,parents=True,exist_ok=True)
    if dest.exists() or dest.is_symlink():sys.exit('EXISTING_LOG_REFUSE_OVERWRITE')
    content=tar.extractfile(m)
    if content is None:continue
    fd=os.open(str(dest),os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o640)
    with os.fdopen(fd,'wb') as out:
     for block in iter(lambda:content.read(1024*1024),b''):out.write(block)
    count+=1
   # Do not restore links from tar, because symlink paths are a frequent hazard.
   print(f'PRIVATE_LOG_FILES_RESTORED={count}')
 print('NO_SERVICE_OR_SMART_TEST_STARTED=TRUE')
if __name__=='__main__':main()
