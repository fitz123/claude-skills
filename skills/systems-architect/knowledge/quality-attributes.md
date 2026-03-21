---
title: "Архитектурные характеристики (Quality Attributes)"
domain: systems-design
tags: [quality-attributes, architecture, requirements, non-functional]
keywords: [характеристики, availability, scalability, performance, maintainability, security, testability, deployability]
related: [quality-attribute-scenarios.md, three-stages-architecture.md, fitness-functions.md, strategy-vs-tactics.md, finding-quality-attributes.md, company-lifecycle.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Архитектурные характеристики (Quality Attributes, Non-Functional Requirements) — свойства системы, определяющие её качество. Это то, КАК система выполняет функции, а не ЧТО она делает. Выбор характеристик определяет архитектурный стиль.

## Когда применять

- При анализе требований: найти явные и неявные характеристики
- При выборе архитектурного стиля: стиль выбирается на основе характеристик
- При расстановке приоритетов: не все характеристики одинаково важны
- При проектировании fitness functions: каждая характеристика → измеримый критерий

## Как применять

**12 ключевых характеристик:**
| # | Характеристика | Описание |
|---|---|---|
| 1 | **Availability** | % uptime, устойчивость к отказам |
| 2 | **Scalability** | Способность расти под нагрузкой |
| 3 | **Modifiability** | Цена и риск изменений |
| 4 | **Maintainability** | Сложность восстановления и обслуживания |
| 5 | **Security** | Защита от несанкционированного доступа |
| 6 | **Performance** | Время отклика |
| 7 | **Agility** | Скорость адаптации к изменениям |
| 8 | **Testability** | Полнота и простота тестирования |
| 9 | **Deployability** | Скорость и простота выкатки |
| 10 | **Usability** | Удобство для пользователей |
| 11 | **Consistency** | Все видят одинаковые данные |
| 12 | **Simplicity** | Понятность системы |

**Найти характеристики:**
- **Явные**: из требований (числа, SLA)
- **Неявные**: из фраз бизнеса («time to market» → agility+deployability), из домена (финтех → security+consistency), из этапа компании (стартап → simplicity)

## Примеры

- «10K одновременных пользователей» → Scalability
- «99.9% uptime» → Availability
- «Финтех» → Security + Consistency (неявно)
- «Time to market» → Agility + Deployability + Testability

## Anti-patterns

- **Хотеть все характеристики**: архитектура — это trade-offs, нельзя иметь максимум всего
- **Не приоритизировать**: равный вес у 12 характеристик → нет фокуса
- **Абстрактные формулировки**: «высокая производительность» → нужны числа и сценарии
- **Не искать неявные**: брать только то, что явно сказано → упустить важные ограничения
