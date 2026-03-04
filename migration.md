# Перенос в свой репозиторий

## Что нужно для работы скрипта

### Обязательные файлы (минимум)

| Файл | Назначение |
|------|------------|
| `zorin.sh` | Основной скрипт |
| `make_dummy_deb.sh` | Сборка dummy-пакетов (вызывается из zorin.sh) |

Этого достаточно, если в `zorin.sh` оставить дефолтный `REPO_RAW_BASE` (оригинальный репо): ключи и при необходимости `make_dummy_deb.sh` будут качаться с GitHub NanashiTheNameless.

---

### Если хотите, чтобы всё бралось из вашего репо (самодостаточный вариант)

Нужны те же два скрипта **плюс** GPG-ключи в каталоге `raw/`:

| Файл | Назначение |
|------|------------|
| `zorin.sh` | Основной скрипт |
| `make_dummy_deb.sh` | Сборка dummy-пакетов |
| `raw/zorin-os.gpg` | Публичный ключ Zorin OS |
| `raw/zorin-os-premium.gpg` | Публичный ключ Premium (Zorin 16/17) |
| `raw/zorin-os-premium-eighteen.gpg` | Публичный ключ Premium (Zorin 18) |

Файлы `raw/*.gpg` в этом клоне могут отсутствовать (они в оригинальном репо). Скачать их один раз:

```bash
# из корня вашего репо
mkdir -p raw
curl -fsSL -o raw/zorin-os.gpg \
  "https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/raw/zorin-os.gpg"
curl -fsSL -o raw/zorin-os-premium.gpg \
  "https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/raw/zorin-os-premium.gpg"
curl -fsSL -o raw/zorin-os-premium-eighteen.gpg \
  "https://github.com/NanashiTheNameless/Zorin-OS-Pro/raw/refs/heads/main/raw/zorin-os-premium-eighteen.gpg"
```

В `zorin.sh` задать свой репо (в начале файла):

```bash
REPO_RAW_BASE="${ZORIN_PRO_REPO_RAW_BASE:-https://github.com/YOUR_USER/YOUR_REPO/raw/refs/heads/main}"
```

Подставьте `YOUR_USER` и `YOUR_REPO`.

---

## Пошагово: перенос в уже существующий репо

1. **Склонируйте свой репо и откройте его в каталоге.**

2. **Скопируйте только нужные файлы.**

   Минимум (зависимость от оригинального репо по ключам и `make_dummy_deb.sh`):

   ```bash
   cp /path/to/Zorin-OS-Pro/zorin.sh .
   cp /path/to/Zorin-OS-Pro/make_dummy_deb.sh .
   ```

   Самодостаточный вариант (всё из вашего репо):

   ```bash
   cp /path/to/Zorin-OS-Pro/zorin.sh .
   cp /path/to/Zorin-OS-Pro/make_dummy_deb.sh .
   mkdir -p raw
   # затем скачать raw/*.gpg как выше или скопировать из клона оригинального репо
   ```

3. **Если всё должно идти с вашего репо** — в `zorin.sh` замените дефолт в строке с `REPO_RAW_BASE` на URL вашего репо (как в примере выше).

4. **Закоммитьте и запушьте.**

   ```bash
   git add zorin.sh make_dummy_deb.sh
   [ при самодостаточном варианте: git add raw/ ]
   git commit -m "Add Zorin OS Core→Pro scripts"
   git push
   ```

5. **Проверка запуска с вашего репо:**

   ```bash
   bash <(curl -fsSL "https://github.com/YOUR_USER/YOUR_REPO/raw/refs/heads/main/zorin.sh") -8 -X -U
   ```

   (или без `-U`, если нужны подтверждения.)

---

## Что из этого проекта можно не переносить

- `.github/` — CI, issue templates: только если хотите такие же в своём репо.
- `README.md`, `CONTRIBUTORS.md`, `SECURITY.md`, `license.md`, `raw/NOTICE.txt` — по желанию (можно взять идеи или текст).
- `CODE_REVIEW.md`, `MIGRATION.md` — служебные; в свой репо можно не копировать.
- `.vscode/` — настройки редактора, не нужны для работы скрипта.

Итого: для работы скрипта в своём репо достаточно перенести **`zorin.sh`** и **`make_dummy_deb.sh`**; при желании полностью перейти на свой репо — ещё каталог **`raw/`** с тремя `.gpg` и правка **`REPO_RAW_BASE`** в `zorin.sh`.
