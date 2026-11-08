# RECOVERY_AND_PORTING_SPEC.md

Цей документ — специфікація відновлення або переписування `disk_health_audit.sh` з нуля.

Мета:
- мати достатньо інформації, щоб повністю відтворити функціонал;
- мати мапу залежностей і поведінки;
- мати орієнтир для порту на іншу ОС.

---

## 1. Функціональні вимоги

Майбутня реалізація повинна:

1. запускатися від root;
2. не дозволяти паралельні копії одного й того ж запуску;
3. працювати в режимах:
   - `install`
   - `collect`
   - `short`
   - `long`
4. автоматично знаходити диски;
5. вміти обмежуватися списком дисків;
6. опційно пропускати системний диск;
7. формувати окремий каталог звіту на кожен запуск;
8. підтримувати retention старих запусків;
9. збирати SMART по кожному диску;
10. формувати machine-readable state-файл;
11. формувати user summary;
12. формувати technical summary;
13. надсилати короткий summary в Telegram;
14. не падати через один проблемний диск;
15. мати видимий поетапний прогрес у логах.

---

## 2. Обов’язкові режими

### `install`
- перевіряє наявність залежностей;
- за потреби встановлює їх;
- завершується.

### `collect`
- не запускає active self-test;
- лише збирає SMART і стан.

### `short`
- запускає `smartctl -t short`;
- чекає завершення активних тестів;
- збирає звіти.

### `long`
- запускає `smartctl -t long`;
- чекає завершення активних тестів;
- збирає звіти.

---

## 3. Мінімальний набір зовнішніх залежностей

Для Linux-реалізації потрібні аналоги таких утиліт:

- `bash`
- `smartctl`
- `lsblk`
- `findmnt`
- `flock`
- `awk`
- `grep`
- `sed`
- `date`
- `dmesg`
- `journalctl`
- `curl`
- `df`
- `numfmt`

---

## 4. Мінімальна структура директорій

```text
PROJECT_ROOT/
├── utils/
├── config/
├── docs/
├── systemd/
└── logs/
    ├── latest
    └── runs/
```

---

## 5. Обов’язкові вихідні файли запуску

Кожен запуск повинен створювати:

- `inventory.txt`
- `kernel_disk_logs.txt`
- `disk_state.tsv`
- `mounts.tsv`
- `summary_user.txt`
- `summary_assistant.txt`

Per-disk:
- `*_smart_info.txt`
- `*_smart_caps.txt`
- `*_smart_attr.txt`
- `*_selftest.txt`
- `*_errorlog.txt`
- `*_smart_full.txt`

Для Telegram:
- `telegram_message.txt`

---

## 6. Формат `disk_state.tsv`

Формат повинен бути стабільним:

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

### Вимога
Порядок колонок має бути фіксований.
Будь-який renderer summary повинен очікувати саме цей порядок або мати явну схему мапінгу.

---

## 7. Обов’язкові статуси

### Health status
- `OK`
- `WARNING`
- `CRITICAL`

### Free space status
- `OK`
- `WARNING`
- `CRITICAL`
- `N/A`

### Self-test status
- `STARTED`
- `NOT_STARTED`
- `SKIPPED`
- `COLLECT_ONLY`
- `N/A`

---

## 8. Правила оцінки health

Обов’язкові сигнали:

- SMART overall health
- `Reallocated_Sector_Ct`
- `Current_Pending_Sector`
- `Offline_Uncorrectable`
- `UDMA_CRC_Error_Count`
- `Power_On_Hours`
- `Device Error Count`
- останній self-test

### Мінімальні правила
- `CRITICAL`:
  - SMART FAIL/BAD
  - pending > 0
  - offline_uncorrectable > 0
  - важка помилка в last self-test
- `WARNING`:
  - reallocated > 0
  - crc > 0
  - device error count > 0
- інакше `OK`

---

## 9. Правила оцінки free space

### Вхідні дані
Потрібно визначити сумарний `size` і `available` по всіх mountpoint'ах, що належать піддереву конкретного диска.

### Правила
- `free_pct > 50` → `OK`
- `25 <= free_pct <= 50` → `WARNING`
- `free_pct < 25` → `CRITICAL`
- якщо mountpoint'и не знайдено → `N/A`

---

## 10. Правила self-test

### Для `short/long`
Для кожного диска:
1. перевірити, чи вже активний self-test;
2. за потреби дочекатися його завершення;
3. спробувати стартувати новий тест;
4. зробити retry;
5. якщо старт не вдався:
   - не валити повний запуск;
   - записати `NOT_STARTED` або `SKIPPED`.

