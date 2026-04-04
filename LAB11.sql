-- Задание 1. Представление — сводка по добыче (простое)
-- Создание представления v_daily_production_summary
CREATE OR REPLACE VIEW v_daily_production_summary AS
SELECT
    d.full_date,
    m.mine_name,
    s.shift_name,
    COUNT(*) AS record_count,
    SUM(fp.tons_mined) AS total_tons,
    SUM(fp.fuel_consumed_l) AS total_fuel,
    ROUND(AVG(fp.trips_count), 2) AS avg_trips
FROM
    fact_production AS fp
JOIN
    dim_date AS d ON fp.date_id = d.date_id
JOIN
    dim_mine AS m ON fp.mine_id = m.mine_id
JOIN
    dim_shift AS s ON fp.shift_id = s.shift_id
GROUP BY
    d.full_date,
    m.mine_name,
    s.shift_name;

-- Проверка представления: данные за март 2024, шахта «Северная», записей > 5
SELECT
    full_date,
    mine_name,
    shift_name,
    record_count,
    total_tons,
    total_fuel,
    avg_trips
FROM
    v_daily_production_summary
WHERE
    mine_name = 'Северная'
    AND full_date >= '2024-03-01'
    AND full_date <= '2024-03-31'
    AND record_count > 5
ORDER BY
    full_date,
    shift_name;

-- ============================================================================

-- Задание 2. Представление с ограничением обновления (простое)
-- Создание представления v_unplanned_downtime с WITH CHECK OPTION
CREATE OR REPLACE VIEW v_unplanned_downtime AS
SELECT
    downtime_id,
    date_id,
    equipment_id,
    reason_id,
    start_time,
    end_time,
    duration_min,
    is_planned,
    comment,
    loaded_at
FROM
    fact_equipment_downtime
WHERE
    is_planned = FALSE
WITH CHECK OPTION;

-- Проверка: количество записей в представлении
SELECT
    COUNT(*) AS unplanned_count
FROM
    v_unplanned_downtime;

-- Проверка: количество записей в базовой таблице (для сравнения)
SELECT
    COUNT(*) AS total_count,
    COUNT(*) FILTER (WHERE is_planned = FALSE) AS unplanned_count,
    COUNT(*) FILTER (WHERE is_planned = TRUE) AS planned_count
FROM
    fact_equipment_downtime;

-- ============================================================================
-- Объяснение WITH CHECK OPTION:
--
-- Вопрос: Что произойдёт при попытке выполнить:
-- INSERT INTO v_unplanned_downtime (..., is_planned, ...) VALUES (..., TRUE, ...)?
--
-- Ответ: ОШИБКА! WITH CHECK OPTION запрещает вставку или обновление строк,
--        которые не удовлетворяют условию WHERE представления.
--
--        PostgreSQL вернёт ошибку:
--        ERROR:  new row violates check option for view "v_unplanned_downtime"
--
--        Это гарантирует целостность данных — через представление нельзя
--        добавить плановый простой, так как оно предназначено только для
--        внеплановых простоев.
-- ============================================================================


-- Задание 3. Материализованное представление для качества руды (среднее)
-- Создание материализованного представления mv_monthly_ore_quality
CREATE MATERIALIZED VIEW mv_monthly_ore_quality AS
SELECT
    m.mine_name,
    TO_CHAR(TO_DATE(d.date_id::VARCHAR, 'YYYYMMDD'), 'YYYY-MM') AS year_month,
    COUNT(*) AS sample_count,
    ROUND(AVG(oq.fe_content), 2) AS avg_fe,
    ROUND(MIN(oq.fe_content), 2) AS min_fe,
    ROUND(MAX(oq.fe_content), 2) AS max_fe,
    ROUND(AVG(oq.sio2_content), 2) AS avg_sio2,
    ROUND(AVG(oq.moisture), 2) AS avg_moisture
FROM
    fact_ore_quality AS oq
JOIN
    dim_mine AS m ON oq.mine_id = m.mine_id
JOIN
    dim_date AS d ON oq.date_id = d.date_id
