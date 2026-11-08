# TECHNICAL.md — disk-health-audit

Технічна документація по внутрішній логіці `disk_health_audit.sh`.

## 1. Загальна схема виконання

Порядок роботи:

1. `ensure_root()`
2. `acquire_lock()`
3. `parse_args()`
4. `install_dependencies()` — якщо дозволено
5. `init_report_dir()`
6. `cleanup_old_runs()`
7. `write_inventory()`
8. `write_kernel_logs()`
9. `write_state_headers()`
10. `discover_disks()`
11. у `short/long`:
    - `start_selftest()`
    - `wait_for_started_tests_to_finish()`
12. `collect_for_disk()` для кожного диска
13. `write_user_summary()`
14. `write_assistant_summary()`
15. `send_telegram_report()`

---

## 2. Ключові функції

### `discover_disks()`
Шукає всі `lsblk ... TYPE=disk`.

Підтримує:
- список конкретних дисків через `ONLY_DISKS`;
- пропуск системного диска через `SKIP_SYSTEM_DISK`.

### `start_selftest()`
Запускає `smartctl -t short|long`.

Особливості:
- робить retry (`SELFTEST_START_RETRIES`);
- не валить увесь запуск, якщо один диск не стартує;
- зберігає per-disk статус:
  - `STARTED`
  - `NOT_STARTED`
  - `SKIPPED`

### `wait_for_started_tests_to_finish()`
Опитує статус уже запущених тестів через `smartctl -c`.

Особливості:
- чекає лише диски зі статусом `STARTED`;
- не чіпає `NOT_STARTED` / `SKIPPED`;
- використовує `POLL_SEC`.

### `collect_for_disk()`
Збирає всі необхідні smart-файли і потім викликає `append_state_row()`.

### `append_state_row()`
Формує один рядок `disk_state.tsv`.

Особливості:
- включає ідентифікацію:
  - path
  - serial
  - model
  - transport
  - label
  - uuid
- включає health-поля;
- включає self-test поля;
- включає free-space поля;
- у режимі `collect` виставляє:
  - `selftest_start_status=COLLECT_ONLY`
  - `selftest_start_reason=self-test not started in collect mode`

### `write_user_summary()`
Будує читабельний summary.

Особливості:
- окремо рахує:
  - `Health summary`
  - `Free space summary`
  - `Self-test summary`
- показує per-disk блоки;
- підтягує попередній `disk_state.tsv` для delta по SMART-лічильниках.

### `write_assistant_summary()`
Будує технічний звіт для глибокої діагностики.

### `build_telegram_message()`
Формує короткий текст для Telegram з окремими summary-блоками й коротким списком дисків.

### `send_telegram_report()`
Виконує:
- `sendMessage`
- `sendDocument`

---

## 3. Формат `disk_state.tsv`

Колонки повинні йти саме в такому порядку:

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

### Важлива примітка
Summary і Telegram напряму залежать від цього порядку.  
Якщо змінити схему колонок без синхронного оновлення `write_user_summary()` та `build_telegram_message()`, формат зламається.

---

## 4. Health evaluation

`assess_disk_state()` працює за правилами:

### `CRITICAL`
- SMART overall містить `FAIL/BAD/FAILED`
- `Current_Pending_Sector > 0`
- `Offline_Uncorrectable > 0`
- останній self-test має важкий failure

### `WARNING`
- `Reallocated_Sector_Ct > 0`
- `UDMA_CRC_Error_Count > 0`
- `Device Error Count > 0`

### `OK`
- якщо нічого з переліченого вище не спрацювало

---

## 5. Free space evaluation

### Джерело даних
Free space рахується по mountpoint'ах піддерева конкретного диска.

### Правила
- `OK`, якщо `free_pct > 50`
- `WARNING`, якщо `25 <= free_pct <= 50`
- `CRITICAL`, якщо `free_pct < 25`
- `N/A`, якщо не знайдено придатних mountpoint'ів

### Потенційні особливості
- USB-диск без активного mountpoint може давати `N/A`
- RAID/LVM/нестандартні шари можуть вимагати адаптації логіки для конкретної ОС

---

## 6. Self-test status model

Модель статусів:

- `STARTED`
- `NOT_STARTED`
- `SKIPPED`
- `COLLECT_ONLY`
- `N/A`

### Логіка
- `short/long` можуть виставляти `STARTED`, `NOT_STARTED`, `SKIPPED`
- `collect` завжди виставляє `COLLECT_ONLY`
- `N/A` лишається fallback-варіантом для непередбачених випадків

---

## 7. Принцип стійкості до проблемних дисків

Система спроєктована з таким принципом:

> один проблемний диск не повинен зупинити повний запуск по всіх інших дисках

Це реалізовано через:
- retry на старт self-test;
- окремий per-disk статус;
- масиви `SELFTEST_START_STATUS` і `SELFTEST_START_REASON`;
- толерантне збирання smartctl-виводів (`|| true` там, де це потрібно);
- `collect` як безпечний пасивний режим.

---

## 8. Логи прогресу

Логи мають stage-формат:

- `1/7 Підготовка середовища`
- `2/7 Інвентаризація системи`
- `3/7 Збір системних логів по дисках`
- `4/7 Підготовка state-файлів`
- `5/7 Старт self-test`
- `6/7 Очікування завершення`
- `6/7 Збір SMART-звітів`
- `7/7 Формування підсумків`

Per-disk прогрес:
- `[SELFTEST n/N] ...`
- `[COLLECT n/N] ...`

Це спроєктовано так, щоб:
- читалося у `journalctl`;
- читалося у `systemctl status`;
- було зрозуміло в ручному запуску.

---

## 9. Конфігурація

### Дефолти в коді
Скрипт має бути працездатним без зовнішнього `env`.

### `env`
Використовується для перевизначення:
- polling / stagger;
- retry;
- retention;
- Telegram;
- кореневих шляхів.

### Пріоритет
1. CLI
2. env
3. defaults in code

---

## 10. Systemd-архітектура

### Service
Використовується шаблонний oneshot-service.

Причина `Type=oneshot`:
- скрипт не daemon;
- він стартує, виконує повний цикл і завершується.

`inactive (dead)` після успішного виконання — це нормальний стан.

### Timer
Поточна схема:
- weekly short
- monthly long

---

## 11. Мінімальний smoke-test після змін

```bash
bash -n /opt/forprint-utils/disk-health-audit/utils/disk_health_audit.sh
systemctl start disk-health-audit@collect.service
journalctl -u disk-health-audit@collect.service -n 120 -l --no-pager
cat /opt/forprint-utils/disk-health-audit/logs/latest/summary_user.txt
cat /opt/forprint-utils/disk-health-audit/logs/latest/telegram_message.txt
```

Для `short`:

```bash
systemctl start disk-health-audit@short.service
journalctl -u disk-health-audit@short.service -f -l
```

---

## 12. Відомі обмеження

1. Частина USB-SATA bridge не дає повного SMART.
2. Не всі диски віддають однаковий набір атрибутів.
3. На не-Debian/Ubuntu auto-install потрібно адаптувати.
4. Для складних storage stack (mdraid/LVM/ZFS) окремі частини можуть потребувати кастомної логіки.
5. Будь-яка зміна схеми `disk_state.tsv` вимагає синхронного оновлення summary-функцій.

---

## 13. Короткий технічний висновок

Ця версія вже має правильну операційну архітектуру:

- окремий state layer;
- окремий user summary;
- окремий assistant summary;
- окремий telegram renderer;
- стійкість до частково проблемних дисків;
- weekly/monthly orchestration через systemd.

Тобто скрипт уже можна вважати стабільною робочою базою.
