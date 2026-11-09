# LINUX_RUNBOOK — команды и контекст для Linux-машины

> Дата: 2026-11-04. Задача: проверить и запустить на Linux порт Windows-фич
> (adapt / adapt-sites / hybrid / routing) в Nukera (Rust-ядро + Flutter GUI).
> Подробный контекст задачи: `CONTEXT_TRANSFER.md` (в этой же папке).
> Целевая тест-система: **Puppy Linux Revolution (apt)** — см. §3.
> Машина разработки — Windows: cargo check, flutter analyze/test и pytest
> там уже пройдены (см. §2). Всё, что требует настоящего Linux, — ниже.

## 1. Контекст в двух абзацах

В Linux-версию Nukera перенесены фичи Windows-версии 0.7.0: глобальная
адаптация (перебор пула стратегий, победитель → `/etc/unblocker/strategy.conf`,
прогресс в `/tmp/unblocker-adapt.json`), per-site адаптация
(`/etc/unblocker/adapt.sites.json` + конфиги `/etc/unblocker/sites/<host>.conf`),
гибридная сборка (базовый профиль + профили победителей) и перепроверка,
маршрутизация (`/etc/unblocker/routing.json`: режим all/custom, категории,
домены, исключения → hostlist-файлы в `/etc/unblocker/hostlists/`).

Архитектура: GUI работает от пользователя и ходит в ядро через FFI только для
чтения; все мутации `/etc` идут через `pkexec /usr/bin/unblocker <подкоманда>`
(polkit-правило разрешает это без пароля). Демон при каждом старте nfqws
применяет routing-конфиг и per-site профили к argv nfqws.

## 2. Что уже проверено на Windows (повторять не нужно)

| Проверка | Результат |
|---|---|
| `cargo check --workspace` | прошёл (подтверждено 2026-11-04) |
| `flutter analyze` (unblocker_gui) | No issues found! |
| `flutter test` | All tests passed! |
| `pytest tests -q` | 3 passed |
| `python scripts/check_static.py` | RESULT: PASS |

Не проверено и не может быть проверено на Windows: реальная сборка
(`flutter build linux`), AppImage, polkit/pkexec, systemd, сам сценарий
адаптации — это и есть содержание этого ранбука.

## 3. Шаг 1 — установка инструментов (Puppy Linux Revolution, apt)

Puppy работает от root, поэтому `sudo` из команд §6–§7 опускайте. Требование
glibc ≥ 2.39 (README) касается готовых бинарников: при сборке на самой системе
glibc совпадает автоматически.

### 3.0 Определить базу и режим

```bash
cat /etc/os-release        # база: Ubuntu 24.04 или Debian 12 — от неё зависят имена пакетов
id -u                      # 0 = root
df -h / ; free -h          # место и память
scripts/detect-init.sh     # скрипт из репо: INIT=…, PUPPY=…, есть ли systemctl и polkit
```

⚠ Puppy — live-система: без save-файла (папка сохранения сессии) всё,
что поставлено через apt, пропадёт при перезагрузке. В VirtualBox включите
сохранение сессии при выключении, либо выполните шаги 1–6 за один сеанс;
если сессия слетела — повторите только этот §3, это несколько минут.

### 3.1 Пакеты сборки (apt)

```bash
apt-get update
apt-get install -y build-essential clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev squashfs-tools unzip xz-utils ca-certificates \
    curl git python3 python3-pytest policykit-1

# libfuse2 (нужен для запуска AppImage): на базе Ubuntu 24.04 пакет называется libfuse2t64
apt-get install -y libfuse2t64 || apt-get install -y libfuse2

# запасной путь, если python3-pytest не нашёлся в репозиториях:
apt-get install -y python3-pip && python3 -m pip install --break-system-packages pytest
```

Если `apt-get update` падает с пустым списком источников — пропишите репозитории
своей базы (Ubuntu 24.04 или Debian 12) в `/etc/apt/sources.list` и повторите.

