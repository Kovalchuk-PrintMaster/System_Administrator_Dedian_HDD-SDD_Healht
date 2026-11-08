# Debian Disk Health Audit — відновлюваний комплект

Це джерела та інфраструктура для **існуючого** сервісу на Debian 12; не нова реалізація SMART-тестів.

## Робоча схема, підтверджена 2026-11-08

- `systemd/disk-health-audit@.service` запускає `utils/disk_health_audit.sh %i` як **root**.
- `disk-health-audit-short.timer`: щосуботи `14:00`, випадкова затримка до 15 хв.
- `disk-health-audit-long.timer`: **перша субота місяця** `14:00`, випадкова затримка до 15 хв.
- Обидва таймери: `Persistent=true`. Після ввімкнення пропущені тести можуть запуститися негайно.
- Звіти: `logs/runs/<timestamp>/`; `logs/latest` — символічне посилання на поточний/останній запуск.
- `smartmontools` (`smartctl`), `util-linux`, `gawk`, `curl` та стандартні утиліти — залежності.
- Додаткові режими: `collect` (без запуску активного self-test), `short`, `long`, `install`.

## Межі резервної копії

**Відкриті файли репозиторію:** `utils/`, `systemd/`, `docs/`, шаблон `config/*.example`, інсталятор і перевірки. У `legacy/` збережено копію старого скрипту; вона мала помилку синтаксису і не використовується сервісом.

**Приватні файли:** справжній `config/disk-health-audit.env`, системні дані та історія `logs/` **не зберігаються відкритим текстом у Git**. За окремої дії оператора додається `private-backup/DISK_HEALTH_PRIVATE_FULL_*.tar.gz.gpg` — зашифрована версія повного серверного snapshot. Для відновлення потрібен пароль шифрування, **не передавати його у чат чи репозиторій**.

Скрипт `utils/disk_health_audit.sh` перенесено з архіву REVIEW і змінено **лише** присвоєння токена Telegram на `TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"`, щоб джерело не містило секрету. Перед випуском скрипт `prepare_repository.py` обов'язково перевіряє еквівалентність решти коду реальному файлу на сервері. Це підтверджує структуру, але не тестує диск.

## Після перевстановлення Debian (ручна контрольована процедура)

1. Встановити `git`, `smartmontools`, `util-linux`, `gawk`, `curl`, `grep`, `sed`, `coreutils`, `findutils`, `procps` та `gnupg` за потреби.
2. `git clone https://github.com/Kovalchuk-PrintMaster/System_Administrator_Dedian_HDD-SDD_Healht.git /root/disk-health-restore`
3. `bash /root/disk-health-restore/scripts/install_restore.sh --dry-run` — лише перевірка.
4. `bash /root/disk-health-restore/scripts/install_restore.sh --apply` — інсталяція **без ввімкнення** таймерів. Нічого не перезаписує в уже встановленій програмі.
5. Відновити **приватну** `env` із зашифрованого snapshot (див. `docs/OPERATIONS_AND_RESTORE_UA.md`, команда `python3 scripts/restore_private_config.py --archive /root/disk-health-restore-private/full.tar.gz`) до нового каталогу `config/` і перевірити відповідність Telegram/дисків/шляхів.
6. Після ручної перевірки конфігурації та календаря: `bash /root/disk-health-restore/scripts/install_restore.sh --enable-timers` — окрема явна активація; `Persistent=true` може запустити пропущені тести.
7. `bash /root/disk-health-restore/scripts/verify_restore.sh` і `systemctl list-timers --all | grep disk-health-audit`.

**Безпека:** команда `collect` збирає SMART без запуску нових self-test, але створює журнали й читає диски; не входить до автоматичного інсталятора. `short/long` може навантажувати накопичувачі. Відновлення `logs/` необов'язкове для запуску, але потрібне для історичних порівнянь.

`docs/README_disk_health_audit.md`, `docs/TECHNICAL_disk_health_audit.md` і `docs/RECOVERY_AND_PORTING_SPEC_disk_health_audit.md` збережено для опису функціональності, при цьому деякі старі приклади шляхів відрізняються від фактичних і мають менший пріоритет, ніж цей README.
