---
title: "Event-Driven Architecture (EDA)"
domain: systems-design
tags: [architecture-style, distributed, async, events]
keywords: [EDA, события, async, брокер сообщений, eventual consistency, расцепление]
related: [microservices-architecture.md, event-storming.md, cqrs.md, event-sourcing.md, saga-pattern.md, communication-types.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Event-Driven Architecture — распределённый стиль, где компоненты общаются через события (events) через брокер сообщений. Продюсеры публикуют события, не зная о консьюмерах. Обеспечивает высокую расцепленность, масштабируемость и отказоустойчивость, но требует принятия eventual consistency.

## Когда применять

- Нужна высокая расцепленность между сервисами
- Допустима eventual consistency (не нужна немедленная консистентность)
- Высокая нагрузка (брокер как буфер)
- Много консьюмеров одного события (fan-out)
- Нужна аудит-история всех действий

## Как применять

1. **Определить события**: бизнесовые, не технические (OrderPlaced, PaymentProcessed)
2. **Выбрать брокер**: Kafka (высокая нагрузка, retention), RabbitMQ (flexibility), etc.
3. **Определить schema**: формат события, версионирование (Schema Registry)
4. **Продюсеры**: публикуют событие после завершения локальной транзакции
5. **Консьюмеры**: подписываются на нужные события, обрабатывают идемпотентно
6. **Обработать ошибки**: Dead Letter Queue, retry policy, idempotency key

## Примеры

- OrderPlaced → [Payment Service] → PaymentProcessed → [Inventory Service] → [Shipping Service]
- UserRegistered → [Email Service, Notification Service, Analytics Service] (fan-out)
- Kafka для обработки миллионов транзакций в финтехе

## Anti-patterns

- **Технические события**: `RecordUpdatedInDB` — это не бизнес-событие
- **Синхронный запрос через события**: ждать ответа на событие = использовать async как sync
- **Нет идемпотентности**: событие обработано дважды → дубль транзакции
- **Нет schema registry**: разные версии событий → консьюмеры ломаются
- **Оркестрация без нужды**: использовать Saga там, где достаточно локальной транзакции
