CREATE EXTENSION IF NOT EXISTS tablefunc;

-- ============================================================================
-- ЗАДАНИЕ 1. ROLLUP — сменный рапорт с подитогами (простое)
-- ============================================================================

SELECT
    CASE WHEN GROUPING(m.mine_name) = 1 THEN '>>> ВСЕГО'
         ELSE m.mine_name
    END AS mine_name,
    CASE WHEN GROUPING(s.shift_name) = 1 THEN '-- Подитог --'
         ELSE s.shift_name
    END AS shift_name,
    SUM(fp.tons_mined) AS total_tons,
    COUNT(DISTINCT fp.equipment_id) AS equipment_count,
    GROUPING(m.mine_name) AS g_mine,
    GROUPING(s.shift_name) AS g_shift
FROM
    fact_production fp
JOIN
    dim_mine m ON fp.mine_id = m.mine_id
JOIN
    dim_shift s ON fp.shift_id = s.shift_id
WHERE
    fp.date_id = 20240115
GROUP BY
    ROLLUP(m.mine_name, s.shift_name)
ORDER BY
    g_mine, m.mine_name, g_shift, s.shift_name;

-- Ответ: 3×4 + 3 + 4 + 1 = 20 строк для 3 шахт и 4 типов

-- ============================================================================
-- ЗАДАНИЕ 2. CUBE — матрица «шахта × тип оборудования» (простое)
-- ============================================================================

SELECT
    CASE WHEN GROUPING(m.mine_name) = 1 THEN 'ВСЕ ШАХТЫ'
         ELSE m.mine_name
    END AS mine_name,
    CASE WHEN GROUPING(et.type_name) = 1 THEN 'ВСЕ ТИПЫ'
         ELSE et.type_name
    END AS type_name,
    GROUPING(m.mine_name) + GROUPING(et.type_name) AS grouping_level,
    SUM(fp.tons_mined) AS total_tons,
    ROUND(SUM(fp.tons_mined) / NULLIF(COUNT(DISTINCT fp.equipment_id), 0), 2) AS avg_tons_per_equip
FROM
    fact_production fp
JOIN
    dim_mine m ON fp.mine_id = m.mine_id
JOIN
    dim_equipment e ON fp.equipment_id = e.equipment_id
JOIN
    dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_date d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240101 AND 20240331
GROUP BY
    CUBE(m.mine_name, et.type_name)
ORDER BY
    grouping_level, mine_name, type_name;

-- Ответ на вопрос: Для 3 шахт и 4 типов:
-- Детальные: 3×4 = 12
-- Подитоги по шахтам: 3
-- Подитоги по типам: 4
-- Общий итог: 1
-- Итого: 12 + 3 + 4 + 1 = 20 строк

-- ============================================================================
-- ЗАДАНИЕ 3. GROUPING SETS — сводка KPI по нескольким срезам (среднее)
-- ============================================================================

SELECT
    CASE
        WHEN GROUPING(m.mine_name) = 0 THEN 'Шахта'
        WHEN GROUPING(s.shift_name) = 0 THEN 'Смена'
        WHEN GROUPING(et.type_name) = 0 THEN 'Тип оборудования'
        ELSE 'ИТОГО'
    END AS dimension,
    COALESCE(m.mine_name, s.shift_name, et.type_name, 'Все') AS dimension_value,
    SUM(fp.tons_mined) AS total_tons,
    SUM(fp.trips_count) AS total_trips,
    ROUND(SUM(fp.tons_mined)::NUMERIC / NULLIF(SUM(fp.trips_count), 0), 2) AS avg_tons_per_trip
FROM
    fact_production fp
LEFT JOIN dim_mine m ON fp.mine_id = m.mine_id
LEFT JOIN dim_shift s ON fp.shift_id = s.shift_id
LEFT JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
LEFT JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
WHERE
    fp.date_id BETWEEN 20240101 AND 20240131
GROUP BY
    GROUPING SETS (
        (m.mine_name),
        (s.shift_name),
        (et.type_name),
        ()
    )
ORDER BY
    dimension, dimension_value;


-- ============================================================================
-- ЗАДАНИЕ 4. Условная агрегация — PIVOT (среднее)
-- ============================================================================

