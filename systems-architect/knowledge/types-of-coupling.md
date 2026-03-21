---
title: "10 видов Coupling"
domain: systems-design
tags: [coupling, architecture, analysis]
keywords: [temporal coupling, functional coupling, static coupling, dynamic coupling, semantic coupling, deployment coupling, through resources]
related: [coupling-cohesion.md, instability-metric.md, event-storming.md, data-model.md]
source: "Systems Analysis Course, Lesson 1"
---

## Определение

Coupling — связанность между элементами системы. Существует минимум 10 видов связанности. Их понимание помогает обнаружить скрытые зависимости, которые не видны при поверхностном анализе. Насмотренность в видах coupling — ключевой навык системного аналитика.

## Когда применять

- При анализе ES-модели: искать все виды coupling между контекстами
- При анализе модели данных: искать формальные связи (static coupling)
- При решении о слиянии/разделении контекстов
- При оценке риска изменений: какие сервисы затронуты

## Как применять

Пройти по каждому виду для каждой пары контекстов:

1. **Temporal** — есть ли строгий порядок выполнения? (регистрация → оплата → сборка)
2. **Functional** — дублируется ли одинаковая бизнес-логика в нескольких местах?
3. **Implementation** — используют ли общую техническую реализацию (shared lib)?
4. **Static** — есть ли общие данные? (FK в БД, общие модели данных)
5. **Dynamic** — есть ли вызовы в рантайме? (HTTP, RPC, события)
6. **Afferent/Efferent** — считать входящие (Ca) и исходящие (Ce) зависимости → instability
7. **Through resources** — используют ли общие ресурсы? (CPU, память, файлы, одна БД)
8. **Semantic** — используют ли общий протокол/формат данных?
9. **Deployment** — есть ли зависимости при деплое? (нельзя задеплоить A без B)

## Примеры

- Сервисы А и Б используют одну БД → **Through resources + Static coupling** → вероятно один контекст
- Нотификации вызываются после каждого действия → **Temporal + Dynamic coupling** → нотификации — технический шаг, не отдельный сервис
- Два контекста используют одну модель «Пользователь» → **Static + Semantic coupling**

## Anti-patterns

- **Видеть только Dynamic coupling** (HTTP-вызовы) и игнорировать остальные 9 видов
- **Не проверять Temporal coupling** — самый частый скрытый coupling в распределённых системах
- **Разрезать по Through resources coupling** не учитывая бизнес-смысл
- **Думать что async = нет coupling** — async убирает Temporal, но не Static и Semantic
