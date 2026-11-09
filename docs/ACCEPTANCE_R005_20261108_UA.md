# ForPrint Disk Health Audit — акт приймання R005

Дата: **2026-11-08**. Статус: **BACKUP_VERIFIED + SANDBOX_RESTORE_ACCEPTED**.

> Це приймання резервної копії та репетиції інсталяції в перенаправлену файлову систему. **Повне встановлення в окремій чистій Debian 12 VM ще не проводилося.**

## Контрольні ідентифікатори

- Репозиторій: `Kovalchuk-PrintMaster/System_Administrator_Dedian_HDD-SDD_Healht`.
- Базовий коміт перевіреної резервної копії: `d45ab30619e17104c3340f5ec3d4dc7531fe559e`.
- SHA-256 зашифрованого GitHub snapshot: `130d95aaa3b8c733e350b7db9b901025eb783968ef6860f32f914e58878ab629`.
- SHA-256 розшифрованого оригіналу: `8ad9e4d21a7498716b6f6cdb98f5edbfd066f781ca1cdf835d29c4f12b44a0f3`.
- Підтверджена наявність SHA-256 правильного оригіналу після незалежного `git clone` і `gpg --decrypt`.

## Фактичні результати R005 (вивід оператора)

| Компонент | Фактичний статус |
|---|---|
| Фіксація GitHub джерел та cipher | `R005_GITHUB_SOURCE_PIN=PASS_COMMIT_AND_CIPHER` |
| Live systemd = GitHub (байт у байт) | `R005_LIVE_UNITS=PASS_BYTE_EXACT_GITHUB` |
| Перевірка systemd units | `R005_SYSTEMD_ANALYZE=PASS` |
| Bash-синтаксис | `R005_BASH_SYNTAX=PASS` |
| `--apply` з перенаправленими шляхами й systemctl stub | `R005_SANDBOX_INSTALL=PASS_APPLY_NO_LIVE_PATH_WRITES` |
| Захист повторного встановлення й невчасної активації | `R005_INSTALL_AND_ACTIVATION_GUARDS=PASS_NO_TIMERS_ENABLED` |
| Розшифрування приватної копії | `R005_GPG_RECOVERY=PASS_ORIGINAL_SHA256` |
| Ефективний Telegram-токен із env = оригінальному | `R005_TELEGRAM_TOKEN_EQUIVALENCE=PASS_ENV_PRESERVES_ORIGINAL_EFFECTIVE_TOKEN` |
| Live скрипт = вихідний snapshot | `R005_LIVE_SCRIPT_VS_SNAPSHOT=PASS` |
| Live env = вихідний snapshot | `R005_LIVE_ENV_VS_SNAPSHOT=PASS_SAME` |
| Приватна конфігурація й chmod 0600 | `R005_PRIVATE_CONFIG_RESTORE=PASS_SHA256_MODE_0600_NO_OVERWRITE` |
| Відновлено файлів історії | `R005_HISTORY_RESTORE_FILES=1827` |
| Фактичне чисте Debian встановлення | `R005_ACTUAL_CLEAN_DEBIAN_INSTALL=NOT_PERFORMED_SANDBOX_REHEARSAL_ONLY` |
| Live-служби | `R005_LIVE_SERVICE_CHANGES=NONE` |
| Підсумок | `R005_ACCEPTANCE=PASS_SANDBOX_WITH_TELEGRAM_EQUIVALENCE` |

## Експлуатаційний стан на момент аудиту

- `short`: щосуботи 14:00, випадкова затримка до 15 хвилин.
- `long`: перша субота місяця о 14:00, випадкова затримка до 15 хвилин.
- Обидва таймери: `Persistent=true`, запуск через `disk-health-audit@.service` від `root`.
- Цей акт нічого не встановлює та не дозволяє запускати SMART-тести.

## Обов'язкові умови для аварійного відновлення

1. Поза сервером і GitHub зберегти пароль GPG. Переконатися, що він доступний без залежності від GPG-кешу.
2. Під час реального відновлення виконувати інструкцію `docs/OPERATIONS_AND_RESTORE_UA.md`.
3. Приватний `.env` відновити з зашифрованого snapshot; пароль/токени ніколи не включати до Git або журналів.
4. Вмикати таймери лише після перевірки дисків/розкладу: `Persistent=true` може запустити пропущені перевірки.
5. Ця копія — **знімок стану на 2026-11-08**. Пізніші зміни конфігурації/коду або журнали потребують нового контрольованого snapshot та commit.
6. Репозиторій публічний. Короткі/передбачувані паролі можна підбирати офлайн; для майбутнього snapshot краще приватний репозиторій і довга випадкова фраза.

## Наступна межа: R007 / чиста Debian 12 VM

**Не виконувати цей сценарій на s01.** Виділена VM Debian 12 з власним systemd (PID 1):

1. Встановити стандартні пакети з apt: `git gnupg smartmontools util-linux gawk curl coreutils findutils grep sed procps`.
2. Клонувати GitHub у `/root/disk-health-restore`; перевірити точний затверджений commit і SHA-256 encrypted snapshot.
3. `bash /root/disk-health-restore/scripts/install_restore.sh --dry-run`.
4. `bash /root/disk-health-restore/scripts/install_restore.sh --apply` — **тільки на VM**.
5. `bash /root/disk-health-restore/scripts/verify_restore.sh`; переконатися, що `short`/`long` timers не активовані.
6. За потреби приватного restore — GPG decrypt у захищеній тимчасовій директорії, SHA-256 оригіналу, `restore_private_config.py` без перезапису існуючих даних.
7. Не виконувати `short`, `long`, `collect` або `--enable-timers` як частину статичного приймання.
8. Після фіксації протоколу окремої VM статус можна підвищити до `CLEAN_DEBIAN_RESTORE_ACCEPTED`.

**Статус R006:** публікація цього акта — лише документальне закриття приймання R005; не змінює програму та не замінює випробування на окремій VM.