### 3.2 Rust (rustup)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
source "$HOME/.cargo/env"      # под root это /root/.cargo/env
rustc --version && cargo --version
```

### 3.3 Flutter SDK (та же версия, что на Windows — 3.47.9)

```bash
cd /opt
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.9-stable.tar.xz
tar xf flutter_linux_3.47.9-stable.tar.xz
echo 'export PATH="/opt/flutter/bin:$PATH"' >> /root/.bashrc
export PATH="/opt/flutter/bin:$PATH"
flutter config --enable-linux-desktop
flutter doctor    # для Linux-десктопа красными не должны быть clang/cmake/ninja/GTK
```

Если версии 3.47.9 нет в архиве — возьмите ближайшую stable:
https://docs.flutter.dev/release/archive (шаблон имени:
`flutter_linux_<версия>-stable.tar.xz`).

### 3.4 Проверка инструментов

```bash
gcc --version | head -1
rustc --version
flutter --version | head -2
pytest --version
mksquashfs -version 2>&1 | head -1
pkexec --version
```

## 4. Шаг 2 — статические проверки (быстро, до сборки)

```bash
cd fork/nukera-hybrid
cargo check --workspace                 # Rust: типы/импорты (на Windows уже прошёл)
cd unblocker_gui
flutter pub get
flutter analyze                          # Dart: типы/импорты
flutter test
cd ..
python3 scripts/check_static.py          # wiring/скобки/маркеры (или: make check)
python3 -m pytest tests -q
```

Ожидание: всё зелёное. Если cargo/analyze выдают ошибки — это мелкие правки
импортов/типов: код писался без компилятора, исправлять по тексту ошибки.

## 5. Шаг 3 — сборка

```bash
cd unblocker_gui
flutter build linux --release
# бинарник GUI: build/linux/x64/release/bundle/nukera_gui (имя см. в выводе)

cd ..
cargo build --release
# CLI/демон: target/release/unblocker

scripts/build-appimage.sh                # нужен squashfs-tools
./Nukera-Linux-x86_64.AppImage --verify  # самопроверка системы
```
he commands (from the successful build earlier):

In the Puppy VM (SSH root@192.168.1.116, project at /root/fork/nukera-hybrid):

bash

cd /root/fork/nukera-hybrid
export PATH=/opt/flutter/bin:/root/.cargo/bin:$PATH
cargo build --release
flutter build linux --release
NUKERA_VERSION=0.7.0 bash packaging/deb/build-deb.sh --out dist


## 6. Шаг 4 — polkit-правило (чтобы GUI не спрашивал пароль)

```bash
sudo cp packaging/polkit/50-unblocker.rules /etc/polkit-1/rules.d/
# проверить, что путь бинарника совпадает с правилом:
grep -E 'unblocker' /etc/polkit-1/rules.d/50-unblocker.rules
# правило разрешает: /usr/lib/nukera/unblocker и /usr/bin/unblocker
pkexec /usr/bin/unblocker status   # должно пройти БЕЗ запроса пароля
```

## 7. Шаг 5 — функциональный сценарий новых фич (CLI от root)

Бинарник: `target/release/unblocker` (или установленный путь из §6).
Синтаксис любой подкоманды: `unblocker <команда> --help`.

```bash
B=./target/release/unblocker

# 1) Глобальная адаптация (несколько минут, перебирает пул стратегий)
sudo $B adapt
sudo $B adapt-progress            # или: cat /tmp/unblocker-adapt.json
# в другом терминале можно следить: watch -n2 cat /tmp/unblocker-adapt.json
sudo $B adapt-stop                # отмена (файл /tmp/unblocker-adapt.cancel)

# 2) Per-site адаптация (победители → /etc/unblocker/sites/<host>.conf)
sudo $B adapt-sites youtube.com instagram.com

