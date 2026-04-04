-- ============================================================================
-- ЗАДАНИЕ 1. UNION ALL — объединённый журнал событий (простое)
-- ============================================================================

SELECT
    'Добыча' AS event_type,
    e.equipment_name,
    fp.tons_mined AS value,
    'тонн' AS unit
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
WHERE
    fp.date_id = 20240315

UNION ALL

SELECT
    'Простой' AS event_type,
    e.equipment_name,
    fd.duration_min AS value,
    'мин.' AS unit
FROM
    fact_equipment_downtime AS fd
JOIN
    dim_equipment AS e ON fd.equipment_id = e.equipment_id
WHERE
    fd.date_id = 20240315

ORDER BY
    equipment_name,
    event_type;

-- Ответ: UNION ALL сохраняет все строки (включая дубликаты)

-- ============================================================================
-- ЗАДАНИЕ 2. UNION — уникальные шахты с активностью (простое)
-- ============================================================================

SELECT
    m.mine_name
FROM
    fact_production AS fp
JOIN
    dim_mine AS m ON fp.mine_id = m.mine_id
WHERE
    fp.date_id BETWEEN 20240101 AND 20240331

UNION

SELECT
    m.mine_name
FROM
    fact_equipment_downtime AS fd
JOIN
    dim_equipment AS e ON fd.equipment_id = e.equipment_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
WHERE
    fd.date_id BETWEEN 20240101 AND 20240331;

-- Подсчёт уникальных шахт
SELECT
    COUNT(*) AS unique_mines_count
FROM
    (
        SELECT m.mine_name
        FROM fact_production fp
        JOIN dim_mine m ON fp.mine_id = m.mine_id
        WHERE fp.date_id BETWEEN 20240101 AND 20240331
        UNION
        SELECT m.mine_name
        FROM fact_equipment_downtime fd
        JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
        JOIN dim_mine m ON e.mine_id = m.mine_id
        WHERE fd.date_id BETWEEN 20240101 AND 20240331
    ) AS all_mines;

-- Ответ: UNION удаляет дубликаты, UNION ALL — нет. Если шахта есть в обоих
-- источниках, UNION вернёт 1 строку, UNION ALL — 2 строки.

-- ============================================================================
-- ЗАДАНИЕ 3. EXCEPT — оборудование без данных о качестве 
-- ============================================================================

-- Вариант 1: EXCEPT (через fact_production как связку)
SELECT
    e.equipment_name,
    et.type_name
FROM
    (
        -- Оборудование с добычей за Q1 2024
        SELECT DISTINCT fp.equipment_id
        FROM fact_production AS fp
        WHERE fp.date_id BETWEEN 20240101 AND 20240331
        
        EXCEPT
        
        -- Оборудование, для которого есть данные о качестве (через mine_id + date_id)
        SELECT DISTINCT fp2.equipment_id
        FROM fact_production AS fp2
        JOIN fact_ore_quality AS oq ON fp2.mine_id = oq.mine_id
            AND fp2.date_id = oq.date_id
        WHERE oq.date_id BETWEEN 20240101 AND 20240331
    ) AS eq_no_quality
JOIN
    dim_equipment AS e ON eq_no_quality.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
ORDER BY
    e.equipment_name;

-- Вариант 2: NOT EXISTS (альтернатива)
SELECT
    e.equipment_name,
    et.type_name
FROM
    (
        SELECT DISTINCT fp.equipment_id
        FROM fact_production AS fp
        WHERE fp.date_id BETWEEN 20240101 AND 20240331
    ) AS prod_eq
JOIN
    dim_equipment AS e ON prod_eq.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
WHERE
    NOT EXISTS (
        SELECT 1
        FROM fact_ore_quality AS oq
        JOIN fact_production AS fp2 ON oq.mine_id = fp2.mine_id
            AND oq.date_id = fp2.date_id
        WHERE fp2.equipment_id = prod_eq.equipment_id
          AND oq.date_id BETWEEN 20240101 AND 20240331
    )
