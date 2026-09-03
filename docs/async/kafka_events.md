# Спецификация асинхронных событий Apache Kafka

## 1. Параметры топика
Шина данных используется для асинхронного вещания созданных мастер-записей НСИ во внешние системы-потребители.

*   **Имя топика:** `mdm.nomenclature.events`
*   **Стратегия партиционирования:** `id` (UUID номенклатуры). Использование UUID гарантирует равномерное распределение сообщений по партициям кластера.
*   **Семантика доставки:** как минимум один раз. Потребители обязаны реализовывать идемпотентную обработку на основе `event_id` или `payload.id`.
*   **Формат сериализации:** JSON (UTF-8).

## 2. Структура заголовков сообщения

Каждое сообщение сопровождается метаданными для трассировки и маршрутизации:

| Заголовок | Тип данных | Пример значения | Описание |
| :--- | :--- | :--- | :--- |
| `event_id` | String | `9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d` | Уникальный идентификатор события |
| `event_type` | String | `NomenclatureCreated` | Тип бизнес-события |
| `source_system` | String | `nsi-core-api` | Сервис-источник события |
| `trace_id` | String | `4bf92f3577b34da6a3ce929d0e0e4736` | Сквозной идентификатор трейсинга OpenTelemetry |
| `created_at` | String | `2026-09-02T18:30:00Z` | Временная метка генерации события |

## 3. Схема полезной нагрузки

Спецификация структуры тела сообщения (`Payload`) для события `NomenclatureCreated`:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "NomenclatureCreatedEvent",
  "type": "object",
  "required": [
    "id",
    "generated_name",
    "gost",
    "parameters",
    "created_at"
  ],
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "Первичный ключ мастер-записи в NSI API"
    },
    "generated_name": {
      "type": "string",
      "description": "Эталонное наименование по ГОСТ 1759.0-87"
    },
    "gost": {
      "type": "object",
      "required": ["code", "accuracy_class"],
      "properties": {
        "code": { "type": "string", "example": "ГОСТ 7798-70" },
        "accuracy_class": { "type": "string", "enum": ["A", "B", "C"] },
        "tolerance": { "type": ["string", "null"], "example": "-6g" }
      }
    },
    "parameters": {
      "type": "object",
      "required": [
        "diameter",
        "length",
        "execution",
        "thread_step",
        "thread_direction",
        "material_grade"
      ],
      "properties": {
        "diameter": { "type": "number", "example": 12.0 },
        "length": { "type": "number", "example": 60.0 },
        "execution": { "type": "integer", "enum": [1, 2, 3, 4], "example": 2 },
        "thread_step": { "type": "number", "example": 1.25 },
        "thread_direction": { "type": "string", "enum": ["Right", "Left"], "example": "Left" },
        "s_size": { "type": ["number", "null"], "example": 18.0 },
        "metal_type": { "type": "string", "example": "Углеродистая сталь" },
        "material_class": { "type": "string", "example": "10.9" },
        "material_grade": { "type": "string", "example": "40Х" },
        "coating_code": { "type": ["string", "null"], "example": "01" },
        "coating_thickness": { "type": ["integer", "null"], "example": 15 }
      }
    },
    "created_at": {
      "type": "string",
      "format": "date-time"
    }
  }
}
```

## 4. Пример сообщения (JSON Payload)

Пример сообщения, публикуемого в топик при генерации высокопрочного болта:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "generated_name": "Болт 2М12×1,25-LH-6g×60.109.40Х.0115 (S18) ГОСТ 7798-70",
  "gost": {
    "code": "ГОСТ 7798-70",
    "accuracy_class": "B",
    "tolerance": "-6g"
  },
  "parameters": {
    "diameter": 12.0,
    "length": 60.0,
    "execution": 2,
    "thread_step": 1.25,
    "thread_direction": "Left",
    "s_size": 18.0,
    "metal_type": "Углеродистая сталь",
    "material_class": "10.9",
    "material_grade": "40Х",
    "coating_code": "01",
    "coating_thickness": 15
  },
  "created_at": "2026-09-02T18:30:00Z"
}
```

## 5. Регламент консьюмеров

| Система | Consumer Group ID | Реакция на событие `NomenclatureCreated` |
| :--- | :--- | :--- |
| **1C:ERP** | `1c-erp-nomenclature-sync` | Создание карточки в справочнике «Номенклатура» с заполнением реквизитов (вид номенклатуры, ставка НДС по умолчанию). |
| **WMS** | `wms-sku-generator` | Генерация складской карточки артикула и шаблона штрихкодирования ячейки хранения. |
| **B2B Portal** | `b2b-catalog-indexer` | Добавление позиции в поисковый индекс каталога закупок для поставщиков. |
