# disk-health-audit

Скрипт для регулярного контролю стану дисків через SMART з історією запусків, читабельним summary, технічним summary, Telegram-сповіщеннями та запуском через systemd timer.

## Призначення

`disk_health_audit.sh` автоматизує регулярну перевірку дисків і дає три рівні результату:

1. **короткий людський summary** для швидкого перегляду;
2. **технічний summary** для діагностики;
3. **machine-readable state** (`disk_state.tsv`) для подальшого аналізу або інтеграції.

Скрипт спроєктований так, щоб:
- не падати через один проблемний диск;
- не вимагати ручного втручання на кожному запуску;
- бути переносимим між серверами;
- мати достатньо документації для відновлення або переписування під іншу ОС.

---

## Поточна структура проекту

```text
/opt/forprint-utils/disk-health-audit/
├── utils/
│   └── disk_health_audit.sh
├── config/
│   └── disk-health-audit.env
├── docs/
│   ├── README.md
│   ├── TECHNICAL.md
│   └── RECOVERY_AND_PORTING_SPEC.md
├── systemd/
│   ├── disk-health-audit@.service
│   ├── disk-health-audit-short.timer
│   └── disk-health-audit-long.timer
└── logs/
    ├── latest -> ./runs/YYYY-MM-DD_HH-MM-SS
    └── runs/
        └── YYYY-MM-DD_HH-MM-SS/
```

---

## Що робить скрипт

Скрипт виконує повний цикл:

1. перевіряє root-доступ;
2. бере lock, щоб не було паралельних запусків;
3. підвантажує `env`, якщо він існує;
4. готує каталог нового запуску;
5. очищає старі каталоги звітів за retention-політикою;
6. знаходить усі block devices типу `disk`;
7. у режимах `short` / `long` запускає SMART self-test;
8. збирає по кожному диску:
   - `smartctl -i`
   - `smartctl -c`
   - `smartctl -A`
   - `smartctl -l selftest`
   - `smartctl -l error`
   - `smartctl -x`
9. формує `disk_state.tsv`;
10. формує `summary_user.txt`;
11. формує `summary_assistant.txt`;
12. за потреби відправляє короткий summary і `summary_user.txt` у Telegram.

---

## Режими роботи

### `install`
Ставить залежності і завершується.

### `collect`
Не запускає активний self-test. Лише збирає поточний стан.

### `short`
Запускає короткий SMART self-test, чекає завершення і формує звіт.

### `long`
Запускає довгий SMART self-test, чекає завершення і формує звіт.

---

## Базові приклади запуску

```bash
sudo bash /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh install
sudo bash /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh collect
sudo bash /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh short
sudo bash /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh long
```

Лише один диск:

```bash
sudo bash /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh collect --disk /dev/sda
```

---

## Що лежить у `logs/runs/<timestamp>/`

Кожен запуск створює окремий каталог, наприклад:

```text
logs/runs/2026-04-15_19-39-18/
```

Типовий вміст:

- `inventory.txt`
- `kernel_disk_logs.txt`
- `disk_state.tsv`
- `mounts.tsv`
- `*_smart_info.txt`
- `*_smart_caps.txt`
- `*_smart_attr.txt`
- `*_selftest.txt`
- `*_errorlog.txt`
- `*_smart_full.txt`
- `summary_user.txt`
- `summary_assistant.txt`
- `telegram_message.txt`
- `telegram_sendMessage.*`
- `telegram_sendDocument.*`

Симлінк `logs/latest` завжди вказує на останній запуск.

---

## Формат `disk_state.tsv`

Поточний формат колонок:

```text
disk_path
serial
model
size
transport
label
uuid
status
selftest_start_status
selftest_start_reason
reallocated
pending
offline_uncorrectable
crc
power_on_hours
device_error_count
last_selftest
overall_health
fs_total
fs_free
fs_free_pct
fs_space_status
```

Це головний проміжний формат, із якого будуються:
- `summary_user.txt`
- `telegram_message.txt`

---

## Статуси

### Health status
Базується на SMART-даних:

- `OK`
- `WARNING`
- `CRITICAL`

Приклади логіки:
- `CRITICAL`, якщо є `Pending > 0`, `Offline_Uncorrectable > 0` або SMART FAIL;
- `WARNING`, якщо росте `Reallocated`, `CRC` або `Device Error Count`;
- інакше `OK`.

### Free space status
Окремий незалежний статус:

- `OK` — вільно більше 50%;
- `WARNING` — від 25% до 50%;
- `CRITICAL` — менше 25%;
- `N/A` — немає придатного mountpoint або не вдалося порахувати.

### Self-test status
- `STARTED`
- `NOT_STARTED`
- `SKIPPED`
- `COLLECT_ONLY`
- `N/A`

У режимі `collect` правильний статус — `COLLECT_ONLY`.

---

## Як читати `summary_user.txt`

Summary зроблений так, щоб його можна було швидко читати очима.