ORDER BY
    e.equipment_name;

-- Ответ: EXCEPT и NOT EXISTS дают одинаковый результат.
-- fact_ore_quality связывается с оборудованием через mine_id + date_id

-- ============================================================================
-- ЗАДАНИЕ 4. INTERSECT — операторы на нескольких типах оборудования (ИСПРАВЛЕНО)
-- ============================================================================

-- Поиск операторов-универсалов (LHD и TRUCK)
SELECT
    o.last_name || ' ' || o.first_name || ' ' || COALESCE(o.middle_name, '') AS full_name,
    o.position,
    o.qualification
FROM
    (
        SELECT fp.operator_id
        FROM fact_production AS fp
        JOIN dim_equipment AS e ON fp.equipment_id = e.equipment_id
        JOIN dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
        WHERE et.type_code = 'LHD'
        INTERSECT
        SELECT fp.operator_id
        FROM fact_production AS fp
        JOIN dim_equipment AS e ON fp.equipment_id = e.equipment_id
        JOIN dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
        WHERE et.type_code = 'TRUCK'
    ) AS universal_ops
JOIN
    dim_operator AS o ON universal_ops.operator_id = o.operator_id
ORDER BY
    full_name;

-- Подсчёт процента универсалов
SELECT
    COUNT(*) AS universal_count,
    (SELECT COUNT(DISTINCT operator_id) FROM fact_production) AS total_operators,
    ROUND(
        COUNT(*)::NUMERIC / 
        (SELECT COUNT(DISTINCT operator_id) FROM fact_production) * 100, 2
    ) AS universal_pct
FROM
    (
        SELECT fp.operator_id
        FROM fact_production fp
        JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
        JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
        WHERE et.type_code = 'LHD'
        INTERSECT
        SELECT fp.operator_id
        FROM fact_production fp
        JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
        JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
        WHERE et.type_code = 'TRUCK'
    ) AS universal_ops;

-- ============================================================================
-- ЗАДАНИЕ 5. Диаграмма Венна: комплексный анализ (ИСПРАВЛЕНО)
-- ============================================================================

WITH lhd_ops AS (
    SELECT DISTINCT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
    WHERE et.type_code = 'LHD'
),
truck_ops AS (
    SELECT DISTINCT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
    WHERE et.type_code = 'TRUCK'
),
total_ops AS (
    SELECT COUNT(DISTINCT operator_id) AS cnt FROM fact_production
)
SELECT
    'Оба типа' AS category,
    COUNT(*) AS operator_count,
    ROUND(COUNT(*)::NUMERIC / (SELECT cnt FROM total_ops) * 100, 2) AS pct
FROM (
    SELECT operator_id FROM lhd_ops
    INTERSECT
    SELECT operator_id FROM truck_ops
) 
UNION ALL
SELECT
    'Только ПДМ',
    COUNT(*),
    ROUND(COUNT(*)::NUMERIC / (SELECT cnt FROM total_ops) * 100, 2)
FROM (
    SELECT operator_id FROM lhd_ops
    EXCEPT
    SELECT operator_id FROM truck_ops
) AS only_lhd
UNION ALL
SELECT
    'Только самосвал',
    COUNT(*),
    ROUND(COUNT(*)::NUMERIC / (SELECT cnt FROM total_ops) * 100, 2)
FROM (
    SELECT operator_id FROM truck_ops
    EXCEPT
    SELECT operator_id FROM lhd_ops
) AS only_truck;

-- Проверка сходимости сумм
WITH lhd_ops AS (
    SELECT DISTINCT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
    WHERE et.type_code = 'LHD'
),
truck_ops AS (
    SELECT DISTINCT fp.operator_id
    FROM fact_production fp
    JOIN dim_equipment e ON fp.equipment_id = e.equipment_id
    JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
    WHERE et.type_code = 'TRUCK'
)
SELECT
    SUM(operator_count) AS total_from_categories,
    (SELECT COUNT(DISTINCT operator_id) FROM fact_production) AS actual_total,
    SUM(operator_count) = (SELECT COUNT(DISTINCT operator_id) FROM fact_production) AS matches
