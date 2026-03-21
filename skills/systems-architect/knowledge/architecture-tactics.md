---
title: "Архитектурные тактики"
domain: systems-design
tags: [tactics, quality-attributes, optimization, trade-offs]
keywords: [тактики, улучшение характеристик, rollback, оркестратор, maintainability, integrability, trade-offs]
related: [quality-attributes.md, quality-attribute-scenarios.md, three-stages-architecture.md, communication-types.md, database-selection.md]
source: "Systems Analysis Course, Lesson 5"
---

## Определение

Архитектурные тактики — конкретные технические решения для **точечного улучшения** определённых архитектурных характеристик (quality attributes). В отличие от архитектурного стиля (монолит vs микросервисы), тактики применяются на уровне отдельных элементов системы.

**Ключевое свойство**: улучшение одной характеристики через тактику почти всегда **ухудшает** другую (trade-off).

## Когда применять

- Когда выбранный архитектурный стиль не даёт нужного значения характеристики
- Когда выбор БД или вид коммуникации не решает проблему
- При точечной оптимизации конкретного узкого места
- Когда стейкхолдер говорит: «нас не устраивает [скорость/надёжность/цена изменений]»

## Как применять

### Алгоритм

1. Идентифицировать проблемную характеристику (из quality attribute scenario)
2. Найти тактики, улучшающие эту характеристику
3. Оценить, какие другие характеристики пострадают
4. Принять решение с учётом приоритетов системы
5. Зафиксировать в ADR с обоснованием trade-off

### Примеры тактик по характеристикам

#### Availability (доступность)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| Active redundancy (hot standby) | Instant failover | ↑ стоимость |
| Passive redundancy (warm standby) | Быстрый failover | Задержка переключения |
| Circuit Breaker | Изоляция отказов | ↑ сложность |
| Health check + auto-restart | Самовосстановление | Временный downtime |
| Geographic distribution | Disaster recovery | ↑ latency, ↑ стоимость |

#### Maintainability (сопровождаемость)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| **Rollback** в деплойменте | Быстрый откат изменений | Нужна стратегия данных |
| Feature flags | Deploy without release | ↑ сложность кода |
| Modularization | Изоляция изменений | ↑ время разработки |
| Strangler Fig | Постепенная замена легаси | Период двойного поддержания |
| Automated testing | Безопасный рефакторинг | ↑ время на тесты |

#### Performance (производительность)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| Caching | ↓ latency | Stale data risk |
| Connection pooling | ↑ throughput БД | Сложность конфигурации |
| Async processing | Разгрузка критического пути | ↑ сложность, eventual consistency |
| Read replicas | ↑ read throughput | Repication lag |
| CDN | ↓ latency для статики | ↑ стоимость |

#### Scalability (масштабируемость)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| Horizontal scaling | ↑ throughput | Нужен stateless сервис |
| Vertical scaling | Просто, быстро | Предел роста, downtime |
| Database sharding | ↑ data throughput | ↑ сложность, сложные запросы |
| CQRS | Разделить read/write нагрузку | ↑ сложность, eventual consistency |

#### Integrability (интегрируемость)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| **Оркестраторы** (Saga, API Gateway) | ↑ управляемость интеграций | ↑ coupling на orchestrator |
| Event-driven integration | Loose coupling | ↑ сложность отладки |
| API versioning | Backward compatibility | ↑ поддержка старых версий |
| Contract testing | Безопасные изменения API | ↑ время на тесты |

#### Security (безопасность)
| Тактика | Эффект | Trade-off |
|---------|--------|-----------|
| Authentication/Authorization | Контроль доступа | ↑ latency |
| Rate limiting | Защита от DDoS/brute-force | Легитимные пользователи могут быть заблокированы |
| Encryption at rest/in transit | Защита данных | ↑ CPU, ↑ latency |
| Audit logging | Трассируемость | ↑ хранилище |

## Примеры

### КИБЕР-ГЕНПОДРЯД

**Проблема**: приёмка работ должна работать на объекте при плохом интернете (availability ↑)

**Тактика**: Offline-first + sync при восстановлении соединения
- **Улучшает**: Availability при нестабильной связи
- **Ухудшает**: Consistency (данные могут расходиться до синхронизации), Complexity

**Тактика**: Feature flags для постепенного rollout модуля ГПР
- **Улучшает**: Deployability, Maintainability (можно откатить без деплоя)
- **Ухудшает**: Complexity кода

**Тактика**: Rollback стратегия в CI/CD
- **Улучшает**: Maintainability (быстрый откат при проблемах)
- **Ухудшает**: Нужна стратегия для миграций БД (нельзя просто откатить если схема поменялась)

## Anti-patterns

- **Тактика без диагностики**: добавить кэш «потому что быстрее» без измерения реального bottleneck
- **Игнорировать trade-offs**: применить тактику не понимая, что ухудшится
- **Тактика вместо стиля**: латать architecture smell тактиками вместо смены архитектурного стиля
- **Преждевременная оптимизация**: применять тактики масштабируемости до подтверждения нагрузки
- **Тактики без ADR**: применить нетривиальное решение без документирования причин