-- Разворот: качество руды по шахтам и месяцам (1 полугодие 2024)
WITH monthly_fe AS (
    SELECT
        m.mine_name,
        EXTRACT(MONTH FROM d.full_date)::INT AS month_num,
        ROUND(AVG(oq.fe_content), 2) AS avg_fe
    FROM
        fact_ore_quality oq
    JOIN
        dim_mine m ON oq.mine_id = m.mine_id
    JOIN
        dim_date d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
    GROUP BY
        m.mine_name,
        EXTRACT(MONTH FROM d.full_date)
)
SELECT
    COALESCE(mine_name, '== ИТОГО ==') AS mine_name,
    ROUND(AVG(CASE WHEN month_num = 1 THEN avg_fe END)::NUMERIC, 2) AS jan,
    ROUND(AVG(CASE WHEN month_num = 2 THEN avg_fe END)::NUMERIC, 2) AS feb,
    ROUND(AVG(CASE WHEN month_num = 3 THEN avg_fe END)::NUMERIC, 2) AS mar,
    ROUND(AVG(CASE WHEN month_num = 4 THEN avg_fe END)::NUMERIC, 2) AS apr,
    ROUND(AVG(CASE WHEN month_num = 5 THEN avg_fe END)::NUMERIC, 2) AS may,
    ROUND(AVG(CASE WHEN month_num = 6 THEN avg_fe END)::NUMERIC, 2) AS jun,
    ROUND(AVG(avg_fe)::NUMERIC, 2) AS period_avg
FROM
    monthly_fe
GROUP BY
    GROUPING SETS ((mine_name), ())
ORDER BY
    GROUPING(mine_name), mine_name;


-- ============================================================================
-- ЗАДАНИЕ 5. crosstab — динамический разворот 
-- ============================================================================

-- Вариант c использованием временной таблицы для top-5 причин
CREATE TEMP TABLE IF NOT EXISTS tmp_top_reasons AS
SELECT
    dr.reason_name,
    ROW_NUMBER() OVER (ORDER BY SUM(fd.duration_min) DESC) AS rn
FROM
    fact_equipment_downtime fd
JOIN
    dim_downtime_reason dr ON fd.reason_id = dr.reason_id
WHERE
    fd.date_id BETWEEN 20240101 AND 20240331
GROUP BY
    dr.reason_name;

-- Получаем список причин для подстановки в запрос (выполнить и скопировать результат)
SELECT STRING_AGG('"' || reason_name || '"', ', ' ORDER BY rn) AS columns_def
FROM tmp_top_reasons
WHERE rn <= 5;

-- Crosstab-запрос 

SELECT * FROM crosstab(
    $$
    SELECT
        e.equipment_name,
        dr.reason_name,
        ROUND(SUM(fd.duration_min) / 60.0, 1) AS total_hours
    FROM
        fact_equipment_downtime fd
    JOIN
        dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN
        dim_downtime_reason dr ON fd.reason_id = dr.reason_id
    JOIN
        tmp_top_reasons tr ON dr.reason_name = tr.reason_name
    WHERE
        fd.date_id BETWEEN 20240101 AND 20240331
        AND tr.rn <= 5
    GROUP BY
        e.equipment_name, dr.reason_name
    ORDER BY
        e.equipment_name, dr.reason_name
    $$,
    $$
    SELECT reason_name FROM tmp_top_reasons WHERE rn <= 5 ORDER BY rn
    $$
) AS ct(
    equipment_name VARCHAR,
    "Поломка двигателя" NUMERIC,
    "Замена фильтра" NUMERIC,
    "Плановое ТО" NUMERIC,
    "Отсутствие оператора" NUMERIC,
    "Сбой датчика" NUMERIC
);


-- ============================================================================
-- ЗАДАНИЕ 6. Комплексный отчёт — ROLLUP + PIVOT + итоги 
-- ============================================================================