FROM (
    SELECT COUNT(*) AS operator_count FROM (
        SELECT operator_id FROM lhd_ops INTERSECT SELECT operator_id FROM truck_ops
    )
    UNION ALL
    SELECT COUNT(*) FROM (
        SELECT operator_id FROM lhd_ops EXCEPT SELECT operator_id FROM truck_ops
    ) AS only_lhd
    UNION ALL
    SELECT COUNT(*) FROM (
        SELECT operator_id FROM truck_ops EXCEPT SELECT operator_id FROM lhd_ops
    ) AS only_truck
) AS t;

-- Ответ: Суммы должны сходиться (все операторы распределены по 3 категориям)

-- ============================================================================
-- ЗАДАНИЕ 6. LATERAL — топ-N записей для каждой группы (среднее)
-- ============================================================================

SELECT
    m.mine_name,
    top5.full_date,
    top5.equipment_name,
    top5.reason_name,
    top5.duration_min,
    top5.duration_hours
FROM
    dim_mine m
CROSS JOIN LATERAL (
    SELECT
        d.full_date,
        e.equipment_name,
        r.reason_name,
        fd.duration_min,
        ROUND(fd.duration_min / 60.0, 1) AS duration_hours
    FROM
        fact_equipment_downtime fd
    JOIN
        dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN
        dim_downtime_reason r ON fd.reason_id = r.reason_id
    JOIN
        dim_date d ON fd.date_id = d.date_id
    WHERE
        e.mine_id = m.mine_id
        AND fd.is_planned = FALSE
        AND fd.date_id BETWEEN 20240101 AND 20240331
    ORDER BY
        fd.duration_min DESC
    LIMIT 5
) top5
WHERE
    m.status = 'active'
ORDER BY
    m.mine_name,
    top5.duration_min DESC;

-- Ответ: LATERAL позволяет ссылаться на столбцы внешнего запроса внутри подзапроса

-- ============================================================================
-- ЗАДАНИЕ 7. LEFT JOIN LATERAL — последнее показание для каждого датчика (сложное)
-- ============================================================================

SELECT
    s.sensor_code,
    st.type_name AS sensor_type,
    e.equipment_name,
    last.full_date,
    last.time_id,
    last.sensor_value,
    last.is_alarm
FROM
    dim_sensor s
JOIN
    dim_sensor_type st ON s.sensor_type_id = st.sensor_type_id
JOIN
    dim_equipment e ON s.equipment_id = e.equipment_id
LEFT JOIN LATERAL (
    SELECT
        d.full_date,
        t.time_id,
        t.sensor_value,
        t.is_alarm
    FROM
        fact_equipment_telemetry t
    JOIN
        dim_date d ON t.date_id = d.date_id
    WHERE
        t.sensor_id = s.sensor_id
    ORDER BY
        t.date_id DESC,
        t.time_id DESC
    LIMIT 1
) last ON TRUE
WHERE
    s.status = 'active'
ORDER BY
    last.full_date ASC NULLS FIRST;

-- Вопрос: Почему LEFT JOIN LATERAL предпочтительнее CROSS JOIN LATERAL?
-- Ответ: LEFT JOIN сохраняет датчики без показаний (возвращает NULL),
--        CROSS JOIN отбросит датчики без данных в telemetry.

-- ============================================================================
-- ЗАДАНИЕ 8. UNION ALL + агрегация — сводный KPI-отчёт (сложное)
-- ============================================================================

