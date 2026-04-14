# git-commitors

Выбор автора коммита из настроенного списка. Полезно для общих машин, парного программирования и переключения между рабочим/личным аккаунтами.

[English version](README.md)

## Как работает

Вы настраиваете список авторов в `~/.git-commitors`. При коммите git-commitors показывает диалог выбора (zenity/whiptail/терминал) и применяет выбранного автора.

Два режима:

| Режим | Как | Плюсы | Минусы |
|-------|-----|-------|--------|
| **alias** (рекомендуется) | `git ci -m "msg"` | Работает без дефолтного git-автора, нет двойного запроса GPG, чистый коммит | Нужно использовать `git ci` вместо `git commit` |
| **hook** | `git commit -m "msg"` | Прозрачно, работает с любым git-воркфлоу и GUI | Требует настроенного дефолтного автора, GPG-запрос при `commit.gpgsign=true` |

## Установка

```bash
git clone <repo-url> git-commitors
cd git-commitors
./install.sh
```

Интерактивный промпт спросит режим (alias/hook/оба), или передайте напрямую:

```bash
./install.sh --alias   # рекомендуется
./install.sh --hook    # глобальный хук
./install.sh --both
```

Удалённая установка:

```bash
GIT_COMMITORS_REPO=https://github.com/davydes/git-commitors.git \
  curl -fsSL https://raw.githubusercontent.com/davydes/git-commitors/main/get.sh | bash
```

### Удаление

```bash
./uninstall.sh
```

Удаляет бинарник, библиотеки, глобальные хуки и алиас `git ci`. Конфиг (`~/.git-commitors`) сохраняется.

## Конфиг

Файл: `~/.git-commitors`

```
# Формат: Имя | Email | GPG Key ID (опционально)

@git
John Doe | john@company.com | ABCD1234EF567890
John Doe | john@personal.com
Jane Smith | jane@work.org
```

- `@git` — импорт текущего пользователя из `git config` (user.name, user.email, user.signingkey)
- GPG-ключ опционален — пропустите третье поле или оставьте пустым
- Строки с `#` — комментарии

Дефолтный конфиг содержит только `@git`. Если файла нет — автоматически используется текущий git-пользователь.

### Редактирование

```bash
git commitors config    # открыть в $EDITOR
git commitors import    # добавить директиву @git
git commitors list      # показать список авторов
```

## Использование

### Режим alias (рекомендуется)

```bash
git ci -m "сообщение коммита"
git ci -a -m "stage и коммит"
git ci                          # откроет редактор
```

Все аргументы `git commit` пробрасываются.

Один автор в конфиге — выбирается автоматически, без диалога. Несколько — появляется пикер (zenity на десктопе, whiptail в терминале, bash `select` как фоллбэк).

### Режим hook

```bash
git commit -m "сообщение"         # пикер появится автоматически
GIT_COMMITORS_SKIP=1 git commit -m "msg"  # пропустить пикер разово
```

### Хуки на отдельный репозиторий (вместо глобальных)

```bash
cd /path/to/repo
git commitors init       # установить хуки в этот репо
git commitors remove     # удалить хуки из этого репо
```

## Интерфейс выбора

Определяется автоматически:

| Окружение | Интерфейс |
|-----------|-----------|
| Десктоп (X11/Wayland) + zenity | GUI-диалог |
| Десктоп + kdialog | KDE-диалог |
| Терминал + whiptail | TUI-меню |
| Терминал + dialog | TUI-меню |
| Терминал (голый) | bash `select` |
| Нет TTY / CI | пропуск |

Переопределение: `GIT_COMMITORS_UI=tui` или `GIT_COMMITORS_UI=gui-zenity` и т.д.

## Переменные окружения

| Переменная | Описание |
|------------|----------|
| `GIT_COMMITORS_CONFIG` | Переопределить путь к конфигу |
| `GIT_COMMITORS_UI` | Принудительный UI: `gui`, `tui`, `gui-zenity`, `tui-whiptail`, `none` |
| `GIT_COMMITORS_SKIP=1` | Пропустить выбор автора для одного коммита |

## Крайние случаи

| Сценарий | Поведение |
|----------|-----------|
| 1 автор в конфиге | Авто-выбор без диалога |
| 0 авторов / нет конфига | Alias: ошибка. Hook: проброс без изменений |
| Отмена диалога | Alias: прерывание. Hook: коммит с дефолтным автором |
| CI/CD (`$CI`, `$GITHUB_ACTIONS` и т.д.) | Хук пропускается |
| `git merge` / `git rebase` | Хук пропускается |
| `commit.gpgsign=true`, автор без GPG | Alias: `--no-gpg-sign`, без запроса. Hook: GPG-запрос на первом коммите |

## Структура проекта

```
bin/git-commitors              # CLI-менеджер + обёртка commit
lib/gc-common.sh               # Парсинг конфига, определение дисплея
lib/gc-picker.sh               # Пикер автора (zenity/whiptail/dialog/select)
hooks/prepare-commit-msg       # Хук: показ пикера, сохранение выбора
hooks/post-commit              # Хук: применение автора через amend
install.sh                     # Установщик (интерактивный выбор режима)
uninstall.sh                   # Удаление
get.sh                         # Удалённая установка (curl | bash)
```

## Требования

- bash 4+
- git
- Опционально: zenity (GUI), whiptail (TUI, предустановлен в Ubuntu)

## Лицензия

MIT