GROUP BY
    m.mine_name,
    TO_CHAR(TO_DATE(d.date_id::VARCHAR, 'YYYYMMDD'), 'YYYY-MM');

-- Создание индекса по mine_name и year_month
CREATE INDEX IF NOT EXISTS idx_mv_ore_quality_mine_month
ON mv_monthly_ore_quality (mine_name, year_month);

-- Запрос к материализованному представлению (EXPLAIN ANALYZE)
EXPLAIN ANALYZE
SELECT
    mine_name,
    year_month,
    sample_count,
    avg_fe,
    min_fe,
    max_fe,
    avg_sio2,
    avg_moisture
FROM
    mv_monthly_ore_quality
WHERE
    mine_name = 'Северная'
    AND year_month = '2024-03'
ORDER BY
    year_month;

-- Аналогичный запрос напрямую к таблицам (для сравнения)
EXPLAIN ANALYZE
SELECT
    m.mine_name,
    TO_CHAR(TO_DATE(d.date_id::VARCHAR, 'YYYYMMDD'), 'YYYY-MM') AS year_month,
    COUNT(*) AS sample_count,
    ROUND(AVG(oq.fe_content), 2) AS avg_fe,
    ROUND(MIN(oq.fe_content), 2) AS min_fe,
    ROUND(MAX(oq.fe_content), 2) AS max_fe,
    ROUND(AVG(oq.sio2_content), 2) AS avg_sio2,
    ROUND(AVG(oq.moisture), 2) AS avg_moisture
FROM
    fact_ore_quality AS oq
JOIN
    dim_mine AS m ON oq.mine_id = m.mine_id
JOIN
    dim_date AS d ON oq.date_id = d.date_id
WHERE
    m.mine_name = 'Северная'
    AND d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    m.mine_name,
    TO_CHAR(TO_DATE(d.date_id::VARCHAR, 'YYYYMMDD'), 'YYYY-MM')
ORDER BY
    year_month;

-- Обновление материализованного представления
REFRESH MATERIALIZED VIEW mv_monthly_ore_quality;

-- ============================================================================
-- Вопрос: Какой индекс нужен для REFRESH ... CONCURRENTLY?
--
-- Ответ: Для REFRESH MATERIALIZED VIEW CONCURRENTLY требуется уникальный индекс
-- хотя бы на одном столбце материализованного представления.

--Пример создания уникального индекса:
--CREATE UNIQUE INDEX idx_mv_ore_quality_unique
--ON mv_monthly_ore_quality (mine_name, year_month);

--После этого можно выполнять:
--REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_ore_quality;

--Преимущество CONCURRENTLY: не блокирует чтение во время обновления
-- ============================================================================

-- ============================================================================

-- Задание 4. Производная таблица — ранжирование операторов (среднее)
-- Запрос с производной таблицей (подзапрос в FROM) и ROW_NUMBER
SELECT
    shift_name,
    full_name,
    total_mined,
    rn
FROM
    (
        SELECT
            s.shift_name,
            o.last_name || ' ' || o.first_name || ' ' || COALESCE(o.middle_name, '') AS full_name,
            SUM(fp.tons_mined) AS total_mined,
            ROW_NUMBER() OVER (
                PARTITION BY s.shift_id
                ORDER BY SUM(fp.tons_mined) DESC
            ) AS rn
        FROM
            fact_production AS fp
        JOIN
            dim_operator AS o ON fp.operator_id = o.operator_id
        JOIN
            dim_shift AS s ON fp.shift_id = s.shift_id
        JOIN
            dim_date AS d ON fp.date_id = d.date_id
        WHERE
            d.date_id BETWEEN 20240101 AND 20240331
        GROUP BY
            s.shift_id,
            s.shift_name,
            o.operator_id,
            o.last_name,
            o.first_name,
            o.middle_name
    ) AS ranked_operators
WHERE
    rn = 1
ORDER BY
    shift_name;



-- ============================================================================
-- Сравнение SQL и DAX подходов
-- ============================================================================