-- Часть 1: KPI в «длинном» формате
WITH kpi_long AS (
    SELECT
        m.mine_name,
        'Добыча (тонн)' AS kpi_name,
        SUM(fp.tons_mined)::NUMERIC AS kpi_value
    FROM
        fact_production fp
    JOIN
        dim_mine m ON fp.mine_id = m.mine_id
    JOIN
        dim_date d ON fp.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY
        m.mine_name

    UNION ALL

    SELECT
        m.mine_name,
        'Простои (часы)',
        ROUND(SUM(fd.duration_min) / 60.0, 1)
    FROM
        fact_equipment_downtime fd
    JOIN
        dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN
        dim_mine m ON e.mine_id = m.mine_id
    JOIN
        dim_date d ON fd.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY
        m.mine_name

    UNION ALL

    SELECT
        m.mine_name,
        'Среднее Fe (%)',
        ROUND(AVG(oq.fe_content), 2)
    FROM
        fact_ore_quality oq
    JOIN
        dim_mine m ON oq.mine_id = m.mine_id
    JOIN
        dim_date d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY
        m.mine_name

    UNION ALL

    SELECT
        m.mine_name,
        'Тревожные показания',
        COUNT(*)::NUMERIC
    FROM
        fact_equipment_telemetry t
    JOIN
        dim_sensor s ON t.sensor_id = s.sensor_id
    JOIN
        dim_equipment e ON s.equipment_id = e.equipment_id
    JOIN
        dim_mine m ON e.mine_id = m.mine_id
    JOIN
        dim_date d ON t.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240301 AND 20240331
        AND t.is_alarm = TRUE
    GROUP BY
        m.mine_name
)
SELECT * FROM kpi_long
ORDER BY mine_name, kpi_name;

-- Часть 2: KPI в «широком» формате (crosstab)
WITH kpi_long AS (
    SELECT
        m.mine_name,
        'Добыча (тонн)' AS kpi_name,
        SUM(fp.tons_mined)::NUMERIC AS kpi_value
    FROM fact_production fp
    JOIN dim_mine m ON fp.mine_id = m.mine_id
    JOIN dim_date d ON fp.date_id = d.date_id
    WHERE d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY m.mine_name
    UNION ALL
    SELECT
        m.mine_name,
        'Простои (часы)',
        ROUND(SUM(fd.duration_min) / 60.0, 1)
    FROM fact_equipment_downtime fd
    JOIN dim_equipment e ON fd.equipment_id = e.equipment_id
    JOIN dim_mine m ON e.mine_id = m.mine_id
    JOIN dim_date d ON fd.date_id = d.date_id
    WHERE d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY m.mine_name
    UNION ALL
    SELECT
        m.mine_name,
        'Среднее Fe (%)',
        ROUND(AVG(oq.fe_content), 2)
    FROM fact_ore_quality oq
    JOIN dim_mine m ON oq.mine_id = m.mine_id
    JOIN dim_date d ON oq.date_id = d.date_id
    WHERE d.date_id BETWEEN 20240301 AND 20240331
    GROUP BY m.mine_name
    UNION ALL
    SELECT
        m.mine_name,
        'Тревожные показания',
        COUNT(*)::NUMERIC
    FROM fact_equipment_telemetry t
    JOIN dim_sensor s ON t.sensor_id = s.sensor_id
    JOIN dim_equipment e ON s.equipment_id = e.equipment_id
    JOIN dim_mine m ON e.mine_id = m.mine_id
    JOIN dim_date d ON t.date_id = d.date_id
    WHERE d.date_id BETWEEN 20240301 AND 20240331 AND t.is_alarm = TRUE
    GROUP BY m.mine_name
)
SELECT
    mine_name,
    MAX(CASE WHEN kpi_name = 'Добыча (тонн)' THEN kpi_value END) AS production,
    MAX(CASE WHEN kpi_name = 'Простои (часы)' THEN kpi_value END) AS downtime,
    MAX(CASE WHEN kpi_name = 'Среднее Fe (%)' THEN kpi_value END) AS avg_fe,
    MAX(CASE WHEN kpi_name = 'Тревожные показания' THEN kpi_value END) AS alarms
FROM
    kpi_long
GROUP BY
    mine_name
ORDER BY
    mine_name;

-- Ответ: UNION ALL + CASE WHEN позволяет развернуть «длинный» формат в «широкий»

