# Диаграмма последовательности: Интеграционные сценарии

## 1. Назначение документа

Документ описывает два ключевых сквозных сценария взаимодействия компонентов микросервиса NSI Nomenclature Service:

### 1. Сценарий чтения: Динамическая фильтрация параметров на форме с применением двухуровневого доступа (Redis Cache → SQL).

### 2. Сценарий записи: Валидация входных данных, дедупликация, транзакционная фиксация в БД и асинхронное вещание мастер-записи подписчикам через Apache Kafka.

## 2. Диаграмма последовательности

```mermaid
sequenceDiagram
    autonumber
    actor User as Инженер (Web UI)
    participant SPA as Web Frontend (MDM)
    participant API as NSI Core API
    participant Redis as Redis Cache
    participant DB as SQL
    participant Kafka as Apache Kafka
    participant ERP as 1C:ERP Consumer
    participant WMS as WMS Consumer

    %% Сценарий 1: Динамическая фильтрация параметров
    rect rgb(240, 248, 255)
    Note over User, DB: Сценарий 1: Запрос допустимых длин (Мастер-фильтр)
    User->>SPA: Выбор ГОСТ 7798-70 и диаметра d=12 мм
    SPA->>API: GET /api/v1/parameters/lengths?gost_id=1&diameter_id=4
    API->>Redis: GET lengths:gost:1:dia:4
    alt Cache Hit (Данные найдены в кэше)
        Redis-->>API: 200 OK [16, 18, 20, ..., 260]
    else Cache Miss (Данных в кэше не найдено)
        API->>DB: SELECT length_id FROM GOST_DIAMETER_LENGTH WHERE gost_id=1 AND diameter_id=4
        DB-->>API: Результат выборки
        API->>Redis: SETEX lengths:gost:1:dia:4 86400 (TTL 24h)
    end
    API-->>SPA: 200 OK (JSON массив доступных длин)
    SPA-->>User: Разблокировка выпадающего списка "Длина"
    end

    %% Сценарий 2: Генерация, валидация и публикация
    rect rgb(245, 255, 245)
    Note over User, WMS: Сценарий 2: Валидация, дедупликация и асинхронная доставка
    User->>SPA: Нажатие кнопки "Сгенерировать и создать"
    SPA->>API: POST /api/v1/nomenclature/generate (JSON payload)
    
    API->>API: 1. Валидация по правилам ГОСТ 1759.0-87
    API->>API: 2. Конкатенация строки: "Болт М12-6g×60.58 ГОСТ 7798-70"
    
    API->>DB: 3. Поиск дубликата: SELECT id FROM NOMENCLATURE WHERE LOWER(REPLACE(generated_name, 'x', '×')) = LOWER(REPLACE($1, 'x', '×'))
    
    alt Дубликат обнаружен (count > 0)
        DB-->>API: Найден существующий id (UUID)
        API-->>SPA: 409 Conflict (Ошибка: запись уже существует)
        SPA-->>User: Модальное окно с предупреждением и ссылкой на существующий ID
    else Запись уникальна (count = 0)
        DB-->>API: 0 записей
        API->>DB: 4. INSERT INTO NOMENCLATURE (...) VALUES (...)
        DB-->>API: 1 row inserted (Commit)
        
        API->>Kafka: 5. Publish to topic 'mdm.nomenclature.events' (Event: NomenclatureCreated)
        Kafka-->>API: ACK (Message offset committed)
        
        API-->>SPA: 201 Created (JSON с ID и эталонной строкой)
        SPA-->>User: Отображение карточки созданной мастер-записи
        
        par Асинхронная доставка мастер-данных в системы-потребители
            Kafka->>ERP: Consumer: NomenclatureCreated
            ERP->>ERP: Фоновое создание карточки в справочнике 1С
        and
            Kafka->>WMS: Consumer: NomenclatureCreated
            WMS->>WMS: Фоновое создание SKU в складской базе
        end
    end
    end
```
## 3. Детализация механизмов отказоустойчивости
### 1. Кэширование со стратегией Cache-Aside:
* Сервис проверяет ключ в Redis. При отсутствии данных выполняется обращение к SQL с последующим заполнением кэша с временем жизни TTL = 86400 сек (24 часа).
### 2. Дедупликация и нормализация "на лету":
* Проверка уникальности использует SQL-функцию REPLACE для приведения символов умножения к стандарту × (U+00D7), что предотвращает создание дублей при наличии исторических опечаток в базах-потребителях.
### 3. Гарантия доставки сообщений:
* Публикация в Kafka выполняется только после успешного коммита транзакции в SQL (INSERT).
Подтверждение от брокера Kafka гарантирует репликацию события в кластере до возврата ответа 201 Created пользователю.