-- Преимущества SQL ROW_NUMBER:
-- 1. Более читаемый синтаксис
-- 2. Лучшая производительность на больших данных
-- 3. Поддержка оконных функций
--
-- Преимущества DAX TOPN:
-- 1. Интеграция с моделью данных
-- 2. Автоматическая оптимизация движком VertiPaq
-- 3. Упрощённая работа с контекстом фильтра
-- ============================================================================



-- Задание 5. CTE — комплексный отчёт по эффективности (среднее)
-- Отчёт «Доступность оборудования по шахтам» за I квартал 2024

WITH production_cte AS (
    SELECT
        fp.mine_id,
        SUM(fp.operating_hours) AS operating_hours,
        SUM(fp.tons_mined) AS total_tons
    FROM
        fact_production AS fp
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        fp.mine_id
),
downtime_cte AS (
    SELECT
        e.mine_id,
        SUM(f.duration_min) / 60.0 AS downtime_hours
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_equipment AS e ON f.equipment_id = e.equipment_id
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        e.mine_id
)
SELECT
    m.mine_name,
    COALESCE(p.operating_hours, 0) AS operating_hours,
    COALESCE(d.downtime_hours, 0) AS downtime_hours,
    COALESCE(p.total_tons, 0) AS total_tons,
    ROUND(
        COALESCE(p.operating_hours, 0) / 
        NULLIF(COALESCE(p.operating_hours, 0) + COALESCE(d.downtime_hours, 0), 0) * 100,
        2
    ) AS availability_pct
FROM
    dim_mine AS m
LEFT JOIN
    production_cte AS p ON m.mine_id = p.mine_id
LEFT JOIN
    downtime_cte AS d ON m.mine_id = d.mine_id
WHERE
    m.status = 'active'
ORDER BY
    availability_pct ASC;




-- Задание 6. Табличная функция — отчёт по простоям 
CREATE OR REPLACE FUNCTION fn_equipment_downtime_report(
    p_equipment_id INT,
    p_date_from INT,
    p_date_to INT
)
RETURNS TABLE (
    full_date DATE,
    reason_name VARCHAR,
    reason_category VARCHAR,
    duration_min NUMERIC,
    duration_hours NUMERIC,
    is_planned BOOLEAN,
    comment TEXT
)
LANGUAGE sql
AS $$
    SELECT
        d.full_date,
        r.reason_name,
        r.category AS reason_category,
        f.duration_min,
        ROUND(f.duration_min / 60.0, 1) AS duration_hours,
        f.is_planned,
        f.comment
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    JOIN
        dim_downtime_reason AS r ON f.reason_id = r.reason_id
    WHERE
        f.equipment_id = p_equipment_id
        AND f.date_id BETWEEN p_date_from AND p_date_to
    ORDER BY
        d.full_date;
$$;

-- Вызов функции для equipment_id = 3 за январь 2024
SELECT * FROM fn_equipment_downtime_report(3, 20240101, 20240131);

-- Вызов функции через LATERAL JOIN для всех единиц оборудования шахты mine_id = 1
SELECT
    e.equipment_id,
    e.equipment_name,
    fdr.full_date,
    fdr.reason_name,
    fdr.reason_category,
    fdr.duration_min,
    fdr.duration_hours,
    fdr.is_planned,
    fdr.comment
FROM
    dim_equipment AS e
CROSS JOIN LATERAL
    fn_equipment_downtime_report(e.equipment_id, 20240101, 20240131) AS fdr
WHERE
    e.mine_id = 1
ORDER BY
    e.equipment_name,
    fdr.full_date;




-- Задание 7. Рекурсивный CTE — иерархия локаций (сложное)
-- Прямой обход: от корня к забоям

WITH RECURSIVE location_tree AS (
    -- Базовый случай: корневые элементы (parent_id IS NULL)
    SELECT
        location_id,
        parent_id,
        location_name,
        location_type,
        0 AS depth,
        location_name::TEXT AS full_path,
        ''::TEXT AS indentation
    FROM
        dim_location_hierarchy
    WHERE
        parent_id IS NULL
    
    UNION ALL
    
    -- Рекурсивный случай: дочерние элементы
    SELECT
        l.location_id,
        l.parent_id,
        l.location_name,
        l.location_type,
        lt.depth + 1 AS depth,
        lt.full_path || ' → ' || l.location_name AS full_path,
        REPEAT('  ', lt.depth + 1) AS indentation
    FROM
        dim_location_hierarchy AS l
    JOIN
        location_tree AS lt ON l.parent_id = lt.location_id
)
SELECT
    indentation || location_name AS hierarchy,
    location_type,
    full_path,
    depth
