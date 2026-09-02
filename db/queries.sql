--Спецификация SQL-запросов сервиса NSI Nomenclature Service

--Запрос 1: Получение допустимых длин для Мастер-фильтра
--Назначение: Вызывается Backend-сервисом при Cache Miss в Redis.
--Параметры:
--$1 (INT) - id стандарта (например: 1 для ГОСТ 7798-70)
--$2 (INT) - id диаметра (например: 4 для d=12мм)
SELECT 
    l.id AS length_id,
    l.value AS length_value,
    gdl.is_recommended
FROM gost_diameter_length gdl
JOIN length l ON l.id = gdl.length_id
WHERE gdl.gost_id = $1 
  AND gdl.diameter_id = $2
ORDER BY l.value ASC;

--Запрос 2: Проверка уникальности наименования
--Назначение: Поиск коллизий перед выполнением INSERT.
--Используем idx_nomenclature_normalized_name.
--Параметры:
--$1 (VARCHAR) - Сгенерированная строка (например: 'Болт М12-6g×60.58 ГОСТ 7798-70')
SELECT 
    id, 
    generated_name, 
    created_at
FROM nomenclature
WHERE LOWER(REPLACE(generated_name, 'x', '×')) = LOWER(REPLACE($1, 'x', '×'))
LIMIT 1;

--Запрос 3: Получение доступных кодов покрытий по ветви металла
--Назначение: Динамическая фильтрация выпадающего списка покрытий в UI.
--Параметры:
--$1 (INT) - id типа металла (например: 1 для Углеродистой стали)
SELECT 
    c.id AS coating_id,
    c.code AS coating_code,
    c.name AS coating_name,
    c.requires_thickness
FROM metal_type_coating mtc
JOIN coating c ON c.id = mtc.coating_id
WHERE mtc.metal_type_id = $1
ORDER BY c.code ASC;

--Запрос 4: Аналитическая выборка покрытия матриц ГОСТ
--Назначение: Мониторинг наполненности справочников НСИ (сколько % геометрических сочетаний создано из возможных по стандарту).
WITH TheoreticalPermutations AS (
    SELECT 
        g.code AS gost_code,
        COUNT(*) AS total_possible_geometry
    FROM gost_diameter_length gdl
    JOIN gost g ON g.id = gdl.gost_id
    GROUP BY g.code
),
ActualNomenclature AS (
    SELECT 
        g.code AS gost_code,
        COUNT(n.id) AS total_created_items
    FROM nomenclature n
    JOIN gost g ON g.id = n.gost_id
    GROUP BY g.code
)
SELECT 
    tp.gost_code,
    tp.total_possible_geometry,
    COALESCE(an.total_created_items, 0) AS created_items,
    ROUND(
        (COALESCE(an.total_created_items, 0)::NUMERIC/NULLIF(tp.total_possible_geometry, 0)::NUMERIC) * 100, 
        2
    ) AS coverage_percent
FROM TheoreticalPermutations tp
LEFT JOIN ActualNomenclature an ON an.gost_code = tp.gost_code
ORDER BY tp.gost_code;
