-- ============================================================================
-- ЗАДАНИЕ 1. Скалярная функция — расчёт OEE (простое)
-- ============================================================================

CREATE OR REPLACE FUNCTION calc_oee(
    p_operating_hours NUMERIC,
    p_planned_hours NUMERIC,
    p_actual_tons NUMERIC,
    p_target_tons NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN p_planned_hours = 0 OR p_target_tons = 0 THEN NULL
            ELSE ROUND(
                (p_operating_hours / p_planned_hours) * 
                (p_actual_tons / p_target_tons) * 100,
                1
            )
        END;
$$;

-- Тестирование функции
SELECT
    calc_oee(10, 12, 80, 100) AS test_1,  
    calc_oee(12, 12, 100, 100) AS test_2,  
    calc_oee(8, 12, 0, 100) AS test_3;     

-- Использование в запросе к fact_production
SELECT
    e.equipment_name,
    SUM(fp.operating_hours) AS total_operating,
    SUM(fp.operating_hours) * 1.2 AS planned_hours, 
    SUM(fp.tons_mined) AS actual_tons,
    SUM(fp.tons_mined) * 1.1 AS target_tons,       
    calc_oee(
        SUM(fp.operating_hours),
        SUM(fp.operating_hours) * 1.2,
        SUM(fp.tons_mined),
        SUM(fp.tons_mined) * 1.1
    ) AS oee_percent
FROM
    fact_production fp
JOIN
    dim_equipment e ON fp.equipment_id = e.equipment_id
WHERE
    fp.date_id BETWEEN 20240101 AND 20240131
GROUP BY
    e.equipment_name
ORDER BY
    oee_percent DESC
LIMIT 10;

-- ============================================================================
-- ЗАДАНИЕ 2. Функция с условной логикой — классификация простоев (простое)
-- ============================================================================

CREATE OR REPLACE FUNCTION classify_downtime(p_duration_min INT)
RETURNS VARCHAR
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT
        CASE
            WHEN p_duration_min < 15 THEN 'Микропростой'
            WHEN p_duration_min BETWEEN 15 AND 60 THEN 'Краткий простой'
            WHEN p_duration_min BETWEEN 61 AND 240 THEN 'Средний простой'
            WHEN p_duration_min BETWEEN 241 AND 480 THEN 'Длительный простой'
            ELSE 'Критический простой'
        END;
$$;

-- Применение к fact_equipment_downtime за январь 2024
WITH classified AS (
    SELECT
        classify_downtime(duration_min::INT) AS category,
        duration_min
    FROM
        fact_equipment_downtime
    WHERE
        date_id BETWEEN 20240101 AND 20240131
)
SELECT
    category,
    COUNT(*) AS incident_count,
    ROUND(AVG(duration_min), 1) AS avg_duration,
    ROUND(
        COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 2
    ) AS pct_of_total
FROM
    classified
GROUP BY
    category
ORDER BY
    avg_duration DESC;

-- ============================================================================
-- ЗАДАНИЕ 3. Табличная функция — детальный отчёт по оборудованию (среднее)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_equipment_summary(
    p_equipment_id INT,
    p_date_from INT,
    p_date_to INT
)
RETURNS TABLE (
    report_date DATE,
    tons_mined NUMERIC,
    trips INT,
    operating_hours NUMERIC,
    fuel_liters NUMERIC,
    tons_per_hour NUMERIC
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        d.full_date AS report_date,
        COALESCE(SUM(fp.tons_mined), 0) AS tons_mined,
        COALESCE(SUM(fp.trips_count), 0)::INT AS trips,
        COALESCE(SUM(fp.operating_hours), 0) AS operating_hours,
        COALESCE(SUM(fp.fuel_consumed_l), 0) AS fuel_liters,
        ROUND(
            COALESCE(SUM(fp.tons_mined), 0)::NUMERIC / 
            NULLIF(SUM(fp.operating_hours), 0), 2
        ) AS tons_per_hour
    FROM
        dim_date d
    LEFT JOIN
        fact_production fp ON d.date_id = fp.date_id
            AND fp.equipment_id = p_equipment_id
    WHERE
        d.date_id BETWEEN p_date_from AND p_date_to
    GROUP BY
        d.full_date
    ORDER BY
        d.full_date;
$$;

-- Тест 1: Для конкретного оборудования
SELECT * FROM get_equipment_summary(1, 20240101, 20240131);

-- Тест 2: В составе JOIN с LATERAL
SELECT
    e.equipment_name,
    s.report_date,
    s.tons_mined,
    s.operating_hours,
    s.tons_per_hour
FROM
    dim_equipment e
CROSS JOIN LATERAL
    get_equipment_summary(e.equipment_id, 20240101, 20240131) s
WHERE
    e.mine_id = 1
    AND s.tons_mined > 0
ORDER BY
    e.equipment_name,
    s.report_date
LIMIT 50;

-- ============================================================================
-- ЗАДАНИЕ 4. Функция с дефолтными параметрами — гибкий фильтр (среднее)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_production_filtered(
    p_date_from INT,
    p_date_to INT,
    p_mine_id INT DEFAULT NULL,
    p_shift_id INT DEFAULT NULL,
    p_equipment_type_id INT DEFAULT NULL
)
RETURNS TABLE (
    mine_name VARCHAR,
    shift_name VARCHAR,
    equipment_type VARCHAR,
    total_tons NUMERIC,
    total_trips BIGINT,
    equip_count BIGINT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        m.mine_name,
        s.shift_name,
        et.type_name AS equipment_type,
        SUM(fp.tons_mined) AS total_tons,
        SUM(fp.trips_count) AS total_trips,
        COUNT(DISTINCT fp.equipment_id) AS equip_count
    FROM
        fact_production fp
    JOIN
        dim_mine m ON fp.mine_id = m.mine_id
    JOIN
        dim_shift s ON fp.shift_id = s.shift_id
    JOIN
        dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN
        dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
    WHERE
        fp.date_id BETWEEN p_date_from AND p_date_to
        AND (p_mine_id IS NULL OR fp.mine_id = p_mine_id)
        AND (p_shift_id IS NULL OR fp.shift_id = p_shift_id)
        AND (p_equipment_type_id IS NULL OR e.equipment_type_id = p_equipment_type_id)
    GROUP BY
        m.mine_name,
        s.shift_name,
        et.type_name
    ORDER BY
        m.mine_name,
        s.shift_name,
        et.type_name;
$$;

-- Тест 1: Все данные
SELECT * FROM get_production_filtered(20240101, 20240131);

-- Тест 2: Только шахта 1 (именованный параметр)
SELECT * FROM get_production_filtered(20240101, 20240131, p_mine_id := 1);

-- Тест 3: Шахта 1, смена 1 (позиционные параметры)
SELECT * FROM get_production_filtered(20240101, 20240131, 1, 1);

-- Тест 4: Шахта 1, тип оборудования 2
SELECT * FROM get_production_filtered(20240101, 20240131, p_mine_id := 1, p_equipment_type_id := 2);



-- ============================================================================
-- ЗАДАНИЕ 5. Процедура с транзакциями — архивация данных (среднее)
-- ============================================================================

-- Создание таблицы-архива
CREATE TABLE IF NOT EXISTS archive_telemetry (LIKE fact_equipment_telemetry INCLUDING ALL);

-- Процедура архивации
CREATE OR REPLACE PROCEDURE archive_old_telemetry(
    p_before_date_id INT,
    INOUT p_archived INT,
    INOUT p_deleted INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Шаг 1: Копирование в архив
    INSERT INTO archive_telemetry
    SELECT * FROM fact_equipment_telemetry
    WHERE date_id < p_before_date_id;
    
    GET DIAGNOSTICS p_archived = ROW_COUNT;
    RAISE NOTICE 'Шаг 1: Архивировано % записей', p_archived;
    
    COMMIT;
    
    -- Шаг 2: Удаление из исходной таблицы
    DELETE FROM fact_equipment_telemetry
    WHERE date_id < p_before_date_id;
    
    GET DIAGNOSTICS p_deleted = ROW_COUNT;
    RAISE NOTICE 'Шаг 2: Удалено % записей', p_deleted;
    
    COMMIT;
    
    RAISE NOTICE 'Архивация завершена: archived=%, deleted=%', p_archived, p_deleted;
END;
$$;

-- Тестирование процедуры
CALL archive_old_telemetry(20240101, NULL, NULL);

-- Проверка результатов
SELECT 
    'fact_equipment_telemetry' AS table_name, 
    COUNT(*) AS row_count 
FROM fact_equipment_telemetry
UNION ALL
SELECT 
    'archive_telemetry', 
    COUNT(*) 
FROM archive_telemetry;



-- ============================================================================
-- ЗАДАНИЕ 6. Динамический SQL — универсальный счётчик (среднее)
-- ============================================================================

CREATE OR REPLACE FUNCTION count_fact_records(
    p_table_name TEXT,
    p_date_from INT,
    p_date_to INT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count BIGINT;
    v_sql TEXT;
BEGIN
    -- Проверка: имя таблицы должно начинаться с 'fact_'
    IF p_table_name NOT LIKE 'fact_%' THEN
        RAISE EXCEPTION 'Таблица должна начинаться с "fact_". Получено: %', p_table_name;
    END IF;
    
    -- Формирование динамического запроса
    v_sql := FORMAT(
        'SELECT COUNT(*) FROM %I WHERE date_id BETWEEN $1 AND $2',
        p_table_name
    );
    
    -- Выполнение с параметрами
    EXECUTE v_sql USING p_date_from, p_date_to INTO v_count;
    
    RAISE NOTICE 'Таблица %: % записей за период', p_table_name, v_count;
    
    RETURN v_count;
END;
$$;

-- Тестирование функции
SELECT count_fact_records('fact_production', 20240101, 20240131) AS production_count;
SELECT count_fact_records('fact_equipment_downtime', 20240101, 20240131) AS downtime_count;
SELECT count_fact_records('fact_ore_quality', 20240101, 20240131) AS quality_count;

-- Тест с ошибкой (должен вызвать EXCEPTION)
-- SELECT count_fact_records('dim_mine', 20240101, 20240131);

-- ============================================================================
-- ЗАДАНИЕ 7. Динамический SQL — построитель отчётов (сложное)
-- ============================================================================

CREATE OR REPLACE FUNCTION build_production_report(
    p_group_by TEXT,
    p_date_from INT,
    p_date_to INT,
    p_order_by TEXT DEFAULT 'total_tons DESC'
)
RETURNS TABLE (
    dimension_name VARCHAR,
    total_tons NUMERIC,
    total_trips BIGINT,
    avg_productivity NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_join TEXT;
    v_field TEXT;
    v_order TEXT;
    v_sql TEXT;
BEGIN
    -- Проверка и установка JOIN и поля группировки
    CASE p_group_by
        WHEN 'mine' THEN
            v_join := 'JOIN dim_mine d ON fp.mine_id = d.mine_id';
            v_field := 'd.mine_name';
        WHEN 'shift' THEN
            v_join := 'JOIN dim_shift d ON fp.shift_id = d.shift_id';
            v_field := 'd.shift_name';
        WHEN 'operator' THEN
            v_join := 'JOIN dim_operator d ON fp.operator_id = d.operator_id';
            v_field := 'd.last_name || '' '' || d.first_name';
        WHEN 'equipment' THEN
            v_join := 'JOIN dim_equipment d ON fp.equipment_id = d.equipment_id';
            v_field := 'd.equipment_name';
        WHEN 'equipment_type' THEN
            v_join := 'JOIN dim_equipment e ON fp.equipment_id = e.equipment_id JOIN dim_equipment_type d ON e.equipment_type_id = d.equipment_type_id';
            v_field := 'd.type_name';
        ELSE
            RAISE EXCEPTION 'Некорректный p_group_by: %. Допустимые: mine, shift, operator, equipment, equipment_type', p_group_by;
    END CASE;
    
    -- Проверка сортировки
    CASE p_order_by
        WHEN 'total_tons DESC', 'total_tons ASC', 'dimension_name ASC', 'dimension_name DESC' THEN
            v_order := p_order_by;
        ELSE
            RAISE EXCEPTION 'Некорректный p_order_by: %. Допустимые: total_tons DESC/ASC, dimension_name DESC/ASC', p_order_by;
    END CASE;
    
    -- Формирование запроса
    v_sql := FORMAT(
        $fmt$
        SELECT 
            %s::VARCHAR AS dimension_name,
            ROUND(SUM(fp.tons_mined), 2) AS total_tons,
            SUM(fp.trips_count)::BIGINT AS total_trips,
            ROUND(SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0), 2) AS avg_productivity
        FROM fact_production fp
        %s
        WHERE fp.date_id BETWEEN $1 AND $2
        GROUP BY 1
        ORDER BY %s
        $fmt$,
        v_field, v_join, v_order
    );
    
    -- Выполнение и возврат результата
    RETURN QUERY EXECUTE v_sql USING p_date_from, p_date_to;
END;
$$;

-- Тестирование всех вариантов группировки
SELECT * FROM build_production_report('mine', 20240101, 20240131);
SELECT * FROM build_production_report('shift', 20240101, 20240131);
SELECT * FROM build_production_report('equipment', 20240101, 20240131, 'total_tons DESC');
SELECT * FROM build_production_report('equipment_type', 20240101, 20240131, 'dimension_name ASC');







-- Удаление функций
DROP FUNCTION IF EXISTS calc_oee(NUMERIC, NUMERIC, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS classify_downtime(INT);
DROP FUNCTION IF EXISTS get_equipment_summary(INT, INT, INT);
DROP FUNCTION IF EXISTS get_production_filtered(INT, INT, INT, INT, INT);
DROP FUNCTION IF EXISTS count_fact_records(TEXT, INT, INT);
DROP FUNCTION IF EXISTS build_production_report(TEXT, INT, INT, TEXT);

-- Удаление процедур
DROP PROCEDURE IF EXISTS archive_old_telemetry(INT, INT, INT);
DROP PROCEDURE IF EXISTS process_daily_production(INT, INT, INT, INT);

-- Удаление тестовых таблиц
DROP TABLE IF EXISTS archive_telemetry;
DROP TABLE IF EXISTS staging_daily_production;
DROP TABLE IF EXISTS staging_rejected;