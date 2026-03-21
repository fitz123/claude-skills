---
title: "Modular Monolith"
domain: systems-design
tags: [architecture-style, monolith, modularity]
keywords: [modular monolith, модульный монолит, bounded context, модуль, одна БД]
related: [layered-architecture.md, service-based-architecture.md, bounded-context.md, local-global-complexity.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Modular Monolith — монолитный стиль, где код разделён на модули по боундед-контекстам, но всё деплоится как одно приложение с одной БД. Компромисс: даёт модульность и изоляцию без глобальной сложности распределённых систем.

## Когда применять

- Нужна модульность, но команда небольшая
- Хотите возможность перехода к микросервисам в будущем (модули = кандидаты в сервисы)
- Нет чётких требований на независимое масштабирование отдельных частей
- Начало продукта с неопределёнными границами

## Как применять

1. **Разделить по боундед-контекстам**: каждый модуль = 1 контекст
2. **Запретить прямые зависимости** между модулями (только через API модуля)
3. **Одна БД**, но логическое разделение (схемы, префиксы таблиц по контексту)
4. **Провести Event Storming** для выявления правильных границ модулей
5. **Версионировать API** между модулями — как будто это уже сервисы

**Характеристики** (лучше Layered, хуже Microservices):
- Simplicity/Cost: ★★★★
- Deployability: ★★ (всё вместе, но модули изолированы)
- Modularity: ★★★

## Примеры

- Netflix в начале: монолит с модулями Catalog, Streaming, Billing, Profiles
- Shopify использует Modular Monolith как основу большой части платформы
- Старт e-commerce: модули Catalog, Cart, Checkout, Orders, Users

## Anti-patterns

- **Модули с прямыми зависимостями**: модуль А импортирует классы модуля Б напрямую → не монолит, а Big Ball of Mud
- **Одна «модель» на все модули**: shared User entity везде → высокий coupling
- **Разбивать на модули по слоям** (не по контекстам): repositories/, services/, controllers/ → это не Modular Monolith
- **Пропустить и сразу идти в микросервисы**: если монолит ещё не болит
