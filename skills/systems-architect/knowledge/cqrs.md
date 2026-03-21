---
title: "CQRS (Command Query Responsibility Segregation)"
domain: systems-design
tags: [pattern, cqrs, read-write, scalability]
keywords: [CQRS, command, query, чтение, запись, read model, write model, scalability]
related: [event-sourcing.md, event-driven-architecture.md, quality-attributes.md, database-selection.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

CQRS — паттерн разделения модели чтения и записи. **Command** (запись) и **Query** (чтение) используют разные модели данных, а иногда разные хранилища. Применяется когда характеристики read и write пути противоречат друг другу.

## Когда применять

- Характеристики чтения и записи сильно различаются (read-heavy vs write-heavy)
- Нужна оптимизация запросов чтения без усложнения модели записи
- Сложные read-модели (агрегации, проекции нескольких источников)
- В связке с Event Sourcing

## Как применять

1. **Определить Command side**: операции изменения состояния (CreateOrder, ProcessPayment)
2. **Определить Query side**: операции чтения (GetOrderList, GetOrderDetails)
3. **Разделить модели**: Command работает с domain model (агрегаты); Query работает с denormalized read model
4. **Синхронизировать**: через события (событие от write → обновление read model)
5. **Выбрать хранилища**: write → PostgreSQL (consistency); read → Redis/Elasticsearch (performance)

## Примеры

- E-commerce: запись заказа → PostgreSQL (транзакции); список заказов пользователя → денормализованная таблица или Redis для скорости
- Аналитическая платформа: write события → Kafka; read дашборды → ClickHouse (агрегации)
- Event Sourcing + CQRS: write = поток событий; read = проекции из событий

## Anti-patterns

- **CQRS везде**: добавляет сложность; применять только при реальном противоречии характеристик
- **Одно хранилище без разных моделей**: «CQRS» только в названии
- **Нет синхронизации**: write и read модели расходятся → некорректные данные
- **Сложная read-модель в command side**: нарушает разделение, теряется смысл паттерна