### Для `collect`
Не запускати self-test.
Писати:
- `selftest_start_status=COLLECT_ONLY`
- `selftest_start_reason=self-test not started in collect mode`

---

## 11. Принцип стійкості

Система повинна бути tolerant до:
- USB bridge із частковим SMART;
- дисків, що не підтримують повний набір smartctl-команд;
- проблемних або повільних носіїв;
- неповних або відсутніх SMART-атрибутів.

Один носій не повинен зупиняти повний audit.

---

## 12. Формат user summary

Повинен містити:

### Header
- host
- timestamp
- mode
- current report dir
- previous state file
- `Health summary`
- `Free space summary`
- `Self-test summary`

### Per-disk block
- icon + health status
- model
- serial
- path
- LABEL
- UUID
- SMART overall health
- self-test status + reason
- key SMART counters
- free space
- last self-test
- note / conclusion

---

## 13. Формат Telegram summary

Повинен містити:

### Header
- host
- mode
- date
- `Health`
- `Free space`
- `Self-test`

### Per-disk short block
- icon + model
- LABEL + serial
- path
- `SMART=... | SPACE=... | SELFTEST=...`

---

## 14. Прогрес у логах

Повинен бути stage-based формат:

- `1/7 ...`
- `2/7 ...`
- ...
- `7/7 ...`

І per-disk:
- `[SELFTEST n/N]`
- `[COLLECT n/N]`

---

## 15. Збереження історії

Повинна підтримуватись retention-політика:
- `RUNS_CLEANUP_ENABLED`
- `RUNS_RETENTION_DAYS`

---

## 16. Параметри конфігурації, які треба перенести

Мінімальний набір:

- `PROJECT_ROOT`
- `CONFIG_DIR`
- `LOGS_DIR`
- `RUNS_DIR`
- `LATEST_LINK`
- `LOCK_FILE`
- `STATE_FILE_NAME`

- `POLL_SEC`
- `STAGGER_SEC`
- `AUTO_INSTALL`
- `SKIP_SYSTEM_DISK`
- `MAX_WAIT_MINUTES`
- `SELFTEST_START_RETRIES`
- `SELFTEST_START_RETRY_DELAY`

- `TELEGRAM_ENABLED`
- `TELEGRAM_SEND_DOCUMENT`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`
- `TELEGRAM_API_URL`
- `TELEGRAM_DISABLE_NOTIFICATION`

---

## 17. Портинг на іншу ОС

### Що треба замінити
На іншій ОС треба знайти аналоги для:

- `lsblk`
- `findmnt`
- `smartctl`
- `journalctl`
- `dmesg`
- `flock`
- `df`
- `numfmt`

### Що лишається незмінним
Незалежно від ОС треба зберегти:
- режими роботи;
- формат `disk_state.tsv`;
- модель статусів;
- структуру summary;
- tolerance до проблемних дисків;
- stage-based progress;
- окремий транспортний шар для Telegram.

### Рекомендований підхід до порту
Найкраще розділити реалізацію на 3 шари:
1. **OS adapter layer**  
   Отримання дисків, mountpoint'ів, SMART, файлової системи.
2. **Core logic layer**  
   Оцінка status, free space, retry, self-test model, state schema.
3. **Output layer**  
   User summary, assistant summary, Telegram message.

---

## 18. Мінімальний smoke-test після відновлення

1. `bash -n` або еквівалент syntax check
2. `collect`
3. перевірити:
   - `disk_state.tsv`
   - `summary_user.txt`
   - `summary_assistant.txt`
   - `telegram_message.txt`
4. `short`
5. перевірити:
   - логіку self-test status
   - що проблемний диск не валить увесь запуск
6. перевірити таймери

---

## 19. Критичні інваріанти

Це речі, які не можна ламати без наслідків:

1. стабільний формат `disk_state.tsv`
2. окремий health і free-space статус
3. `collect` не запускає self-test
4. один диск не валить повний аудит
5. progress-логи є завжди
6. Telegram формується з того ж state, що й user summary
7. історія запусків не затирається, а накопичується в `runs/`

---

## 20. Короткий висновок

Якщо втратити вихідний скрипт, але залишити цей документ, то можна відновити еквівалентний utility із тим самим функціоналом:

- discovery
- smart collection
- state schema
- health evaluation
- free-space evaluation
- self-test orchestration
- reporting
- Telegram
- systemd orchestration
- retention policy

Тобто цей документ є не просто описом, а саме специфікацією відновлення.
