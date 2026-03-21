---
title: "Pipeline Architecture"
domain: systems-design
tags: [architecture-style, data-processing, etl]
keywords: [pipeline, фильтры, трансформации, ETL, map-reduce, потоковая обработка]
related: [microkernel-architecture.md, event-driven-architecture.md, quality-attributes.md]
source: "Systems Analysis Course, Lesson 3"
---

## Определение

Pipeline Architecture — архитектурный стиль, где данные последовательно проходят через цепочку фильтров-трансформаций. Каждый фильтр выполняет одну операцию над данными и передаёт результат следующему. Классический паттерн для обработки данных.

## Когда применять

- Последовательная обработка данных без ветвлений
- ETL-пайплайны (Extract, Transform, Load)
- Map-Reduce задачи
- Потоковая обработка (stream processing)
- Компиляция кода (lexer → parser → semantic analysis → code gen)

## Как применять

1. **Определить входные данные** и конечный результат
2. **Разбить на шаги**: каждый шаг = один фильтр с одной ответственностью
3. **Определить формат данных** между фильтрами (контракт передачи)
4. **Собрать пайплайн**: линейная цепочка фильтров
5. **Добавить ветвления** при необходимости (разные пайплайны для разных типов входных данных)

## Примеры

- **ETL**: CSV файл → [Parse] → [Validate] → [Transform] → [Enrich] → [Load to DB]
- **Компилятор**: Source code → [Lexer] → [Parser] → [Semantic] → [Optimizer] → [Code Gen]
- **Обработка заказов**: заказ → [Validate] → [Check inventory] → [Calculate price] → [Create invoice]
- Unix pipes: `cat log.txt | grep ERROR | awk '{print $3}' | sort | uniq -c`

## Anti-patterns

- **Состояние между фильтрами**: фильтр хранит данные о предыдущих вызовах → нарушает изоляцию
- **Фильтр с несколькими ответственностями**: валидация + трансформация + обогащение в одном
- **Использовать для интерактивных систем**: Pipeline — для batch/stream обработки, не для CRUD
- **Фильтры знают друг о друге**: нарушает независимость — каждый фильтр должен работать независимо