FROM
    location_tree
ORDER BY
    full_path;

-- ============================================================================
-- Обратный обход: от забоя (location_id = 13) до корня шахты
-- ============================================================================

WITH RECURSIVE location_path AS (
    -- Базовый случай: начальный элемент (забой)
    SELECT
        location_id,
        parent_id,
        location_name,
        location_type,
        0 AS depth,
        location_name::TEXT AS full_path
    FROM
        dim_location_hierarchy
    WHERE
        location_id = 13
    
    UNION ALL
    
    -- Рекурсивный случай: родительские элементы
    SELECT
        l.location_id,
        l.parent_id,
        l.location_name,
        l.location_type,
        lp.depth + 1 AS depth,
        l.location_name || ' → ' || lp.full_path AS full_path
    FROM
        dim_location_hierarchy AS l
    JOIN
        location_path AS lp ON l.location_id = lp.parent_id
)
SELECT
    location_name,
    location_type,
    full_path,
    depth
FROM
    location_path
ORDER BY
    depth ASC;

-- ============================================================================

-- Задание 8. Рекурсивный CTE — генерация календаря и заполнение пропусков (сложное)
-- Генерация последовательности дат за февраль 2024

WITH RECURSIVE date_range AS (
    -- Базовый случай: первая дата февраля
    SELECT
        DATE '2024-02-01'::DATE AS current_date,
        DATE '2024-02-29'::DATE AS end_date
    
    UNION ALL
    
    -- Рекурсивный случай: следующая дата
    SELECT
        (current_date + INTERVAL '1 day')::DATE,
        end_date
    FROM
        date_range
    WHERE
        current_date < end_date
),
production_dates AS (
    -- Даты с добычей для шахты mine_id = 1
    SELECT DISTINCT
        fp.date_id
    FROM
        fact_production AS fp
    WHERE
        fp.mine_id = 1
        AND fp.date_id BETWEEN 20240201 AND 20240229
),
missing_days AS (
    -- Дни без добычи (LEFT JOIN + IS NULL)
    SELECT
        dr.current_date AS full_date,
        TO_CHAR(dr.current_date, 'Day') AS day_name,
        TO_CHAR(dr.current_date, 'ID')::INT AS day_of_week,
        CASE
            WHEN TO_CHAR(dr.current_date, 'ID')::INT <= 5 THEN 'рабочий'
            ELSE 'выходной'
        END AS day_type,
        pd.date_id AS production_date_id
    FROM
        date_range AS dr
    LEFT JOIN
        production_dates AS pd ON TO_CHAR(dr.current_date, 'YYYYMMDD')::INT = pd.date_id
    WHERE
        pd.date_id IS NULL  -- Только дни без добычи
)
SELECT
    full_date,
    TRIM(day_name) AS day_name,
    day_of_week,
    day_type
FROM
    missing_days
WHERE
    day_type = 'рабочий'  -- Только рабочие дни
ORDER BY
    full_date;

-- ============================================================================
-- Подсчёт потерянных рабочих дней
-- ============================================================================

WITH RECURSIVE date_range AS (
    SELECT
        DATE '2024-02-01'::DATE AS current_date,
        DATE '2024-02-29'::DATE AS end_date
    
    UNION ALL
    
    SELECT
        (current_date + INTERVAL '1 day')::DATE,
        end_date
    FROM
        date_range
    WHERE
        current_date < end_date
),
production_dates AS (
    SELECT DISTINCT
        fp.date_id
    FROM
        fact_production AS fp
    WHERE
        fp.mine_id = 1
        AND fp.date_id BETWEEN 20240201 AND 20240229
)
SELECT
    COUNT(*) AS lost_working_days,
    STRING_AGG(
        TO_CHAR(dr.current_date, 'DD.MM.YYYY'),
        ', '
        ORDER BY dr.current_date
    ) AS lost_dates