### Верхній блок
Містить:
- host
- дату
- mode
- каталог звіту
- посилання на попередній `disk_state.tsv`
- окремі summary-блоки:
  - `Health summary`
  - `Free space summary`
  - `Self-test summary`

### Блок по кожному диску
Містить:
- статус із іконкою:
  - 🟢
  - 🟡
  - 🔴
  - ⚪
- модель
- serial
- path
- LABEL
- UUID
- SMART overall health
- self-test status + reason
- ключові SMART-лічильники
- free space
- last self-test
- короткі примітки
- висновок

---

## Telegram

Якщо `TELEGRAM_ENABLED=yes`, скрипт:
1. створює `telegram_message.txt`;
2. надсилає короткий текстовий summary;
3. прикріплює `summary_user.txt`, якщо це дозволено налаштуваннями.

Поточний Telegram summary містить:
- host
- mode
- date
- `Health`
- `Free space`
- `Self-test`
- короткий блок по кожному диску:
  - status
  - LABEL
  - serial
  - path
  - SMART / SPACE / SELFTEST

---

## Конфігурація через `config/disk-health-audit.env`

Скрипт **самодостатній**: усі основні дефолти зберігаються в коді.  
`env` потрібен лише для перевизначення параметрів.

Приклад:

```bash
# Основні параметри
POLL_SEC=20
STAGGER_SEC=5
MAX_WAIT_MINUTES=0
SKIP_SYSTEM_DISK=no
AUTO_INSTALL=yes

# Retry старту self-test
SELFTEST_START_RETRIES=3
SELFTEST_START_RETRY_DELAY=5

# Шляхи
PROJECT_ROOT=/opt/forprint-utils/disk-health-audit
LOGS_DIR=/opt/forprint-utils/disk-health-audit/logs

# Retention
RUNS_CLEANUP_ENABLED=yes
RUNS_RETENTION_DAYS=180

# Telegram
TELEGRAM_ENABLED=yes
TELEGRAM_SEND_DOCUMENT=yes
TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN
TELEGRAM_CHAT_ID=
TELEGRAM_API_URL=https://api.telegram.org
TELEGRAM_DISABLE_NOTIFICATION=true
```

Пріоритет налаштувань:
1. CLI
2. `env`
3. дефолти в коді

---

## Автоматичний запуск через systemd

### Сервіс
Використовується шаблонний service:

- `disk-health-audit@collect.service`
- `disk-health-audit@short.service`
- `disk-health-audit@long.service`

### Таймери
Поточна схема:

#### Weekly short
```ini
[Unit]
Description=Run disk health audit short weekly

[Timer]
OnCalendar=Sat *-*-* 14:00:00
Persistent=true
RandomizedDelaySec=15m
Unit=disk-health-audit@short.service

[Install]
WantedBy=timers.target
```

#### Monthly long
```ini
[Unit]
Description=Run disk health audit long monthly

[Timer]
OnCalendar=Sat *-*-01..07 14:00:00
Persistent=true
RandomizedDelaySec=15m
Unit=disk-health-audit@long.service

[Install]
WantedBy=timers.target
```

`Persistent=true` означає: якщо сервер був вимкнений у момент запуску, systemd надолужить пропущений запуск після ввімкнення.

---

## Корисні команди

Перевірка синтаксису:

```bash
bash -n /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh
```

Разовий `collect`:

```bash
systemctl start disk-health-audit@collect.service
journalctl -u disk-health-audit@collect.service -n 120 -l --no-pager
```

Живий перегляд:

```bash
journalctl -u disk-health-audit@short.service -f -l
```

Останній summary:

```bash
cat /opt/forprint-utils/disk-health-audit/logs/latest/summary_user.txt
cat /opt/forprint-utils/disk-health-audit/logs/latest/telegram_message.txt
```

Таймери:

```bash
systemctl list-timers --all | grep disk-health-audit
```

---

## Відомі практичні особливості

1. USB-SATA bridge може:
   - не давати повний SMART;
   - не дозволяти запускати self-test;
   - повертати `SMART health line not found`.
2. Для окремих дисків частина SMART-лічильників може бути `N/A`.
3. `Free space` рахується по знайдених mountpoint'ах піддерева диска.
4. У `collect` self-test не запускається навмисно.
5. Один проблемний диск не повинен ламати повний запуск.

---

## Якщо треба відновити або перенести
Для відновлення скрипта з нуля або переписування під іншу ОС використовуй:

- `docs/RECOVERY_AND_PORTING_SPEC.md`

Це не просто опис користування, а саме функціональна специфікація відновлення.

---

## Короткий висновок

Поточна версія — це вже повноцінний utility-проєкт із:
- history-based логікою;
- resilient-поведінкою;
- окремим state-файлом;
- читабельними summary;
- Telegram-інтеграцією;
- weekly/monthly systemd-таймерами;
- документацією, достатньою для реконструкції.
