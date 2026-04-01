-- Задание 1. Округление результатов анализов (математические функции)
SELECT
    sample_number,
    ROUND(fe_content, 1) AS fe_rounded,
    CEIL(sio2_content) AS sio2_ceil,
    FLOOR(al2o3_content) AS al2o3_floor
FROM
    fact_ore_quality
WHERE
    date_id = 20240315
ORDER BY
    fe_rounded DESC;



-- Задание 2. Отклонение от целевого содержания Fe (ABS, SIGN, POWER)
SELECT
    sample_number,
    fe_content,
    ROUND(fe_content - 60, 2) AS deviation,
    ROUND(ABS(fe_content - 60), 2) AS abs_deviation,
    CASE
        WHEN fe_content > 60 THEN 'Выше нормы'
        WHEN fe_content = 60 THEN 'В норме'
        ELSE 'Ниже нормы'
    END AS direction,
    ROUND(POWER(fe_content - 60, 2), 2) AS squared_dev
FROM
    fact_ore_quality
WHERE
    date_id BETWEEN 20240301 AND 20240331
ORDER BY
    abs_deviation DESC
LIMIT 10;



-- Задание 3. Статистика добычи по сменам (агрегатные функции)
SELECT
    fp.shift_id,
    CASE fp.shift_id
        WHEN 1 THEN 'Утренняя'
        WHEN 2 THEN 'Дневная'
        WHEN 3 THEN 'Ночная'
        ELSE 'Неизвестная'
    END AS shift_name,
    COUNT(*) AS record_count,
    SUM(fp.tons_mined) AS total_tons,
    ROUND(AVG(fp.tons_mined), 2) AS avg_tons,
    COUNT(DISTINCT fp.operator_id) AS unique_operators
FROM
    fact_production AS fp
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    fp.shift_id
ORDER BY
    fp.shift_id;



-- Задание 4. Список причин простоев по оборудованию (STRING_AGG / CONCATENATEX)
SELECT
    e.equipment_name,
    STRING_AGG(DISTINCT dr.reason_name, '; ' ORDER BY dr.reason_name) AS reasons,
    SUM(fd.duration_min) AS total_min,
    COUNT(*) AS incidents
FROM
    fact_equipment_downtime AS fd
JOIN
    dim_equipment AS e ON fd.equipment_id = e.equipment_id
JOIN
    dim_downtime_reason AS dr ON fd.reason_id = dr.reason_id
WHERE
    fd.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_min DESC;



-- Задание 5. Преобразование date_id и форматирование отчёта
SELECT
    fp.date_id,
    TO_CHAR(TO_DATE(fp.date_id::VARCHAR, 'YYYYMMDD'), 'DD.MM.YYYY') AS formatted_date,
    SUM(fp.tons_mined) AS total_tons,
    TO_CHAR(SUM(fp.tons_mined), 'FM999G999D00') AS formatted_tons
FROM
    fact_production AS fp
WHERE
    fp.date_id BETWEEN 20240301 AND 20240307
GROUP BY
    fp.date_id
ORDER BY
    fp.date_id;



