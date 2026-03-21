---
title: "Microservices Architecture"
domain: systems-design
tags: [architecture-style, distributed, scalability]
keywords: [микросервисы, отдельная БД, независимый деплой, инфраструктурная изоляция, гранулярное масштабирование]
related: [service-based-architecture.md, event-driven-architecture.md, entity-service-antipattern.md, local-global-complexity.md, quality-attributes.md, database-selection.md, instability-metric.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Microservices Architecture — распределённый стиль, где каждый сервис маленький, независимо деплоится и имеет свою БД. Максимальная модульность и масштабируемость, но максимальная глобальная сложность. Оправдан только в двух конкретных случаях.

## Когда применять

**Только когда выполняется хотя бы одно из условий:**
1. Нужны **противоречащие характеристики** в одном сервисе (например, высокая availability для поиска и высокая consistency для платежей — нельзя в одном сервисе)
2. Нужна **инфраструктурная изоляция кода** (разные языки, команды разного размера, compliance требования)

## Как применять

1. **Убедиться в необходимости**: проверить два условия выше
2. **Разбить по боундед-контекстам**: 1 контекст = 1 сервис
3. **Каждый сервис имеет свою БД**: нет общих таблиц
4. **Определить коммуникации**: синхронные (HTTP/gRPC) или асинхронные (события)
5. **Настроить observability**: distributed tracing, centralized logging, metrics
6. **Определить распределённые транзакции**: Saga pattern

**Характеристики:**
- Simplicity/Cost: ★ (самый дорогой)
- Deployability: ★★★★★
- Scalability: ★★★★★
- Fault Tolerance: ★★★★★

## Примеры

- Netflix: сотни микросервисов, каждый с уникальными характеристиками (streaming vs recommendation vs billing)
- Uber: разные требования к availability и latency для GPS tracking vs payment processing

## Anti-patterns

- **Микросервисы без необходимости**: «потому что модно» → колоссальная сложность без выгоды
- **Entity Services**: UserService, OrderService вокруг сущностей → распределённый монолит
- **Общая БД**: нивелирует все преимущества микросервисов
- **Нет distributed tracing**: при проблемах невозможно найти причину
- **Синхронные цепочки**: A вызывает B вызывает C — temporal coupling, каскадные отказы
