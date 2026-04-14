---
name: xunit-run
description: "Запуск xUnit-тестов 1С через vanessa-runner (vrunner). Используй когда пользователь просит запустить тесты, прогнать xUnit, выполнить unit-тесты, проверить тесты в базе, запустить vrunner xunit, или после сборки тестовой EPF хочет её выполнить."
argument-hint: "[TestPath] [database]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
---

# /xunit-run — Запуск xUnit-тестов

Запускает xUnit-тесты 1С через `vrunner xunit` и выводит результаты из JUnit XML.

## Usage

```
/xunit-run [TestPath] [database]
```

| Параметр  | Обязательный | По умолчанию | Описание                                    |
|-----------|:------------:|--------------|---------------------------------------------|
| TestPath  | нет          | `tests`      | Папка с EPF-тестами или конкретный EPF-файл  |
| database  | нет          | default      | Имя базы из `.v8-project.json`               |

## Критичные знания

### vrunner — единственный надёжный способ запуска

Прямой вызов `1cv8.exe` через bat/PowerShell ненадёжен: процесс `1CLaunch` перехватывает запуск и `start /wait` не ждёт реального завершения. `vrunner` обходит эту проблему.

### Путь к тестам — ПОЗИЦИОННЫЙ аргумент

```bash
vrunner xunit --settings env.json "tests"                    # ПРАВИЛЬНО
vrunner xunit --settings env.json --testpath tests           # ОШИБКА: "Избыточные параметры"
```

`--testpath` вызывает ошибку cmdline-парсера vanessa-runner 2.6. Путь передаётся только позиционно, после всех `--` параметров.

## Параметры подключения

Прочитай `.v8-project.json` из корня проекта. Возьми `v8path` и разреши базу:
1. Если пользователь указал базу по имени — ищи по id / alias / name в `.v8-project.json`
2. Если не указал — используй `default`
3. Если `.v8-project.json` нет — спроси пользователя

## Команда

```powershell
powershell.exe -NoProfile -File .claude/skills/xunit-run/scripts/xunit-run.ps1 <параметры>
```

### Параметры скрипта

| Параметр | Обязательный | По умолчанию | Описание |
|----------|:------------:|--------------|----------|
| `-TestPath <путь>` | нет | `tests` | Папка с EPF или конкретный EPF-файл |
| `-V8Version <версия>` | нет | из `.v8-project.json` | Версия платформы |
| `-InfoBasePath <путь>` | * | — | Файловая база |
| `-InfoBaseServer <сервер>` | * | — | Сервер 1С |
| `-InfoBaseRef <имя>` | * | — | Имя базы на сервере |
| `-UserName <имя>` | нет | — | Имя пользователя 1С |
| `-Password <пароль>` | нет | — | Пароль |
| `-PathXUnit <путь>` | нет | автопоиск | Путь к xddTestRunner.epf |
| `-OrdinaryApp <0\|1>` | нет | `1` | Обычное приложение (для УПП/совместимость 8.2) |
| `-ReportPath <путь>` | нет | `build/tests/junit.xml` | Путь к JUnit XML |
| `-SettingsFile <путь>` | нет | `env.json` | Путь к файлу настроек vrunner |

> `*` — нужен `-InfoBasePath` или пара `-InfoBaseServer` + `-InfoBaseRef`

## Алгоритм работы

1. Найти vrunner (PATH, ovm, типичные пути)
2. Если `env.json` существует — использовать; иначе — сгенерировать из параметров
3. Проверить наличие `xddTestRunner.epf` (из env.json `--pathxunit` или `oscript_modules/add/`)
4. Запустить `vrunner xunit --settings <env.json> "<testpath>"`
5. Прочитать JUnit XML и вывести сводку

## Разбор результатов

После запуска скрипт:
- Парсит JUnit XML
- Выводит сводку: total / passed / failed / errors / skipped
- Для failed/error тестов — имя теста и сообщение ошибки
- Exit code: 0 = все тесты passed, 1 = есть ошибки

## Примеры

```powershell
# Запуск всех тестов в папке tests/
powershell.exe -NoProfile -File .claude/skills/xunit-run/scripts/xunit-run.ps1 -InfoBasePath "C:\Базы\МояБаза" -UserName "test" -Password "1"

# Конкретный EPF
powershell.exe -NoProfile -File .claude/skills/xunit-run/scripts/xunit-run.ps1 -TestPath "tests/МойТест.epf" -InfoBasePath "C:\Базы\МояБаза"

# Серверная база
powershell.exe -NoProfile -File .claude/skills/xunit-run/scripts/xunit-run.ps1 -InfoBaseServer "srv01" -InfoBaseRef "MyDB" -UserName "Admin" -Password "secret"

# С существующим env.json (все параметры уже там)
powershell.exe -NoProfile -File .claude/skills/xunit-run/scripts/xunit-run.ps1 -SettingsFile "env.json"
```

## Если xddTestRunner.epf не найден

```bash
opm install add
```

Это установит xUnit-аддон в `oscript_modules/add/`, включая `xddTestRunner.epf`.

## Если vrunner не найден

```bash
opm install vanessa-runner
# или через ovm:
ovm install stable
```
