# Контекст задачи: перенос Windows-фич в Linux-версию Nukera

> Файл для переноса контекста в другую сессию/модель. Дата: 2026-11-04.
> Машина разработки: Windows (cargo/rustc/flutter/dart отсутствуют) — компиляция не проверялась.

## 1. Постановка задачи

«Добавь все фичи, которые были реализованы на Windows, в код для Linux».

- Источник фич: `fork/nukera-hybrid/Nukera-win/` (Nukera-win 0.7.0, Python CLI `cli/nukera.py` ~2590 строк + Flutter GUI `gui/lib/main.dart` ~2227 строк).
- Приёмник: `fork/nukera-hybrid/` — Linux-версия: Rust-ядро (`crates/unblocker-core`, `crates/unblocker`) + Flutter GUI (`unblocker_gui/`).
- Linux-версия до порта умела только: вкл/выкл движка, Telegram URL, язык/автостарт. `install-discover` писал per-site конфиги в `/etc/unblocker/sites/`, но демон их никогда не читал.

## 2. Архитектура (как всё связано)

- GUI (Flutter, работает от пользователя) ↔ ядро через FFI (`libunblocker_core.so`) — только для чтения статуса/вкл-выкл.
- Мутации `/etc` GUI делает через `pkexec /usr/bin/unblocker <subcommand>` (CLI от root). FFI для новых фич сознательно НЕ расширялся — GUI от пользователя не может писать в /etc, правильный канал — pkexec CLI (как существующие enable/disable).
- Прогресс адаптации GUI читает напрямую из `/tmp/unblocker-adapt.json` (файл с chmod 0666).
- Демон при каждом старте nfqws применяет routing-конфиг и per-site профили к argv nfqws.
- AppRun ставит бинарник в `/usr/lib/nukera/unblocker`; polkit-правило разрешает оба пути (`/usr/lib/nukera/unblocker` и `/usr/bin/unblocker`) без пароля.

## 3. Что сделано (изменённые файлы)

### Ядро — crates/unblocker-core
- **`src/adapt/mod.rs`** (новый, ~610 строк):
  - Глобальная адаптация: перебор пула стратегий `/etc/unblocker/strategies/pool/*.strat`, прогон каждого сайта через nfqws, победитель → `/etc/unblocker/strategy.conf`.
  - Прогресс: `/tmp/unblocker-adapt.json` (stage/message/best/attempts/total); отмена через `/tmp/unblocker-adapt.cancel`; рестарт сервиса после адаптации.
  - Per-site адаптация: карта `/etc/unblocker/adapt.sites.json`, конфиги сайтов `/etc/unblocker/sites/<host>.conf`.
  - Гибридная сборка: базовый профиль + профили победителей с `--new/--hostlist`.
  - Перепроверка (hybrid-check): пересборка упавших сайтов.
- **`src/routing/mod.rs`** (новый):
  - `RoutingConfig` — `/etc/unblocker/routing.json`: режим all/custom, категории (youtube, telegram web и т.д. — из `Nukera-win/cli/nukera.py ROUTING_CATEGORIES`), пользовательские домены, исключения.
  - Генерация hostlist-файлов: `/etc/unblocker/hostlists/nukera-user.sites`, `nukera-exclude.sites`.
  - `apply_to_args()` — применяется к argv nfqws перед запуском.
  - `per_site_args()` — профили победителей с exclude-листом, чтобы базовый профиль не перехватывал их трафик.
- **`src/lib.rs`**: зарегистрированы `pub mod adapt;` и `pub mod routing;`.

### CLI — crates/unblocker/src/main.rs
Новые подкоманды: `adapt`, `adapt-stop`, `adapt-sites`, `hybrid-build`, `hybrid-check`, `routing-get`, `routing-set [--mode/--categories/--domains/--excludes]`, `adapt-progress`.
Демон: wiring routing-конфига и per-site профилей в запуск nfqws (Windows-parity).

