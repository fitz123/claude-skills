---
title: "Поиск неявных характеристик (5 источников)"
domain: systems-design
tags: [quality-attributes, analysis, methodology, requirements]
keywords: [неявные характеристики, implicit, фразы-маркеры, time to market, домен, lifecycle, цели компании]
related: [quality-attributes.md, quality-attribute-scenarios.md, company-lifecycle.md, stakeholder-matrix.md, subdomains.md, requirements-gathering.md]
source: "Systems Analysis Course, Lesson 2"
---

## Определение

Архитектурные характеристики бывают **явные** (explicit) — прямо указаны в требованиях или легко вытащить из людей — и **неявные** (implicit) — не лежат на поверхности, бизнес о них не думает, но они критичны.

**Явные** примеры: «20К пользователей, 2000 активных подписок, пик до 10К в праздники» → Scalability.

**Неявные** примеры: maintainability, evolvability, modifiability — никто не скажет цифру, но без них система скатится в big ball of mud.

Для поиска неявных характеристик существуют **5 источников**.

## Когда применять

- При анализе требований нового проекта
- Когда бизнес отвечает «всё важно» или «не знаю» на вопросы о характеристиках
- При выборе архитектурного стиля — нужно понять, какие характеристики неявно требуются
- При анализе поддоменов: каждый тип поддомена подразумевает свои характеристики

## Как применять

### Источник 1: Разговор с людьми — фразы-маркеры

Бизнес рассказывает о характеристиках, сам не понимая того. Пять ключевых фраз-маркеров:

| Фраза бизнеса | Характеристики |
|---|---|
| **Слияния и поглощения** (M&A) | Interoperability, Scalability, Adaptability, Extensibility |
| **Время выхода на рынок** (Time to market) | Agility, Testability, Deployability |
| **Удовлетворённость пользователей** | Performance, Availability, Fault tolerance, Testability, Deployability, Agility, Security |
| **Конкурентное преимущество** | Agility, Testability, Deployability, Scalability, Availability, Fault tolerance |
| **Время и бюджет** | Simplicity, Feasibility |

⚠️ Каждая фраза-маркер без числа — абстракция. Обязательно уточняй: «time to market» → «фичи выкатываются максимум за два недельных спринта».

### Источник 2: Изучение требований

Берёшь явную характеристику и делаешь предположения о неявных:
- Если есть данные о пиковой нагрузке → думай об Elasticity
- Многоязычность → Localization
- Интеграции с внешними системами → Configurability, Extensibility, Reuse
- Работа с сетью → Authorization, Authentication, Security, Robustness
- Сложная система ролей → Securability

### Источник 3: Цели компании

Цели бизнеса напрямую влияют на характеристики:
- EdTech с целью «вовлечённость и доходимость» → Usability, Simplicity (без них пользователи отваливаются)
- Core-поддомены (сложные, часто меняются) → Availability, Extensibility, Modifiability, Maintainability
- Generic-поддомены → Supportability, Installability
- Supporting-поддомены → Maintainability, Readability

### Источник 4: Специфика домена

У каждого домена есть характерные скрытые требования:
- Финтех → Privacy, Security, Consistency (неявно обязательны)
- Медицина → Compliance, Auditability, Availability
- E-commerce в праздники → Elasticity (пиковая нагрузка)
- Биржа → Performance (особенно в момент открытия/закрытия торгов)

### Источник 5: Этап жизни компании

Разные стадии требуют разных характеристик (подробнее в `company-lifecycle.md`):
- Стартап/гипотезы → Simplicity, Feasibility, Modifiability
- Расширение → Scalability, Modifiability, Maintainability, Testability, Agility
- Захват рынка → Availability, Scalability, Performance
- Зрелая компания → Maintainability, Extensibility

## Примеры

**Кейс Happy Cat Box (курс):**
- Явные: 20К пользователей, 2000 активных, пик 10К → Scalability + Elasticity
- Фраза «минимальный Time to Market» + уточнение «за 2 спринта» → Agility, Testability, Deployability
- Core-поддомены «мэтчинг» и «тестирование игрушек» → Modifiability, Evolvability
- Стадия «расширение» → Scalability, Modifiability, Maintainability, Testability, Agility, Evolvability

**Применительно к КИБЕР-ГЕНПОДРЯД:**
- Фраза «контроль с объекта в реальном времени» → Performance, Availability
- Финансовые документы КС-2, КС-3 → Consistency, Auditability, Security
- Стадия: ранний рост → Simplicity + Modifiability (менять под разных заказчиков)
- Домен строительства с госрегуляцией → Compliance, Auditability

## Anti-patterns

- **Задавать прямой вопрос «какие у вас характеристики?»** — бизнес не знает этого языка, нужно слушать фразы-маркеры
- **Брать только явные характеристики** — главные риски обычно скрыты в неявных
- **Определять без валидации** — нельзя на 100% верно определить все характеристики; важно согласовать предположения с заинтересованными лицами
- **Игнорировать тип поддомена** — core требует других характеристик, чем supporting; перепутаешь — потратишь дорогих людей не туда
- **Не уточнять абстракции** — «высокая удовлетворённость» без числа → нет измеримого критерия → нельзя проверить
