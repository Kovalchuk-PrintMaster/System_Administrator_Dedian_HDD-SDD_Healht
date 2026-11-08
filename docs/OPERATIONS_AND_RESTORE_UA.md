# Паспорт встановлення та відновлення — 2026-11-08

## Фактичний стан `s01`

- ОС: Debian GNU/Linux 12 (bookworm).
- Програмний каталог: `/opt/forprint-utils/disk-health-audit/`; робочий скрипт: `utils/disk_health_audit.sh`.
- `systemd` файли з `/etc/systemd/system/`; користувач виконання `root`; `Type=oneshot`.
- `systemd` керує `short` / `long`. Не cron; `smartmontools.service` — окремий системний сервіс і до інсталятора цього проєкту не входить.
- `disk-health-audit-short.timer`: OnCalendar=`Sat *-*-* 14:00:00`; RandomizedDelaySec=`15m`; Persistent=`true`.
- `disk-health-audit-long.timer`: OnCalendar=`Sat *-*-01..07 14:00:00`; RandomizedDelaySec=`15m`; Persistent=`true`.
- 2026-11-07: останні зібрані спрацювання таймерів, екземпляри short/long мали `Result=success`, `ExecMainStatus=0`.
- Логи: `logs/runs/...`, `logs/latest`; 2026-11-08 — близько 13 МБ. Історія не потрібна для запуску, але потрібна для збереження попередніх станів.
- Існує **другий файл** `config/disk_health_audit.sh`; він не викликається systemd, старіший, із синтаксичною помилкою (у сирій версії REVIEW після заміни редакції токена). Архівна копія зберігається у `legacy/`.
- Початковий snapshot: `DISK_HEALTH_PRIVATE_FULL_20261108T193152Z.tar.gz` SHA-256 `8ad9e4d21a7498716b6f6cdb98f5edbfd066f781ca1cdf835d29c4f12b44a0f3`. Зберігається окремо до його шифрування та перенесення за межі сервера.

## Паролі, токени та дані

1. Публічний Git містить лише очищені джерела та **зашифровану копію** приватного snapshot (якщо оператор її додав).
2. Конфігурація містить `TELEGRAM_BOT_TOKEN` та інші приватні поля; відновлюйте її лише з зашифрованої копії, **не з шаблона**, якщо треба точно зберегти сповіщення.
3. Пароль до GPG запишіть **поза GitHub і поза сервером** у надійному менеджері паролів. Без нього повний snapshot не відновити. Втрата пароля означає втрату приватної частини резервної копії.
4. Якщо токен був жорстко прописаний у вихідному коді, важливо перевірити, що ефективне значення токена перенесено в `.env`. Сам факт наявності відповідного ключа у `.env` не гарантує однакового значення. Скрипт публікації НЕ підтверджує еквівалентність приватної конфігурації.
5. Дані дисків, серійні номери, топологія та історичні журнали зберігаються лише в зашифрованій копії.

## Відновлення приватної конфігурації

Коли в клоні є `private-backup/*.gpg`:

```bash
umask 077
mkdir -p /root/disk-health-restore-private
# GPG попросить пароль; тимчасовий архів залишається лише в /root.
gpg --output /root/disk-health-restore-private/full.tar.gz \
  --decrypt /root/disk-health-restore/private-backup/DISK_HEALTH_PRIVATE_FULL_20261108T193152Z.tar.gz.gpg
sha256sum /root/disk-health-restore-private/full.tar.gz
# Очікується 8ad9e4d21a7498716b6f6cdb98f5edbfd066f781ca1cdf835d29c4f12b44a0f3
# Перегляньте структуру архіву; не розпаковуйте сліпо поверх системи.
tar -tzf /root/disk-health-restore-private/full.tar.gz | head -n 30
```

Після виконання `scripts/install_restore.sh --apply` відновіть `.env` **без перезапису існуючих даних**:

```bash
python3 /root/disk-health-restore/scripts/restore_private_config.py \
 --archive /root/disk-health-restore-private/full.tar.gz
# За потреби відновлення журналів замість попереднього запуску додайте --restore-logs.
```

Скрипт перевіряє SHA-256 архіву та `.env`, відмовляється від небезпечних шляхів і ніколи не запускає SMART-тести. Не розпаковуйте tar цілком поверх `/etc` або `/root`. Після відновлення видаліть тимчасовий розшифрований файл. Зверніть увагу: якщо токен у вихідному робочому коді відрізнявся від `.env`, еквівалентність Telegram потребує окремої перевірки.

## Безпечне вмикання таймерів

1. Перед активацією перевірити диски, конфігурацію і вікно часу: `systemd-analyze calendar 'Sat *-*-* 14:00:00'` і `'Sat *-*-01..07 14:00:00'`.
2. `systemctl cat disk-health-audit@.service disk-health-audit-short.timer disk-health-audit-long.timer`.
3. `systemctl is-enabled disk-health-audit-short.timer disk-health-audit-long.timer`.
4. Після явного рішення оператора `scripts/install_restore.sh --enable-timers`.
5. `systemctl list-timers --all | grep disk-health-audit`; `journalctl -u disk-health-audit@short.service -n 50 --no-pager`.
6. Не запускати `short` або `long` вручну лише заради smoke-тесту після відновлення: це реальні SMART-тести. Опціональний `collect` — за дозволом оператора.

## Оновлення копії

Нові релізи — окремі коміти. За зміни `.env` або історії потрібен новий зашифрований snapshot. Не додавати plaintext `.env`, `logs/`, приватний архів без шифрування, SSH-ключі чи `.git` із production у репозиторій. Перевіряти `git ls-files` перед push.
