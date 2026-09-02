# Реляционная модель данных

## 1. Архитектурные принципы проектирования БД
База данных сервиса спроектирована с учетом следующих требований:

1. **Третья нормальная форма:** Все неключевые атрибуты функционально зависят исключительно от первичных ключей, что исключает аномалии обновления и дублирование справочных данных.

2. **Ссылочная целостность:** Все связи между матрицами ограничений и справочниками защищены внешними ключами с правилом `ON DELETE RESTRICT`.

3. **Хранение атомарных параметров:** В транзакционную таблицу `NOMENCLATURE` сохраняется не только итоговая строка, но и внешние ключи на все выбранные физические параметры изделия для возможности последующей аналитики в ERP/WMS.

## 2. ER-диаграмма

```mermaid
erDiagram
    GOST {
        int id PK
        varchar code "Код стандарта, напр. 7798-70"
        varchar name "Наименование стандарта"
        varchar accuracy_class "Класс точности: A, B, C"
        varchar tolerance "Поле допуска: 6g, 8g или пусто"
    }

    DIAMETER {
        int id PK
        numeric value "Номинальный диаметр резьбы (d), мм"
    }

    LENGTH {
        int id PK
        numeric value "Номинальная длина болта (l), мм"
    }

    GOST_DIAMETER_PARAM {
        int id PK
        int gost_id FK "Ссылка на GOST"
        int diameter_id FK "Ссылка на DIAMETER"
        numeric step_coarse "Крупный (основной) шаг резьбы, мм"
        numeric step_fine_1 "Мелкий шаг 1, мм (nullable)"
        numeric step_fine_2 "Мелкий шаг 2, мм (nullable)"
        boolean has_alternative_s "Признак наличия альт. размера под ключ"
    }

    GOST_DIAMETER_LENGTH {
        int id PK
        int gost_id FK "Ссылка на GOST"
        int diameter_id FK "Ссылка на DIAMETER"
        int length_id FK "Ссылка на LENGTH"
        boolean is_recommended "Флаг применения (true - осн., false - не реком.)"
    }

    METAL_TYPE {
        int id PK
        varchar name "Ветвь металла: Углеродистая, Нержавеющая, Цветная"
    }

    MATERIAL_CLASS {
        int id PK
        int metal_type_id FK "Ссылка на METAL_TYPE"
        varchar code "Класс прочности (напр. 10.9) или Группа (напр. 21, 32)"
    }

    MATERIAL_GRADE {
        int id PK
        int class_id FK "Ссылка на MATERIAL_CLASS"
        varchar name "Марка стали или сплава (напр. 40Х, 12Х18Н10Т, Л63)"
    }

    COATING {
        int id PK
        varchar code "Двузначный цифровой код по ГОСТ 9.306"
        varchar name "Наименование покрытия"
        boolean requires_thickness "Флаг обязательности ввода толщины"
    }

    METAL_TYPE_COATING {
        int id PK
        int metal_type_id FK "Ссылка на METAL_TYPE"
        int coating_id FK "Ссылка на COATING"
    }

    NOMENCLATURE {
        uuid id PK "Глобальный идентификатор мастер-записи"
        varchar generated_name "Итоговая эталонная строка по ГОСТ"
        int gost_id FK "Ссылка на GOST"
        int diameter_id FK "Ссылка на DIAMETER"
        int length_id FK "Ссылка на LENGTH"
        int material_grade_id FK "Ссылка на MATERIAL_GRADE"
        int coating_id FK "Ссылка на COATING (nullable)"
        int coating_thickness "Толщина покрытия в мкм (nullable)"
        int execution "Исполнение изделия: 1, 2, 3, 4"
        numeric thread_step "Фактический шаг резьбы, мм"
        varchar thread_direction "Направление резьбы: Right, Left"
        numeric s_size "Фактический размер под ключ, мм (nullable)"
        timestamp created_at "Дата и время создания мастер-записи"
    }

    GOST ||--o{ GOST_DIAMETER_PARAM : "содержит параметры"
    DIAMETER ||--o{ GOST_DIAMETER_PARAM : "определен в"
    
    GOST ||--o{ GOST_DIAMETER_LENGTH : "разрешает длины"
    DIAMETER ||--o{ GOST_DIAMETER_LENGTH : "содержит длины"
    LENGTH ||--o{ GOST_DIAMETER_LENGTH : "разрешена для"
    
    METAL_TYPE ||--o{ MATERIAL_CLASS : "группирует"
    METAL_TYPE ||--o{ METAL_TYPE_COATING : "разрешает"
    COATING ||--o{ METAL_TYPE_COATING : "совместимо с"
    
    MATERIAL_CLASS ||--o{ MATERIAL_GRADE : "содержит"
    
    NOMENCLATURE }o--|| GOST : "ссылается на"
    NOMENCLATURE }o--|| DIAMETER : "ссылается на"
    NOMENCLATURE }o--|| LENGTH : "ссылается на"
    NOMENCLATURE }o--|| MATERIAL_GRADE : "ссылается на"
    NOMENCLATURE }o--o| COATING : "ссылается на"
```

## 3. Словарь данных

| Таблица | Назначение | Тип сущности |
| :--- | :--- | :--- |
| **`GOST`** | Реестр стандартов ГОСТ на крепежные изделия с базовыми параметрами. | Справочник |
| **`DIAMETER`** | Ряд номинальных диаметров метрической резьбы (d). | Справочник |
| **`LENGTH`** | Ряд номинальных длин болтов (l). | Справочник |
| **`GOST_DIAMETER_PARAM`** | Матрица соответствия стандартов, диаметров, основных и мелких шагов. | Таблица связей |
| **`GOST_DIAMETER_LENGTH`**| Матрица допустимых длин для каждого диаметра в разрезе стандарта. | Таблица связей |
| **`METAL_TYPE`** | Базовые ветви металлов (Углеродистая сталь, Нержавеющая сталь, Цветные сплавы). | Классификатор |
| **`MATERIAL_CLASS`** | Классы прочности углеродистых сталей и группы материалов сплавов. | Справочник |
| **`MATERIAL_GRADE`** | Перечень конкретных марок сталей и сплавов, разрешенных для классов/групп. | Справочник |
| **`COATING`** | Классификатор видов защитных покрытий по ГОСТ 9.306-85. | Справочник |
| **`METAL_TYPE_COATING`** | Матрица совместимости защитных покрытий с ветвями металлов. | Таблица связей |
| **`NOMENCLATURE`** | Реестр сформированных мастер-записей номенклатуры. | Транзакционная таблица |

## 4. Индексная стратегия

Для обеспечения высокой скорости поиска и исключения создания дубликатов на таблицу `NOMENCLATURE` накладываются следующие индексы:

1. **B-Tree Unique Index:**
   * `idx_nomenclature_unique_params` – составной уникальный индекс по физическим параметрам: `(gost_id, diameter_id, length_id, material_grade_id, COALESCE(coating_id, 0), COALESCE(coating_thickness, 0), execution, thread_step, thread_direction, COALESCE(s_size, 0))`.
2. **Functional Index (Нормализация исторических опечаток):**
   * `idx_nomenclature_normalized_name` – функциональный индекс по текстовому выражению:
     ```sql
     CREATE UNIQUE INDEX idx_nomenclature_normalized_name 
     ON NOMENCLATURE (LOWER(REPLACE(generated_name, 'x', '×')));
     ```
     Индекс гарантирует уникальность наименования вне зависимости от того, какой символ умножения (латинский `x` или типографский `×`) использовался при ручном вводе в смежных системах.
