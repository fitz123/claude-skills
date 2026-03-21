---
title: "Layered Architecture (N-layer)"
domain: systems-design
tags: [architecture-style, monolith, simplicity]
keywords: [layered, N-layer, слоистая архитектура, presentation, business, persistence]
related: [modular-monolith.md, microservices-architecture.md, local-global-complexity.md, quality-attributes.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Layered Architecture — монолитный архитектурный стиль, где система разделена на горизонтальные слои: Presentation (UI/API) → Business Logic → Persistence (БД). Каждый слой зависит только от слоя ниже. Самый простой и дешёвый стиль.

## Когда применять

- Небольшое приложение с простыми требованиями
- Ограниченный бюджет и короткие сроки
- Команда без опыта в распределённых системах
- MVP или прототип
- Нет противоречащих характеристик между частями системы

## Как применять

1. **Разделить код на слои**: Controller/API → Service/UseCase → Repository/DAO
2. **Запретить** обратные зависимости (только сверху вниз)
3. **БД — одна** для всего приложения
4. **Не вводить слои без необходимости**: 3 слоя обычно достаточно

**Характеристики:**
- Simplicity/Cost: ★★★★★
- Deployability: ★ (всё деплоится вместе)
- Scalability: ★ (масштабируется только целиком)
- Fault Tolerance: ★

## Примеры

- Внутренний CRM небольшой компании на Spring Boot/Django
- Административная панель для управления контентом
- Прототип маркетплейса на старте

## Anti-patterns

- **Использовать когда нужна масштабируемость**: монолит не масштабируется горизонтально
- **Big Ball of Mud**: слои есть формально, но каждый вызывает каждого — нет реального разделения
- **Начинать сразу с микросервисов**: если подойдёт layered monolith — начинайте с него
- **Пропускать слои**: контроллер напрямую обращается в БД — архитектура ломается
