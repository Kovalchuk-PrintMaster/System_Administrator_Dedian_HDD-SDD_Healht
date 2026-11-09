# ForPrint Disk Health — R007 r002 Debian 12 Docker restore rehearsal

Це автономний пакет для s01. Працює лише від root, потрібні працюючий Docker daemon, Git та вихід до Docker Hub, Debian apt і GitHub при першому запуску. **Не встановлює Docker**, не змінює реальні шляхи програми `/opt/forprint-utils/disk-health-audit` та `/etc/systemd/system`, не запускає SMART-тестів і не читає приватний `.env`.

**Виправлення r002:** замінено некоректний Docker CLI шаблон `{{.Server.OSType}}` на штатний `{{.OSType}}` у read-only preflight. Всі інші кроки встановлення й політика ізоляції збережені. Додано 2 тести цього бар’єра.

## Що він доводить

- Свіжий `git clone` точної голови `main`: `dcd164fb6b40eea2de7d6ddc2469bbb17d6ccb1e`.
- SHA-256 шифрованого snapshot `130d95aaa3b8c733e350b7db9b901025eb783968ef6860f32f914e58878ab629`.
- Побудова тимчасового образу **Debian 12 (bookworm)** зі стандартними залежностями через `apt`.
- Запуск контейнера без привілеїв, мережі, монтування директорій хоста, передачі блочних пристроїв, із обмеженнями пам'яті й процесів.
- `install_restore.sh --dry-run` та **фактичний `--apply` всередині контейнера**, порівняння байтів скриптів, шаблона, документації, трьох systemd-юнітів.
- Перевірка синтаксису `systemd-analyze verify` і календарів.
- Перевірка заборони повторного `--apply` та `--enable-timers` без приватного конфіга.
- `systemctl daemon-reload` ізолюється вузькою заглушкою тільки для цього виклику, оскільки systemd **не є PID1 контейнера**. Інші команди systemctl заглушка забороняє.

## Важливі обмеження

Це **не VM та не доказ `CLEAN_DEBIAN_VM=PASS`**. Немає повноцінного systemd PID1, немає перевірки завантаження служб та активації таймерів; приватний GPG snapshot навмисне не розшифровується (це вже перевірено R005). Docker image build використовує мережу для apt і завантаження базового образу; docker run — без мережі. Образ після виконання прибирається, базовий кеш Docker може залишитися. Якщо Docker daemon не працює або немає інтернету, скрипт зупиниться з чесним статусом, не змінюючи робочі служби.

## Запуск

Скопіюй ZIP у `/opt/forprint-utils/disk-health-audit/tmp/`, тоді:

```bash
cd /opt/forprint-utils/disk-health-audit || exit 1
unzip -oq tmp/ForPrint_Disk_Health_R007_Debian12_Docker_Restore_r002_20261109.zip -d tmp/
bash tmp/ForPrint_Disk_Health_R007_Debian12_Docker_Restore_r002_20261109/run_once.sh
```

Звіт (без паролів і токенів) записується у `/root/forprint-disk-health-reports/R007_Debian12_Container_*.txt` з правами 0600.

**Очікуваний заключний маркер лише після успіху:** `R007_RESULT=PASS_DEBIAN12_CONTAINER_INSTALL_STATIC_SYSTEMD`, разом із `R007_CLEAN_DEBIAN_VM=NOT_PERFORMED`.
