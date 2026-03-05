# Zorin OS — скрипты настройки и проверки

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](license)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![platform](https://img.shields.io/badge/platform-Linux%20%7C%20Zorin-lightgrey)](https://zorin.com/os/)
[![ShellCheck](https://github.com/Vanilla-SilQ-HD/Zorin/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Vanilla-SilQ-HD/Zorin/actions/workflows/shellcheck.yml)

Набор скриптов для постустановочной настройки **Zorin OS** (Ubuntu/Debian): ускорение системы, питание (TLP), загрузчик **systemd-boot + UKI** с Windows по умолчанию и быстрая/расширенная проверка конфигурации.

**Требования:** Zorin OS или совместимый дистрибутив. Для режима загрузчика — загрузка в **UEFI** и смонтированный **ESP** на `/boot/efi`.

---

## Запуск без клонирования (curl)

Скрипт **zorin-master.sh** самодостаточный — его можно запускать по однострочнику через `curl`. Сначала лучше просмотреть код: открой ссылку в браузере или выполни `curl -fsSL … | less`.

**Базовый URL (ветка main):**

```
https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh
```

**Примеры (подставь нужный режим):**

```bash
# Полная настройка: postinstall → systemdboot → verify
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | sudo bash -s -- --all

# Только пост-установка (пакеты, TLP, ZRAM, earlyoom, sysctl)
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | sudo bash -s -- --postinstall

# Только загрузчик (systemd-boot + UKI, Windows default, Firmware скрыт)
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | sudo bash -s -- --systemdboot

# Быстрая проверка (без sudo можно, но меньше деталей)
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | bash -s -- --verify

# Расширенная проверка (NVIDIA, батарея, NVMe, sleep)
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | sudo bash -s -- --verify-plus

# Предполётная проверка перед --systemdboot (UEFI, ESP, место, Windows EFI)
curl -fsSL https://raw.githubusercontent.com/Vanilla-SilQ-HD/Zorin/main/scripts/zorin-master.sh | bash -s -- --check
```

> Запуск по curl выполняется **на свой риск**. Рекомендуется сначала просмотреть скрипт или клонировать репо и запускать локально.

---

## Структура репозитория

```
Zorin/
├── license
├── readme.md              # этот файл (на GitHub отображается с бейджами и разметкой)
├── .gitignore
├── .github/workflows/
│   └── shellcheck.yml
├── zorin.sh               # Zorin OS Core → Pro (отдельный сценарий)
├── make_dummy_deb.sh      # вызывается из zorin.sh
├── raw/                   # GPG-ключи для zorin.sh (самодостаточный режим)
│   ├── zorin-os.gpg
│   ├── zorin-os-premium.gpg
│   └── zorin-os-premium-eighteen.gpg
├── configs/
│   ├── readme.md
│   ├── tlp-battery.conf
│   └── tlp-performance.conf
└── scripts/
    ├── zorin-master.sh    # единая точка входа (postinstall, systemdboot, verify)
    ├── zorin-lib.sh
    ├── zorin-postinstall.sh
    ├── zorin-systemdboot-windows-default.sh
    ├── zorin-verify.sh
    ├── zorin-verify-plus.sh
    └── zorin-pro.txt
```

- **zorin-master.sh** — один файл, без зависимостей: подходит и для curl, и для локального запуска.
- **zorin.sh** — конвертация Zorin OS Core → Pro (ключи и пакеты); при необходимости тянет файлы из этого репо (`raw/`, `make_dummy_deb.sh`).
- **zorin-verify.sh** / **zorin-verify-plus.sh** подключают `zorin-lib.sh` — запускать из каталога `scripts/` или после клонирования.

Служебные файлы (перенос, заметки) лежат в корне с префиксом `.` и в обычном списке не отображаются.

---

## Режимы master-скрипта

| Режим | Описание | Локально | Через curl |
|-------|----------|----------|------------|
| **--postinstall** | Пакеты, TLP, ZRAM, earlyoom, sysctl. Без загрузчика. | `sudo ./zorin-master.sh --postinstall` | `curl -fsSL …/zorin-master.sh \| sudo bash -s -- --postinstall` |
| **--systemdboot** | systemd-boot + UKI, Windows default, Firmware скрыт. | `sudo ./zorin-master.sh --systemdboot` | `curl -fsSL …/zorin-master.sh \| sudo bash -s -- --systemdboot` |
| **--verify** | Быстрая проверка (UEFI, loader, записи, UKI, hook). | `./zorin-master.sh --verify` | `curl -fsSL …/zorin-master.sh \| bash -s -- --verify` |
| **--verify-plus** | + сервисы, mem_sleep, swap, sysctl, NVIDIA, батарея, NVMe. | `sudo ./zorin-master.sh --verify-plus` | `curl -fsSL …/zorin-master.sh \| sudo bash -s -- --verify-plus` |
| **--check** | Предполётная проверка перед --systemdboot. | `./zorin-master.sh --check` | `curl -fsSL …/zorin-master.sh \| bash -s -- --check` |
| **--all** | postinstall → systemdboot → verify. | `sudo ./zorin-master.sh --all` | `curl -fsSL …/zorin-master.sh \| sudo bash -s -- --all` |

При запуске с `sudo` вывод пишется в `/var/log/zorin-master.log`.

### Важно про --systemdboot

- **Меняет загрузчик.** Запускай только когда Windows нормально грузится и ESP смонтирован на `/boot/efi`.
- Пункт **Firmware Settings** скрываем через `auto-firmware no`, не переименовываем.
- Перед первым запуском полезно выполнить `--check`.

---

## Локальная установка (клонирование)

```bash
git clone https://github.com/Vanilla-SilQ-HD/Zorin.git
cd Zorin/scripts
chmod +x zorin-master.sh
sudo ./zorin-master.sh --postinstall   # пример
```

Отдельные скрипты (без master):

| Скрипт | Запуск |
|--------|--------|
| zorin-postinstall.sh | `sudo bash scripts/zorin-postinstall.sh` |
| zorin-systemdboot-windows-default.sh | `sudo bash scripts/zorin-systemdboot-windows-default.sh` |
| zorin-verify.sh | `bash scripts/zorin-verify.sh` или с `sudo` |
| zorin-verify-plus.sh | `sudo bash scripts/zorin-verify-plus.sh` |

### Zorin OS 18 Core → Pro (zorin.sh)

**Важно:** официальный и единственный доверенный вход для `zorin.sh` — **оригинальный репозиторий** автора, не этот форк.

```bash
# Базовый вызов (Zorin OS 18 Core, определение версии по флагу -8)
bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL \
  https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/zorin.sh) [флаги]
```

- **-8** — жёстко указать, что система = Zorin OS 18 Core.  
  Лучше всегда использовать, чтобы не полагаться на автоопределение.
- **-X** — Extra‑контент: кроме базового Pro‑набора ставит большой набор доп. приложений (APT + Flatpak).  
  Если какое‑то Flatpak‑приложение не встанет — будет `Warning`, скрипт продолжит.
- **-U** — unattended: все apt/flatpak‑установки без вопросов (`-y`).

**Практические варианты для Zorin 18 Core:**

```bash
# 1) Минимальный Pro (внешний вид + Pro‑фичи), с подтверждениями:
bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL \
  https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/zorin.sh) -8

# 2) То же, но полностью без вопросов:
bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL \
  https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/zorin.sh) -8 -U

# 3) Полный Pro + Extra, с подтверждениями (рекомендация автора):
bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL \
  https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/zorin.sh) -8 -X

# 4) Полный Pro + Extra, полностью тихо:
bash <(curl -H 'DNT: 1' -H 'Sec-GPC: 1' -fsSL \
  https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/zorin.sh) -8 -X -U
```

**Перед запуском:**

- стабильный интернет (APT + GitHub);  
- установлен Flatpak, если планируешь `-X`;  
- не менять руками `/etc/apt/sources.list.d/zorin.list` и `/etc/apt/trusted.gpg.d` во время работы;  
- по возможности сначала проверить сценарий в VM/на тестовой машине;  
- на боевой системе сделать snapshot/бэкап и поначалу запускать **без `-U`**, чтобы видеть список пакетов.

**Что делает скрипт по сути (по коду):**

- не трогает `/home`;  
- работает через стандартные `apt`, `dpkg`, `flatpak`;  
- правит только:
  - `sources.list.d/zorin.list` (с бэкапом),  
  - добавляет GPG‑ключи в `/etc/apt/trusted.gpg.d/`,  
  - создаёт `apt.conf.d/99zorin-os-premium-user-agent`,  
  - устанавливает/делает dummy‑пакеты `zorin-os-*`,  
  - удаляет `zorin-os-census` и его cron‑таски.

**Риски:**

- это неофициальный инструмент, имитирующий Premium‑систему (юридические/этические последствия — на пользователе);  
- серьёзное изменение репозиториев и большого числа пакетов → возможны конфликты при будущих обновлениях;  
- флаг `-U` делает всё без переспросов — удобно, но снижает контроль.

После завершения работы `zorin.sh` **обязательно перезагрузка**:

```bash
sudo reboot
```

Логи postinstall/systemd‑boot: `/var/log/zorin-postinstall.log`, `/var/log/zorin-systemdboot.log`.

---

## Опциональные конфиги (TLP)

В каталоге **configs/** лежат альтернативные профили TLP:

- **tlp-battery.conf** — максимум батареи.
- **tlp-performance.conf** — максимум производительности.

Они не обязательны: postinstall уже создаёт `99-zorin-snappy.conf`. Подробнее — в [configs/readme.md](configs/readme.md).

---

## Откат / восстановление

- **Вернуть GRUB:** загрузка с установочного носителя Zorin/Ubuntu, смонтировать корень и ESP, установить `grub-efi-amd64`, выполнить `grub-install` и `update-grub`. Либо восстановить из бэкапа ESP (`/boot/efi/EFI/_backup_*`).
- **Меню не грузится:** загрузка с USB, монтирование раздела с корнем, правка конфигов или восстановление из бэкапа ESP.
- **Логи:** при запуске с sudo — `/var/log/zorin-master.log` и соответствующие логи в `/var/log/`.

---

## FAQ

**Windows не появляется в меню systemd-boot.**  
Проверь наличие `/boot/efi/EFI/Microsoft/Boot/bootmgfw.efi`. Если путь другой — отредактируй `/boot/efi/loader/entries/windows.conf`.

**UKI не собирается (ukify ошибка).**  
Установи `systemd-ukify`, выполни `--check`. Для нестандартного root (LUKS/LVM) может понадобиться правка cmdline в скрипте.

**После postinstall ноутбук греется или батарея быстро садится.**  
Подключи опциональный профиль из `configs/tlp-battery.conf` или `configs/tlp-performance.conf`.

**Проверка скриптов в CI.**  
При push/PR в `main` запускается ShellCheck для `scripts/*.sh`.

---

## После выполнения

После `--postinstall` или `--systemdboot` рекомендуется перезагрузка:

```bash
sudo reboot
```

---

## Лицензия

[MIT](license).