-- Часть 1: Добыча по шахтам и месяцам с трендами
WITH production_pivot AS (
    SELECT
        m.mine_name,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 1 THEN fp.tons_mined END) AS jan,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 2 THEN fp.tons_mined END) AS feb,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 3 THEN fp.tons_mined END) AS mar,
        SUM(fp.tons_mined) AS q1_total,
        GROUPING(m.mine_name) AS is_total
    FROM
        fact_production fp
    JOIN
        dim_mine m ON fp.mine_id = m.mine_id
    JOIN
        dim_date d ON fp.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        ROLLUP(m.mine_name)
),
production_report AS (
    SELECT
        mine_name,
        'Добыча (тонн)' AS metric,
        ROUND(jan::NUMERIC, 1) AS jan,
        ROUND(feb::NUMERIC, 1) AS feb,
        ROUND(mar::NUMERIC, 1) AS mar,
        ROUND(q1_total::NUMERIC, 1) AS q1_total,
        ROUND(((feb - jan)::NUMERIC / NULLIF(jan, 0) * 100), 1) AS feb_vs_jan_pct,
        ROUND(((mar - feb)::NUMERIC / NULLIF(feb, 0) * 100), 1) AS mar_vs_feb_pct,
        CASE
            WHEN ABS((feb - jan)::NUMERIC / NULLIF(jan, 0)) < 0.05 THEN 'стабильно'
            WHEN (feb - jan)::NUMERIC / NULLIF(jan, 0) > 0 THEN 'рост'
            ELSE 'снижение'
        END AS trend_feb,
        CASE
            WHEN ABS((mar - feb)::NUMERIC / NULLIF(feb, 0)) < 0.05 THEN 'стабильно'
            WHEN (mar - feb)::NUMERIC / NULLIF(feb, 0) > 0 THEN 'рост'
            ELSE 'снижение'
        END AS trend_mar,
        is_total,
        CASE WHEN is_total = 1 THEN '== ИТОГО ==' ELSE mine_name END AS display_name
    FROM
        production_pivot
),

-- Часть 2: Простои по шахтам и месяцам
downtime_pivot AS (
    SELECT
        m.mine_name,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 1 THEN fd.duration_min / 60.0 END) AS jan,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 2 THEN fd.duration_min / 60.0 END) AS feb,
        SUM(CASE WHEN EXTRACT(MONTH FROM d.full_date) = 3 THEN fd.duration_min / 60.0 END) AS mar,
        SUM(fd.duration_min) / 60.0 AS q1_total,
        GROUPING(m.mine_name) AS is_total
    FROM
        fact_equipment_downtime fd
    JOIN
        dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN
        dim_mine m ON e.mine_id = m.mine_id
    JOIN
        dim_date d ON fd.date_id = d.date_id
    WHERE
        fd.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        ROLLUP(m.mine_name)
),
downtime_report AS (
    SELECT
        mine_name,
        'Простои (часы)' AS metric,
        ROUND(jan::NUMERIC, 1) AS jan,
        ROUND(feb::NUMERIC, 1) AS feb,
        ROUND(mar::NUMERIC, 1) AS mar,
        ROUND(q1_total::NUMERIC, 1) AS q1_total,
        ROUND(((feb - jan)::NUMERIC / NULLIF(jan, 0) * 100), 1) AS feb_vs_jan_pct,
        ROUND(((mar - feb)::NUMERIC / NULLIF(feb, 0) * 100), 1) AS mar_vs_feb_pct,
        CASE
            WHEN ABS((feb - jan)::NUMERIC / NULLIF(jan, 0)) < 0.05 THEN 'стабильно'
            WHEN (feb - jan)::NUMERIC / NULLIF(jan, 0) > 0 THEN 'рост'
            ELSE 'снижение'
        END AS trend_feb,
        CASE
            WHEN ABS((mar - feb)::NUMERIC / NULLIF(feb, 0)) < 0.05 THEN 'стабильно'
            WHEN (mar - feb)::NUMERIC / NULLIF(feb, 0) > 0 THEN 'рост'
            ELSE 'снижение'
        END AS trend_mar,
        is_total,
        CASE WHEN is_total = 1 THEN '== ИТОГО ==' ELSE mine_name END AS display_name
    FROM
        downtime_pivot
)

-- Объединение двух отчётов (is_total включён в SELECT для ORDER BY)
SELECT
    display_name AS mine_name,
    metric,
    jan,
    feb,
    mar,
    q1_total,
    feb_vs_jan_pct,
    mar_vs_feb_pct,
    trend_feb,
    trend_mar
FROM
    production_report

UNION ALL

SELECT
    display_name AS mine_name,
    metric,
    jan,
    feb,
    mar,
    q1_total,
    feb_vs_jan_pct,
    mar_vs_feb_pct,
    trend_feb,
    trend_mar
FROM
    downtime_report

ORDER BY
    metric DESC,
    mine_name;