### GUI — unblocker_gui
- **`lib/src/adapt_page.dart`** (новый, 387 строк): прогресс адаптации с опросом /tmp и отменой; список сайтов (добавить/удалить); гибрид (сборка/перепроверка + рестарт движка); маршрутизация (режим/домены/исключения/сохранение).
- **`lib/src/home_page.dart`**: кнопка-иконка `Icons.tune` в AppBar → переход на adapt_page.
- **`lib/src/localization.dart`**: новые ключи en+ru (в т.ч. `routingSaved`).

### Права/упаковка
- **`packaging/polkit/50-unblocker.rules`**: в allowlist добавлены `/usr/lib/nukera/unblocker` и `/usr/bin/unblocker`.
- deb уже создаёт `/etc/unblocker/sites`; AppRun ставит бинарник в путь из polkit-правила — согласовано.

### Инфраструктура проверок
- **`tests/test_static.py`** (новый pytest-сьют, 3 теста), **`scripts/check_static.py`**, **`Makefile`** с целью `check` (на Windows-машине make нет — запускать `py scripts/check_static.py` или `pytest tests -q`).

## 4. Верификация

- `pytest tests -q` в `fork/nukera-hybrid` → **3 passed** (0.04s).
- `py scripts/check_static.py` → **RESULT: PASS**. Проверяет: баланс скобок всех изменённых Rust/Dart-файлов; наличие wiring (`Cmd::Adapt`, `Cmd::AdaptSites`, `Cmd::HybridBuild`, `Cmd::RoutingSet`, `Cmd::AdaptProgress`, `per_site_args`, `pub mod adapt/routing`); кнопку GUI (`adapt_page.dart`, `Icons.tune`); ключи локализации (`routingSaved`); polkit-пути; отсутствие заглушек.
- `cargo check --workspace` → **прошёл** (подтверждено пользователем 2026-11-04).
- `flutter analyze` → **No issues found!** (было 22 замечания, все исправлены: ffi в pubspec, тест, lint'ы); `flutter test` → **All tests passed!**. Flutter 3.47.9 установлен в `C:\Users\naygmus\flutter`.
- **НЕ проверено (невозможно на Windows)**: реальная сборка `flutter build linux`, AppImage, polkit/pkexec, systemd, функциональный сценарий адаптации. Команды для Linux-машины: **`LINUX_RUNBOOK.md`** (в этой же папке).

## 5. Известные грабли из прошлой сессии

- Запись больших файлов (~22К) выдавала текст-заглушку вместо кода — решено записью кода мелкими частями + скрипт-сплайсер (`.sharrowkin/scripts/assemble_gui.py` и др.).
- `adapt/mod.rs` после удаления дубликата hybrid-функций оказался обрезан внутри `sanitize_host`; баланс скобок сходился не сразу (первая проверка ошибалась из-за регэкспа).
- `make check` на этой машине не работает (нет make).

## 6. Что осталось / следующие шаги

1. На Linux-машине: `cargo check --workspace` и `flutter analyze` в `unblocker_gui/` — исправить возможные ошибки компиляции.
2. Прогнать реальный сценарий: adapt → adapt-sites → hybrid-build → hybrid-check → routing-set, проверить, что демон подхватывает routing/per-site при рестарте.
3. Проверить polkit-путь: GUI-кнопки должны вызывать `pkexec /usr/bin/unblocker …` без пароля.

## 7. Ключевые пути

- Windows-референс: `fork/nukera-hybrid/Nukera-win/cli/nukera.py`, `Nukera-win/gui/lib/main.dart`, `Nukera-win/engine/service.bat`
- Linux-ядро: `fork/nukera-hybrid/crates/unblocker-core/src/{adapt,routing}/mod.rs`, `crates/unblocker/src/main.rs`
- GUI: `fork/nukera-hybrid/unblocker_gui/lib/src/{adapt_page,home_page,localization}.dart`
- Упаковка: `fork/nukera-hybrid/packaging/polkit/50-unblocker.rules`
- Проверки: `fork/nukera-hybrid/tests/test_static.py`, `scripts/check_static.py`, `Makefile`
- Пользователь сейчас смотрит: `crates/unblocker-core/src/routing/mod.rs` (строка 1)