-- Задание 6. Классификация проб и расчёт процента качества (CASE, COALESCE, NULLIF)
SELECT
    d.full_date,
    SUM(CASE WHEN oq.fe_content >= 65 THEN 1 ELSE 0 END) AS rich_ore,
    SUM(CASE WHEN oq.fe_content >= 55 AND oq.fe_content < 65 THEN 1 ELSE 0 END) AS medium_ore,
    SUM(CASE WHEN oq.fe_content < 55 THEN 1 ELSE 0 END) AS poor_ore,
    COUNT(*) AS total,
    ROUND(
        100.0 * SUM(CASE WHEN oq.fe_content >= 60 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        1
    ) AS good_pct
FROM
    fact_ore_quality AS oq
JOIN
    dim_date AS d ON oq.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    d.full_date
ORDER BY
    d.full_date;



-- Задание 7. Безопасные KPI с обработкой NULL и нуля (COALESCE, NULLIF, GREATEST)
SELECT
    o.last_name || ' ' || o.first_name AS full_name,
    o.position,
    ROUND(SUM(fp.tons_mined), 2) AS total_tons,
    ROUND(COALESCE(SUM(fp.fuel_consumed_l), 0), 2) AS total_fuel,
    ROUND(SUM(fp.tons_mined) / NULLIF(SUM(fp.trips_count), 0), 2) AS tons_per_trip,
    ROUND(COALESCE(SUM(fp.fuel_consumed_l), 0) / NULLIF(SUM(fp.tons_mined), 0), 3) AS fuel_per_ton,
    ROUND(GREATEST(
        SUM(CASE WHEN s.shift_id = 1 THEN fp.tons_mined ELSE 0 END) / 
            NULLIF(COUNT(CASE WHEN s.shift_id = 1 THEN 1 END), 0),
        SUM(CASE WHEN s.shift_id = 2 THEN fp.tons_mined ELSE 0 END) / 
            NULLIF(COUNT(CASE WHEN s.shift_id = 2 THEN 1 END), 0)
    ), 2) AS max_efficiency
FROM
    fact_production AS fp
JOIN
    dim_operator AS o ON fp.operator_id = o.operator_id
JOIN
    dim_shift AS s ON fp.shift_id = s.shift_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    o.last_name,
    o.first_name,
    o.position
ORDER BY
    tons_per_trip DESC;



-- Задание 8. Анализ пропусков данных (IS NULL, COUNT, CASE)
SELECT
    COUNT(*) AS total_rows,
    COUNT(sio2_content) AS sio2_filled,
    COUNT(*) - COUNT(sio2_content) AS sio2_null,
    ROUND(100.0 * COUNT(sio2_content) / COUNT(*), 1) AS sio2_pct,
    COUNT(al2o3_content) AS al2o3_filled,
    COUNT(*) - COUNT(al2o3_content) AS al2o3_null,
    ROUND(100.0 * COUNT(al2o3_content) / COUNT(*), 1) AS al2o3_pct,
    COUNT(moisture) AS moisture_filled,
    COUNT(*) - COUNT(moisture) AS moisture_null,
    ROUND(100.0 * COUNT(moisture) / COUNT(*), 1) AS moisture_pct,
    COUNT(density) AS density_filled,
    COUNT(*) - COUNT(density) AS density_null,
    ROUND(100.0 * COUNT(density) / COUNT(*), 1) AS density_pct,
    COUNT(sample_weight_kg) AS sample_weight_filled,
    COUNT(*) - COUNT(sample_weight_kg) AS sample_weight_null,
    ROUND(100.0 * COUNT(sample_weight_kg) / COUNT(*), 1) AS sample_weight_pct
FROM
    fact_ore_quality
WHERE
    date_id BETWEEN 20240301 AND 20240331;



-- Задание 9. Комплексный отчёт по эффективности оборудования
SELECT
    e.equipment_name,
    et.type_name,
    COUNT(*) AS shift_count,
    ROUND(SUM(fp.tons_mined), 1) AS total_tons,
    ROUND(SUM(fp.operating_hours), 1) AS total_hours,
    ROUND(SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0), 2) AS productivity,
    ROUND(SUM(fp.operating_hours) / NULLIF(COUNT(*) * 8, 0) * 100, 1) AS utilization,
    ROUND(COALESCE(SUM(fp.fuel_consumed_l), 0) / NULLIF(SUM(fp.tons_mined), 0), 3) AS fuel_per_ton,
    CASE
        WHEN SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0) > 20 THEN 'Высокая'
        WHEN SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0) > 12 THEN 'Средняя'
        ELSE 'Низкая'
    END AS efficiency_category,
    CASE
        WHEN COUNT(fp.fuel_consumed_l) = COUNT(*) THEN 'Полные'
        ELSE 'Неполные'
    END AS data_status
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name,
    et.type_name
ORDER BY
    productivity DESC;



-- Задание 10. Категоризация простоев (все функции модуля)
WITH categorized AS (
    SELECT
        e.equipment_name,
        r.reason_name,
        COALESCE(f.duration_min, 0) AS duration_safe,
        ROUND(COALESCE(f.duration_min, 0) / 60.0, 1) AS duration_hours,
        CASE
            WHEN COALESCE(f.duration_min, 0) > 480 THEN 'Критический'
            WHEN COALESCE(f.duration_min, 0) >= 120 THEN 'Длительный'
            WHEN COALESCE(f.duration_min, 0) >= 30 THEN 'Средний'
            ELSE 'Короткий'
        END AS category,
        CASE
            WHEN f.is_planned = TRUE THEN 'Плановый'
            ELSE 'Внеплановый'
        END AS planned_status,
        CASE
            WHEN f.end_time IS NULL THEN 'В процессе'
            ELSE 'Завершён'
        END AS completion_status
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_equipment AS e ON f.equipment_id = e.equipment_id
    JOIN
        dim_downtime_reason AS r ON f.reason_id = r.reason_id
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240301 AND 20240331
)
SELECT
    category,
    COUNT(*) AS downtime_count,
    ROUND(SUM(duration_safe) / 60.0, 1) AS total_hours,
    ROUND(100.0 * SUM(duration_safe) / NULLIF(SUM(SUM(duration_safe)) OVER (), 0), 1) AS pct_of_total
FROM
    categorized
GROUP BY
    category
ORDER BY
    total_hours DESC;