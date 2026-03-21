---
title: "Расширенные модели описания систем"
domain: systems-design
tags: [modeling, sequence-diagram, bpmn, c4, system-description, diagrams]
keywords: [sequence diagram, BPMN, структурная модель, модели системы, описание архитектуры, диаграммы]
related: [architecture-frameworks.md, event-storming.md, data-model.md, communication-types.md, bounded-context.md]
source: "Systems Analysis Course, Lesson 5"
---

## Определение

Набор дополнительных моделей описания систем сверх базового набора курса. В реальных проектах шести базовых моделей часто не хватает — некоторые части системы требуют специализированного описания.

### Базовые 6 моделей из курса:
1. Event Storming (ES) — бизнес-события и процессы
2. Модель данных — сущности и связи
3. Поддомены и боундед-контексты
4. Характеристики в каждом боундед-контексте
5. Коммуникации между элементами системы
6. Структурная модель (сервисы и связи)

### Расширенные модели (Урок 5):
7. **Sequence Diagram** — взаимодействие элементов во времени
8. **Структурная модель с внешними системами** (аналог C4 L2)
9. **Модель бизнес-процесса** (BPMN, flowchart)

## Когда применять

- **Sequence Diagram**: когда нужно показать точный порядок обмена сообщениями между компонентами
- **C4 L2 / структурная модель**: когда нужно показать взаимодействие бэкенда, фронта, БД и внешних систем
- **BPMN**: когда ES-модель недостаточно детальна и нужно расписать алгоритм работы конкретной команды/процесса

## Как применять

### Sequence Diagram

**Что показывает**: кто, кому, что и в каком порядке отправляет. Лучший инструмент для описания request-response и событийных цепочек.

**Структура:**
- Участники (actors/components) — вертикальные линии
- Сообщения — горизонтальные стрелки с метками
- Временная ось — сверху вниз
- Опциональные блоки: `loop`, `alt`, `opt`

**Инструменты**: PlantUML, Mermaid, Lucidchart, draw.io

**Пример (Mermaid):**
```
sequenceDiagram
    Прораб->>API: POST /acceptance {work_id, volume}
    API->>AcceptanceService: validateWork(work_id)
    AcceptanceService->>DB: SELECT work WHERE id=work_id
    DB-->>AcceptanceService: work data
    AcceptanceService-->>API: valid
    API->>DB: INSERT acceptance_record
    API->>EventBus: WorkAccepted event
    EventBus->>NotificationService: notify ITR
    API-->>Прораб: 200 OK
```

### Структурная модель с внешними системами (C4 L2)

**Что показывает**: как бэкенд связывается с внешними системами, фронтом и БД. Аналог C4 Level 2 (Container diagram).

**Элементы:**
- Frontend (web/mobile)
- Backend services/API
- Базы данных
- Внешние системы (SMS-шлюз, платёжная система, 1C)
- Брокеры сообщений

**Когда использовать вместо полного C4**: когда нужно быстро показать топологию системы без детализации компонентов.

### BPMN / Flowchart (Модель бизнес-процесса)

**Что показывает**: детальный алгоритм работы команды или набора команд. ES описывает процесс абстрактно, BPMN — детально с ветвлениями, циклами, ролями.

**Основные элементы BPMN:**
- **Events**: start event (круг), end event (жирный круг), intermediate events
- **Tasks**: прямоугольник с закруглёнными углами — активность
- **Gateways**: ромб — ветвление (XOR, AND, OR)
- **Flows**: стрелки между элементами
- **Pools/Lanes**: прямоугольники для разных участников/ролей

**Когда BPMN, а не ES:**
- Нужно показать условия (if/else)
- Нужно показать параллельные ветки
- Нужно показать таймеры и ожидания
- Аудитория — бизнес-аналитики, которые работают с BPMN

**Инструменты**: Camunda Modeler, draw.io (BPMN templates), Lucidchart, Miro templates

## Примеры

### КИБЕР-ГЕНПОДРЯД — применение моделей

**Sequence Diagram: процесс подписания КС-2**
```
РПП → API: запрос на формирование КС-2 (период)
API → PercentovkaService: calculate(объект, период)
PercentovkaService → DB: SELECT принятые работы за период
DB → PercentovkaService: список работ с объёмами
PercentovkaService → KS2Generator: generate(works)
KS2Generator → PDF: создать документ
PDF → Storage: сохранить
PercentovkaService → API: KS-2 готов
API → РПП: ссылка на документ
РПП → API: подписать КС-2
API → DB: UPDATE ks2 SET status=signed
API → EventBus: KS2Signed event
EventBus → NotificationService: уведомить Главного инженера
```

**Структурная модель (C4 L2) — КИБЕР-ГЕНПОДРЯД:**
- [Mobile App] → [Backend API]
- [Backend API] → [PostgreSQL DB]
- [Backend API] → [Redis Cache]
- [Backend API] → [S3 Storage] (PDF документы)
- [Backend API] → [SMS Gateway] (уведомления)
- [Backend API] → [Auth Service]

**BPMN: процесс приёмки работ:**
- Start → [Прораб заполняет объём] → Gateway: объём корректен?
  - Нет → [Уведомление прорабу] → конец
  - Да → [ИТР проверяет качество] → Gateway: качество ОК?
    - Нет → [Замечание прорабу] → [Исправление] → [ИТР проверяет качество]
    - Да → [Приёмка записана в систему] → [КС-2 обновлён] → End

## Anti-patterns

- **Sequence Diagram для всего**: не нужен для простых CRUD-операций; только для сложных цепочек
- **BPMN вместо ES в начале работы**: начинать с детального BPMN до понимания общей картины → уходить в детали
- **Смешивать модели**: рисовать в одной диаграмме и ES-события и BPMN-потоки → путаница
- **Не обновлять диаграммы**: диаграмма из прошлого спринта без обновления → вводит в заблуждение
- **Sequence Diagram без группировки**: огромная диаграмма на 50 шагов → нечитаемо; разбивать на сценарии
