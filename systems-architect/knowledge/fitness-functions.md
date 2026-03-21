---
title: "Fitness Functions — верификация архитектуры"
domain: systems-design
tags: [fitness-functions, architecture, quality-attributes, testing, metrics]
keywords: [fitness function, фитнес-функции, верификация архитектуры, метрики, compliance]
related: [quality-attributes.md, instability-metric.md, adr.md, refactoring-approaches.md]
source: "Systems Analysis Course, Lesson 4.2"
---

## Определение

**Fitness Functions** — набор метрик и автоматических проверок, которые верифицируют, что архитектура системы соответствует заявленным характеристикам. Это «тесты» не для кода, а для архитектурных свойств системы.

Аналогия: если unit-тесты проверяют, что код работает правильно, то fitness functions проверяют, что система соответствует архитектурным целям (performance, security, coupling, etc.).

Из курса: при планировании распила монолита рекомендуется описать **«набор обязательных фитнес-функций для любого сервиса в компании»** — с указанием значений и инструментов.

## Когда применять

- При определении стандартов для новых сервисов в компании
- При переходе с монолита на микросервисы — чтобы отслеживать, что новые сервисы не деградируют
- Для автоматической проверки соблюдения архитектурных решений (из ADR)
- При регулярном аудите архитектуры

## Как применять

### Шаг 1: Определи критически важные характеристики

Для каждого поддомена есть ключевые характеристики (из анализа в lesson 3). Именно их верифицируют fitness functions.

Пример для core-поддомена:
- Performance: P95 < 200ms
- Availability: 99.9%
- Instability: I < 0.3 для ключевых сервисов

### Шаг 2: Сформулируй проверяемые метрики

Каждая характеристика должна быть **измеримой**:

| Характеристика | Fitness Function |
|---|---|
| Performance | P95 latency < N ms |
| Availability | Uptime > 99.9% за 30 дней |
| Coupling/Instability | I = Ce/(Ca+Ce) < 0.4 для core-сервисов |
| Security | Все эндпоинты с аутентификацией |
| Deployability | Деплой < 10 минут, rollback < 5 минут |
| Testability | Покрытие тестами > 80% |

### Шаг 3: Автоматизируй проверки

```
Инструменты:
- Performance: k6, Gatling, Artillery (нагрузочное тестирование)
- Availability: Prometheus + Grafana (мониторинг)
- Coupling: ArchUnit (Java), dependency-cruiser (JS) — проверка архитектурных зависимостей
- Security: OWASP ZAP, Snyk
- Code coverage: Jest, pytest, go test
```

### Шаг 4: Включи в CI/CD pipeline

Fitness functions должны запускаться автоматически:
- **При каждом PR** — быстрые проверки (coupling, тесты)
- **При деплое** — smoke tests, security checks
- **Регулярно** — performance tests, мониторинг instability

### Стандарты для всех сервисов компании

При планировании распила монолита Антон рекомендует описать пять стандартов:

1. **Документация** — какие модели нужны (ES, data model), как описывать контекст принятых решений (ADR)
2. **Коммуникации** — допустимые варианты sync/async, форматы контрактов
3. **Разрешённые технологии** — список допустимых БД, фреймворков (Tech Radar)
4. **Болванка сервиса** — стартовый шаблон для каждого языка (паттерн Cookiecutter/Archetype)
5. **Обязательные fitness functions** — минимальный набор проверок для любого сервиса + значения + инструменты

## Примеры

### Happy Cat Box — обязательные fitness functions

```yaml
# Пример для всех сервисов Happy Cat Box
fitness_functions:
  performance:
    p95_latency_ms: 500
    tool: k6
  availability:
    uptime_percent: 99.5
    tool: prometheus
  instability:
    max_value: 0.5  # для core-сервисов
    core_max: 0.3
    tool: custom-script
  security:
    all_endpoints_authenticated: true
    tool: zap
  deployability:
    deploy_time_minutes: 15
    rollback_time_minutes: 5
```

### КИБЕР-ГЕНПОДРЯД — fitness functions

**Для модуля приёмки (core):**
- P95 создания акта КС-2 < 3 секунды
- Данные об объёме работ не теряются (consistency)
- Instability модуля приёмки < 0.3
- Все операции с КС-2/КС-3 логируются (compliance с ФЗ-44)

**Для модуля ГПР (core):**
- Изменение графика работ доступно всем ролям < 1 секунда
- Конфликты в ГПР обнаруживаются автоматически

## Anti-patterns

- **Fitness functions без автоматизации** — ручная проверка архитектуры забывается
- **Слишком много метрик** — 50 метрик = ни одна не важная. Фокус на критически важных
- **Fitness functions только в начале** — архитектура эволюционирует, метрики нужно обновлять
- **Порог "всегда зелёный"** — слишком мягкие пороги не ловят деградацию
- **Только технические метрики** — бизнесовые характеристики (TTM, deployability) тоже нужны
