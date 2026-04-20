---
name: sonar-issues
description: "Получение и анализ проблем из SonarQube. Используй когда пользователь просит показать ошибки SonarQube, issues, проблемы качества кода, code smells, баги из сонара, что нашёл SonarQube, результаты анализа, или хочет исправить конкретные проблемы SonarQube."
argument-hint: "[severity] [file]"
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Edit
---

# /sonar-issues — Проблемы из SonarQube

Получает список проблем (issues) из SonarQube API, группирует и выводит в удобном формате.

## Параметры

| Параметр | Обязательный | По умолчанию | Описание |
|----------|:------------:|--------------|----------|
| severity | нет | все | Фильтр: `BLOCKER`, `CRITICAL`, `MAJOR`, `MINOR`, `INFO` |
| file | нет | все | Путь к файлу (относительно корня проекта) |

## Алгоритм

### 1. Получить параметры подключения

Прочитай `sonar-project.properties`:
- `sonar.host.url` → `HOST`
- `sonar.token` → `TOKEN`
- `sonar.projectKey` → `PROJECT`

### 2. Проверить доступность сервера

```bash
curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$HOST/api/system/status"
```

Если сервер недоступен — предложи `/sonar-run`.

### 3. Запросить issues

#### Все проблемы проекта

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/issues/search?componentKeys=$PROJECT&ps=500&statuses=OPEN,CONFIRMED,REOPENED" \
  2>/dev/null
```

#### С фильтром по severity

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/issues/search?componentKeys=$PROJECT&severities=CRITICAL,BLOCKER&ps=500&statuses=OPEN,CONFIRMED,REOPENED" \
  2>/dev/null
```

#### По конкретному файлу

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/issues/search?componentKeys=$PROJECT:src/path/to/File.bsl&ps=500&statuses=OPEN,CONFIRMED,REOPENED" \
  2>/dev/null
```

### 4. Парсинг и вывод

JSON-ответ содержит массив `issues`. Для каждого issue извлеки:
- `severity` — уровень: BLOCKER / CRITICAL / MAJOR / MINOR / INFO
- `type` — тип: BUG / VULNERABILITY / CODE_SMELL
- `component` — файл (после `:` идёт путь)
- `line` — номер строки
- `message` — описание проблемы
- `rule` — идентификатор правила (напр. `bsl:EmptyCodeBlock`)
- `effort` — оценка трудозатрат на исправление

#### Формат вывода

Группируй по файлам, внутри файла — по severity (от BLOCKER до INFO):

```
## src/cf/Documents/МойДокумент/Ext/ObjectModule.bsl (5 issues)

| Строка | Severity | Тип | Правило | Описание |
|--------|----------|-----|---------|----------|
| 42 | CRITICAL | BUG | bsl:UsingHardcodeNetworkAddress | Hardcoded network address |
| 78 | MAJOR | CODE_SMELL | bsl:EmptyCodeBlock | Empty code block | 
| 156 | MAJOR | CODE_SMELL | bsl:MissingReturnedValueDescription | Missing return value description |
```

### 5. Сводка

После таблиц — общая статистика:

```
Всего: 127 issues
- BLOCKER: 0
- CRITICAL: 3
- MAJOR: 45
- MINOR: 62
- INFO: 17
```

### 6. Пагинация

API возвращает максимум 500 issues за запрос. Если `total > 500`, делай дополнительные запросы с `p=2`, `p=3` и т.д.:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/issues/search?componentKeys=$PROJECT&ps=500&p=2&statuses=OPEN,CONFIRMED,REOPENED"
```

## Полезные API-запросы

### Метрики проекта (общая картина)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/measures/component?component=$PROJECT&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density,ncloc"
```

### Список правил BSL

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/rules/search?languages=bsl&ps=500"
```

### Quality Gate статус

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$HOST/api/qualitygates/project_status?projectKey=$PROJECT"
```

## Советы по исправлению

Если пользователь хочет исправить конкретные issues:
1. Прочитай файл с проблемой (`Read`)
2. Найди строку с issue
3. Покажи пользователю контекст и предложи исправление
4. Для BSL-правил: можно подавить через `// BSLLS:<RuleName>-off` если правило неприменимо

Не исправляй массово без подтверждения пользователя — некоторые issues могут быть ложными срабатываниями.
