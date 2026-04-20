---
name: sonar-run
description: "Запуск статического анализа SonarQube для 1С-проекта. Используй когда пользователь просит запустить SonarQube, sonar-scanner, проверить код через SonarQube, анализ качества кода, прогнать статический анализ, или когда видишь sonar-project.properties в проекте и нужно проверить код."
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - Edit
---

# /sonar-run — Запуск анализа SonarQube

Запускает sonar-scanner, дожидается обработки на сервере (CE) и выводит результат.

## Алгоритм

### 1. Найти конфигурацию

Прочитай `sonar-project.properties` из корня проекта. Извлеки:
- `sonar.host.url` (по умолчанию `http://localhost:9000`)
- `sonar.token` (для API-запросов к CE)
- `sonar.projectKey` (для ссылки на дашборд)

Если файла нет — спроси пользователя параметры подключения.

### 2. Проверить сервер SonarQube

```bash
curl -s -o /dev/null -w "%{http_code}" <host>/api/system/status
```

- **200** — сервер работает, переходи к шагу 3
- **Иначе** — сервер не запущен. Попробуй запустить:

#### Автозапуск SonarQube

1. Найди установку:
   ```bash
   find /c/SonarQube -name "StartSonar.bat" -type f 2>/dev/null
   ```

2. SonarQube 10+ требует JDK 17+, SonarQube 26+ требует JDK 21+. Стандартный `JAVA_HOME` может указывать на старую JDK. Решение — переменная `SONAR_JAVA_PATH`:
   ```bash
   # Найти JDK 21
   find /c/SonarQube -name "java.exe" -path "*/jdk*/bin/*" 2>/dev/null
   ```

3. Запустить через обёрточный bat или PowerShell:
   ```bash
   # Вариант 1: если есть start-sonar.bat в папке SonarQube
   powershell.exe -NoProfile -Command "Start-Process -FilePath 'C:\SonarQube\start-sonar.bat' -WindowStyle Minimized"
   
   # Вариант 2: создать обёртку
   cat > /c/SonarQube/start-sonar.bat << 'EOF'
   @echo off
   set SONAR_JAVA_PATH=<путь к java.exe JDK 21>
   call <путь к StartSonar.bat>
   EOF
   powershell.exe -NoProfile -Command "Start-Process -FilePath 'C:\SonarQube\start-sonar.bat' -WindowStyle Minimized"
   ```

4. Дождаться запуска (поллинг `/api/system/status`, макс 90 секунд):
   ```bash
   for i in $(seq 1 18); do
     sleep 5
     status=$(curl -s -o /dev/null -w "%{http_code}" <host>/api/system/status 2>/dev/null)
     if [ "$status" = "200" ]; then echo "SonarQube UP"; break; fi
   done
   ```

### 3. Найти sonar-scanner

```bash
# В PATH
where sonar-scanner 2>/dev/null || where sonar-scanner.bat 2>/dev/null

# Типичные пути
find /c/SonarQube -name "sonar-scanner.bat" -type f 2>/dev/null
```

### 4. Очистить кэш и запустить анализ

```bash
rm -rf <project>/.scannerwork
cd <project> && <путь>/sonar-scanner.bat 2>&1 | tail -15
```

Анализ занимает 5-10 минут для крупного 1С-проекта. Запускай в фоне (`run_in_background: true`).

Ожидаемый результат:
```
ANALYSIS SUCCESSFUL, you can find the results at: <host>/dashboard?id=<projectKey>
EXECUTION SUCCESS
```

Если `EXECUTION FAILURE` — смотри лог выше, типичные причины:
- Нет подключения к серверу
- Невалидный токен
- Ошибка парсинга BSL (проверь кодировку файлов: UTF-8 BOM + CRLF)

### 5. Дождаться обработки CE

После загрузки отчёта сканером, CE (Compute Engine) обрабатывает его на сервере. Это может занять 2-6 минут.

Из лога сканера извлеки task id:
```
More about the report processing at <host>/api/ce/task?id=<taskId>
```

Поллинг статуса:
```bash
for i in $(seq 1 24); do
  sleep 15
  result=$(curl -s -H "Authorization: Bearer <token>" "<host>/api/ce/task?id=<taskId>" 2>/dev/null)
  status=$(echo "$result" | grep -o '"status":"[^"]*"' | head -1)
  echo "[$i] $status"
  if echo "$status" | grep -qE "SUCCESS|FAILED"; then
    echo "$result"
    break
  fi
done
```

### 6. Вывод результата

- **SUCCESS** — сообщи пользователю ссылку на дашборд: `<host>/dashboard?id=<projectKey>`
- **FAILED** — извлеки `errorMessage` из JSON ответа CE и сообщи причину

## Типичные ошибки CE

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `OutOfMemoryError: Java heap space` | CE не хватает памяти | Увеличить `sonar.ce.javaOpts` в `conf/sonar.properties` до `-Xmx4g` и перезапустить |
| `Source of file has less lines than expected` | BSL-файл с LF вместо CRLF | Конвертировать в UTF-8 BOM + CRLF (правило U19) |
| `UnsupportedClassVersionError` | Неверная версия Java | Указать JDK 21 через `SONAR_JAVA_PATH` |

## Предупреждения (не критичные)

- `SCM provider autodetection failed` — проект не в git-репозитории, можно игнорировать или добавить `sonar.scm.disabled=true`
- `Too many duplication groups` — крупный файл, SonarQube ограничивает до 100 групп дублирования