# 3) Гибрид: базовый профиль + профили победителей
sudo $B hybrid-build
sudo $B hybrid-check              # перепроверка, пересборка упавших сайтов

# 4) Маршрутизация
sudo $B routing-get
sudo $B routing-set custom --categories youtube --domains example.org \
    --excludes bad.example.com
sudo $B routing-get               # убедиться, что сохранилось

# 5) Рестарт демона и проверка, что nfqws получил hostlist'ы
sudo systemctl restart unblocker
ps aux | grep [n]fqws             # в argv должны быть --hostlist /etc/unblocker/hostlists/*.sites
ls /etc/unblocker/hostlists/
cat /etc/unblocker/strategy.conf
cat /etc/unblocker/routing.json
cat /etc/unblocker/adapt.sites.json
```

## 8. Шаг 6 — проверка GUI

```bash
cd unblocker_gui
flutter run -d linux
```

Чек-лист в окне приложения:
- кнопка-шестерёнка/«tune» в AppBar главной страницы → открывается страница адаптации;
- «Адаптировать» → прогресс заполняется (GUI читает `/tmp/unblocker-adapt.json`), кнопка отмены работает;
- список сайтов: добавить/удалить → сохраняется в `/etc/unblocker/adapt.sites.json`;
- гибрид: сборка/перепроверка + рестарт движка;
- маршрутизация: режим/категории/домены/исключения → «Сохранить» → `routing-get` показывает то же;
- все мутации проходят через pkexec БЕЗ запроса пароля (см. §6).

## 9. Если что-то не работает

- **Puppy: нет systemd / polkit** — `scripts/detect-init.sh` покажет INIT и
  PUPPY. Рестарт демона без systemd: `scripts/nukera-service.sh restart`
  (sysv-backend, ставит `/etc/init.d/unblocker`, лог демона:
  `/var/log/unblocker.log` — journalctl на Puppy нет). Без polkit `pkexec`
  недоступен: GUI-мутации не пройдут (ожидаемое ограничение Puppy),
  CLI-сценарий §7 выполняйте напрямую от root.
- **Ошибка компиляции Rust/Dart** — править по тексту ошибки; это ожидаемая
  первая сборка кода, писанного без компилятора.
- **pkexec просит пароль / отказ** — путь бинарника не совпадает с правилом
  (§6): правило знает только `/usr/lib/nukera/unblocker` и `/usr/bin/unblocker`.
- **`/tmp/unblocker-adapt.json` не появляется** — смотреть лог демона:
  `journalctl -u unblocker -f`.
- **GUI падает на старте** — на машине должен быть systemd и glibc ≥ 2.39;
  вызовы systemctl в GUI уже обёрнуты в try/catch, но окружение проверить стоит.
- **Сайт не разблокировался после адаптации** — проверить, что победитель
  записался (`cat /etc/unblocker/strategy.conf`), демон перезапущен, и в argv
  nfqws есть hostlist'ы (§7.5).

## 10. Ключевые пути

- Ядро: `crates/unblocker-core/src/{adapt,routing}/mod.rs`, `src/lib.rs`
- CLI/демон: `crates/unblocker/src/main.rs` (подкоманды: adapt, adapt-stop,
  adapt-sites, hybrid-build, hybrid-check, routing-get, routing-set, adapt-progress)
- GUI: `unblocker_gui/lib/src/{adapt_page,home_page,localization}.dart`
- Упаковка: `packaging/polkit/50-unblocker.rules`,
  `packaging/systemd/unblocker.service`, `packaging/appimage/AppRun`
- Файлы состояния: `/etc/unblocker/{strategy.conf,adapt.sites.json,routing.json,
  sites/,hostlists/,strategies/pool/}`, прогресс `/tmp/unblocker-adapt.json`,
  отмена `/tmp/unblocker-adapt.cancel`
- Windows-референс: `Nukera-win/cli/nukera.py`, `Nukera-win/gui/lib/main.dart`