FROM
    date_range AS dr
LEFT JOIN
    production_dates AS pd ON TO_CHAR(dr.current_date, 'YYYYMMDD')::INT = pd.date_id
WHERE
    pd.date_id IS NULL
    AND TO_CHAR(dr.current_date, 'ID')::INT <= 5;  -- Только рабочие дни (Пн-Пт)

-- ============================================================================
-- Сравнение SQL и DAX подходов
-- ============================================================================
--
-- Задание 7 (Иерархия):
--                SQL              |            DAX
--                                 |
-- WITH RECURSIVE ... UNION ALL    | PATH() + PATHLENGTH()
-- Рекурсивный обход дерева        | Декларативное построение пути
-- REPEAT('  ', depth) для отступа | REPT("  ", depth) для отступа
-- Прямой и обратный обход         | Только прямой (PATH строит от листа к корню)
--
-- Задание 8 (Календарь):
-- SQL                            | DAX
--                                |
-- Рекурсивный CTE для дат        | dim_date уже содержит все даты
-- GENERATESERIES (PostgreSQL 14+)| GENERATESERIES() в DAX
-- LEFT JOIN + IS NULL            | FILTER + NOT IN
-- Подсчёт пропущенных дней       | COUNTROWS + FILTER
--
-- Преимущества SQL рекурсии:
-- 1. Полный контроль над обходом иерархии
-- 2. Поддержка прямого и обратного обхода
-- 3. Генерация последовательностей без справочников
--
-- Преимущества DAX PATH:
-- 1. Проще синтаксис для иерархий
-- 2. Интеграция с визуализациями Power BI
-- 3. Автоматическая оптимизация движком
-- ============================================================================

-- Задание 9. CTE для скользящего среднего (сложное)
WITH daily_production AS (
    SELECT
        d.date_id,
        d.full_date,
        SUM(fp.tons_mined) AS daily_tons
    FROM
        fact_production AS fp
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        fp.mine_id = 1
        AND d.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        d.date_id,
        d.full_date
),
moving_stats AS (
    SELECT
        date_id,
        full_date,
        daily_tons,
        AVG(daily_tons) OVER (
            ORDER BY date_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS moving_avg_7d,
        MAX(daily_tons) OVER (
            ORDER BY date_id
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS moving_max_7d
    FROM
        daily_production
)
SELECT
    full_date,
    daily_tons,
    ROUND(moving_avg_7d, 2) AS moving_avg_7d,
    ROUND((daily_tons - moving_avg_7d) / NULLIF(moving_avg_7d, 0) * 100, 1) AS deviation_pct,
    CASE
        WHEN ABS((daily_tons - moving_avg_7d) / NULLIF(moving_avg_7d, 0) * 100) > 20 THEN 'Аномалия'
        ELSE ''
    END AS anomaly_flag
FROM
    moving_stats
ORDER BY
    date_id;



DROP VIEW IF EXISTS v_ore_quality_detail;
DROP FUNCTION IF EXISTS fn_ore_quality_stats(INT, INT, INT);
    
    
    
    
    
    
    
    
    

DROP VIEW IF EXISTS v_daily_production_summary;
DROP VIEW IF EXISTS v_unplanned_downtime;
DROP MATERIALIZED VIEW IF EXISTS mv_monthly_ore_quality;
DROP INDEX IF EXISTS idx_mv_ore_quality_mine_month;
DROP INDEX IF EXISTS idx_mv_ore_quality_unique;
DROP FUNCTION IF EXISTS fn_equipment_downtime_report(INT, INT, INT);




DROP MATERIALIZED VIEW IF EXISTS mv_monthly_ore_quality;
DROP INDEX IF EXISTS idx_mv_ore_quality_mine_month;
DROP INDEX IF EXISTS idx_mv_ore_quality_unique;


DROP VIEW IF EXISTS v_daily_production_summary;
DROP VIEW IF EXISTS v_unplanned_downtime;
