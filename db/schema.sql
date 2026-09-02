--Схема базы данных сервиса NSI Nomenclature Service


--1. Справочники стандартов и геометрии резьбы
CREATE TABLE gost (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,       --'7798-70', '7805-70', '15589-70'
    name VARCHAR(255) NOT NULL,
    accuracy_class VARCHAR(5) NOT NULL,      --'A', 'B', 'C'
    tolerance VARCHAR(10) NULL               --'-6g', '-8g' или NULL
);

CREATE TABLE diameter (
    id SERIAL PRIMARY KEY,
    value NUMERIC(6, 2) NOT NULL UNIQUE     --6.00, 8.00, 10.00, ..., 48.00
);

CREATE TABLE length (
    id SERIAL PRIMARY KEY,
    value NUMERIC(6, 2) NOT NULL UNIQUE     --8.00, 10.00, ..., 300.00
);

--2. Матрицы совместимости габаритов (таблицы-связки)
CREATE TABLE gost_diameter_param (
    id SERIAL PRIMARY KEY,
    gost_id INT NOT NULL REFERENCES gost(id) ON DELETE RESTRICT,
    diameter_id INT NOT NULL REFERENCES diameter(id) ON DELETE RESTRICT,
    step_coarse NUMERIC(4, 2) NOT NULL,
    step_fine_1 NUMERIC(4, 2) NULL,
    step_fine_2 NUMERIC(4, 2) NULL,
    has_alternative_s BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_gost_diameter UNIQUE (gost_id, diameter_id)
);

CREATE TABLE gost_diameter_length (
    id SERIAL PRIMARY KEY,
    gost_id INT NOT NULL REFERENCES gost(id) ON DELETE RESTRICT,
    diameter_id INT NOT NULL REFERENCES diameter(id) ON DELETE RESTRICT,
    length_id INT NOT NULL REFERENCES length(id) ON DELETE RESTRICT,
    is_recommended BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_gost_diameter_length UNIQUE (gost_id, diameter_id, length_id)
);

--3. Справочники материалов и покрытий
CREATE TABLE metal_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE        --'Углеродистая сталь', 'Нержавеющая сталь', 'Цветные сплавы'
);

CREATE TABLE material_class (
    id SERIAL PRIMARY KEY,
    metal_type_id INT NOT NULL REFERENCES metal_type(id) ON DELETE RESTRICT,
    code VARCHAR(50) NOT NULL,              --'5.8', '10.9' (для сталей) или '21', '32' (для групп)
    CONSTRAINT uq_metal_class UNIQUE (metal_type_id, code)
);

CREATE TABLE material_grade (
    id SERIAL PRIMARY KEY,
    class_id INT NOT NULL REFERENCES material_class(id) ON DELETE RESTRICT,
    name VARCHAR(50) NOT NULL,              --'40Х', '12Х18Н10Т', 'Л63'
    CONSTRAINT uq_class_grade UNIQUE (class_id, name)
);

CREATE TABLE coating (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,       --'01', '02', '05', '06', '11', '13'
    name VARCHAR(100) NOT NULL,
    requires_thickness BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE metal_type_coating (
    id SERIAL PRIMARY KEY,
    metal_type_id INT NOT NULL REFERENCES metal_type(id) ON DELETE RESTRICT,
    coating_id INT NOT NULL REFERENCES coating(id) ON DELETE RESTRICT,
    CONSTRAINT uq_metal_coating UNIQUE (metal_type_id, coating_id)
);

--4. Мастер-таблица сформированной номенклатуры
CREATE TABLE nomenclature (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    generated_name VARCHAR(500) NOT NULL,
    gost_id INT NOT NULL REFERENCES gost(id) ON DELETE RESTRICT,
    diameter_id INT NOT NULL REFERENCES diameter(id) ON DELETE RESTRICT,
    length_id INT NOT NULL REFERENCES length(id) ON DELETE RESTRICT,
    material_grade_id INT NOT NULL REFERENCES material_grade(id) ON DELETE RESTRICT,
    coating_id INT NULL REFERENCES coating(id) ON DELETE RESTRICT,
    coating_thickness INT NULL,
    execution INT NOT NULL DEFAULT 1 CHECK (execution IN (1, 2, 3, 4)),
    thread_step NUMERIC(4, 2) NOT NULL,
    thread_direction VARCHAR(10) NOT NULL DEFAULT 'Правая' CHECK (thread_direction IN ('Правая', 'Левая')),
    s_size NUMERIC(4, 2) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--5. Индексная стратегия
--Составной индекс по внешним ключам
CREATE INDEX idx_nomenclature_fk ON nomenclature (gost_id, diameter_id, length_id, material_grade_id);

--Функциональный уникальный индекс для дедупликации с нормализацией исторического текста (смотри ADR-001)
CREATE UNIQUE INDEX idx_nomenclature_normalized_name 
ON nomenclature (LOWER(REPLACE(generated_name, 'x', '×')));
