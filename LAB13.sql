-- Задание 1. Доля оборудования в общей добыче (простое)
-- Использование оконной функции SUM() OVER() для расчёта доли

SELECT
    e.equipment_name,
    fp.tons_mined,
    SUM(fp.tons_mined) OVER (
        PARTITION BY fp.date_id, fp.shift_id
    ) AS total_tons,
    ROUND(
        fp.tons_mined / NULLIF(
            SUM(fp.tons_mined) OVER (
                PARTITION BY fp.date_id, fp.shift_id
            ), 0
        ) * 100,
        1
    ) AS pct_of_total
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
WHERE
    fp.date_id = 20240115
    AND fp.shift_id = 1
ORDER BY
    fp.tons_mined DESC;


-- ============================================================================

-- Задание 2. Нарастающий итог по шахтам (простое)
-- Использование оконной функции SUM() OVER (PARTITION BY ... ORDER BY ...)

WITH daily_production AS (
    SELECT
        m.mine_name,
        d.full_date,
        SUM(fp.tons_mined) AS daily_tons
    FROM
        fact_production AS fp
    JOIN
        dim_mine AS m ON fp.mine_id = m.mine_id
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240131
    GROUP BY
        m.mine_name,
        d.full_date
)
SELECT
    mine_name,
    full_date,
    daily_tons,
    SUM(daily_tons) OVER (
        PARTITION BY mine_name
        ORDER BY full_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM
    daily_production
ORDER BY
    mine_name,
    full_date;

-- ============================================================================

-- Задание 3. Скользящее среднее расхода ГСМ (простое)
-- Использование оконной функции AVG() OVER (ROWS BETWEEN ... PRECEDING AND CURRENT ROW)

WITH daily_fuel AS (
    SELECT
        d.full_date,
        SUM(fp.fuel_consumed_l) AS daily_fuel
    FROM
        fact_production AS fp
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        fp.mine_id = 1
        AND d.date_id BETWEEN 20240101 AND 20240331
    GROUP BY
        d.full_date
)
SELECT
    full_date,
    ROUND(daily_fuel, 2) AS daily_fuel,
    ROUND(
        AVG(daily_fuel) OVER (
            ORDER BY full_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2
    ) AS ma_7,
    ROUND(
        AVG(daily_fuel) OVER (
            ORDER BY full_date
            ROWS BETWEEN 13 PRECEDING AND CURRENT ROW
        ), 2
    ) AS ma_14
FROM
    daily_fuel
ORDER BY
    full_date;

-- ============================================================================
-- Ответ на вопрос о первых 6 значениях скользящего среднего
-- ============================================================================

-- Вопрос: Почему первые 6 значений скользящего среднего за 7 дней рассчитаны
--         по меньшему количеству строк? Как это влияет на точность?

-- Ответ:

-- 1. Причина: Оконная функция ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
--    включает текущую строку и 6 предыдущих. Для первых строк таблицы
--    предыдущих строк просто не существует.

-- 2. Влияние на точность:
--    - Первые 6 значений MA_7 менее стабильны (меньше данных для усреднения)
--    - Могут быть более чувствительны к выбросам
--    - Не рекомендуется использовать для анализа трендов

-- 3. Решение:
--    - Пометить первые 6 строк флагом "недостаточно данных"
--    - Использовать ROW_NUMBER() для фильтрации

--
-- 4. Альтернатива: Использовать RANGE вместо ROWS для учёта всех дат
--    в диапазоне, даже если есть пропуски в данных.
-- ============================================================================


-- Задание 4. Рейтинг операторов по типам оборудования (среднее)
-- Использование оконных функций RANK(), DENSE_RANK(), NTILE()

SELECT
    full_name,
    type_name,
    total_tons,
    rnk,
    dense_rnk,
    quartile
FROM
    (
        SELECT
            o.last_name || ' ' || LEFT(o.first_name, 1) || '.' AS full_name,
            et.type_name,
            SUM(fp.tons_mined) AS total_tons,
            RANK() OVER (
                PARTITION BY et.type_name
                ORDER BY SUM(fp.tons_mined) DESC
            ) AS rnk,
            DENSE_RANK() OVER (
                PARTITION BY et.type_name
                ORDER BY SUM(fp.tons_mined) DESC
            ) AS dense_rnk,
            NTILE(4) OVER (
                PARTITION BY et.type_name
                ORDER BY SUM(fp.tons_mined) DESC
            ) AS quartile
        FROM
            fact_production AS fp
        JOIN
            dim_operator AS o ON fp.operator_id = o.operator_id
        JOIN
            dim_equipment AS e ON fp.equipment_id = e.equipment_id
        JOIN
            dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
        JOIN
            dim_date AS d ON fp.date_id = d.date_id
        WHERE
            d.date_id BETWEEN 20240101 AND 20240630
        GROUP BY
            o.last_name,
            o.first_name,
            et.type_name
    ) AS ranked_operators
WHERE
    rnk <= 5
ORDER BY
    type_name,
    rnk;

-- ============================================================================

-- Задание 5. Сравнение дневной и ночной смены (среднее)
-- Использование LAG(), SUM() OVER(), AVG() OVER() с именованными окнами

WITH shift_production AS (
    SELECT
        d.full_date,
        s.shift_name,
        s.shift_id,
        SUM(fp.tons_mined) AS shift_tons
    FROM
        fact_production AS fp
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    JOIN
        dim_shift AS s ON fp.shift_id = s.shift_id
    WHERE
        fp.mine_id = 1
        AND d.date_id BETWEEN 20240101 AND 20240131
    GROUP BY
        d.full_date,
        s.shift_name,
        s.shift_id
)
SELECT
    full_date,
    shift_name,
    shift_tons,
    LAG(shift_tons, 1) OVER w AS prev_shift_tons,
    ROUND(
        shift_tons / NULLIF(
            SUM(shift_tons) OVER (
                PARTITION BY full_date
            ), 0
        ) * 100, 1
    ) AS pct_of_day,
    ROUND(
        AVG(shift_tons) OVER w, 2
    ) AS ma_7_shift
FROM
    shift_production
WINDOW
    w AS (
        PARTITION BY shift_id
        ORDER BY full_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )
ORDER BY
    full_date,
    shift_id;

-- ============================================================================

-- Задание 6. Интервалы между внеплановыми простоями (среднее)
-- Использование LAG(), LEAD() для анализа интервалов между поломками

WITH downtime_intervals AS (
    SELECT
        e.equipment_name,
        d.full_date AS downtime_date,
        r.reason_name,
        f.duration_min,
        LAG(d.full_date, 1) OVER (
            PARTITION BY e.equipment_id
            ORDER BY d.full_date
        ) AS prev_downtime_date,
        LEAD(d.full_date, 1) OVER (
            PARTITION BY e.equipment_id
            ORDER BY d.full_date
        ) AS next_downtime_date
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    JOIN
        dim_equipment AS e ON f.equipment_id = e.equipment_id
    JOIN
        dim_downtime_reason AS r ON f.reason_id = r.reason_id
    WHERE
        f.is_planned = FALSE
)
SELECT
    equipment_name,
    downtime_date,
    reason_name,
    duration_min,
    prev_downtime_date,
    CASE
        WHEN prev_downtime_date IS NOT NULL
        THEN downtime_date - prev_downtime_date
        ELSE NULL
    END AS days_between,
    next_downtime_date
FROM
    downtime_intervals
ORDER BY
    equipment_name,
    downtime_date;

-- ============================================================================
-- Дополнительно: Среднее количество дней между поломками для каждого оборудования
-- ============================================================================

WITH downtime_intervals AS (
    SELECT
        e.equipment_id,
        e.equipment_name,
        d.full_date AS downtime_date,
        LAG(d.full_date, 1) OVER (
            PARTITION BY e.equipment_id
            ORDER BY d.full_date
        ) AS prev_downtime_date
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    JOIN
        dim_equipment AS e ON f.equipment_id = e.equipment_id
    WHERE
        f.is_planned = FALSE
)
SELECT
    equipment_name,
    COUNT(*) AS downtime_count,
    ROUND(AVG(downtime_date - prev_downtime_date), 1) AS avg_days_between,
    MIN(downtime_date - prev_downtime_date) AS min_days_between,
    MAX(downtime_date - prev_downtime_date) AS max_days_between
FROM
    downtime_intervals
WHERE
    prev_downtime_date IS NOT NULL
GROUP BY
    equipment_id,
    equipment_name
ORDER BY
    avg_days_between ASC;




-- Задание 7. Обнаружение выбросов по содержанию Fe методом IQR (среднее)

WITH mine_quartiles AS (
    SELECT
        m.mine_id,
        m.mine_name,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY oq.fe_content) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY oq.fe_content) AS q3
    FROM
        fact_ore_quality AS oq
    JOIN
        dim_mine AS m ON oq.mine_id = m.mine_id
    JOIN
        dim_date AS d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
    GROUP BY
        m.mine_id,
        m.mine_name
),
outliers AS (
    SELECT
        oq.sample_number,
        mq.mine_name,
        d.full_date,
        oq.fe_content,
        mq.q1,
        mq.q3,
        mq.q3 - mq.q1 AS iqr,
        mq.q1 - 1.5 * (mq.q3 - mq.q1) AS lower_bound,
        mq.q3 + 1.5 * (mq.q3 - mq.q1) AS upper_bound,
        CASE
            WHEN oq.fe_content < mq.q1 - 1.5 * (mq.q3 - mq.q1) THEN 'Выброс (низ)'
            WHEN oq.fe_content > mq.q3 + 1.5 * (mq.q3 - mq.q1) THEN 'Выброс (верх)'
            ELSE NULL
        END AS outlier_status
    FROM
        fact_ore_quality AS oq
    JOIN
        mine_quartiles AS mq ON oq.mine_id = mq.mine_id
    JOIN
        dim_date AS d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
)
SELECT
    mine_name,
    full_date,
    sample_number,
    ROUND(fe_content::NUMERIC, 2) AS fe_content,  
    ROUND(q1::NUMERIC, 2) AS q1,
    ROUND(q3::NUMERIC, 2) AS q3,
    ROUND(iqr::NUMERIC, 2) AS iqr,
    outlier_status
FROM
    outliers
WHERE
    outlier_status IS NOT NULL
ORDER BY
    mine_name,
    fe_content;

-- Подсчёт общего количества выбросов по каждой шахте
WITH mine_quartiles AS (
    SELECT
        m.mine_id,
        m.mine_name,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY oq.fe_content) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY oq.fe_content) AS q3
    FROM
        fact_ore_quality AS oq
    JOIN
        dim_mine AS m ON oq.mine_id = m.mine_id
    JOIN
        dim_date AS d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
    GROUP BY
        m.mine_id,
        m.mine_name
),
outliers AS (
    SELECT
        mq.mine_name,
        CASE
            WHEN oq.fe_content < mq.q1 - 1.5 * (mq.q3 - mq.q1) THEN 'Выброс (низ)'
            WHEN oq.fe_content > mq.q3 + 1.5 * (mq.q3 - mq.q1) THEN 'Выброс (верх)'
            ELSE NULL
        END AS outlier_status
    FROM
        fact_ore_quality AS oq
    JOIN
        mine_quartiles AS mq ON oq.mine_id = mq.mine_id
    JOIN
        dim_date AS d ON oq.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
)
SELECT
    mine_name,
    COUNT(*) AS outlier_count,
    COUNT(*) FILTER (WHERE outlier_status = 'Выброс (низ)') AS low_outliers,
    COUNT(*) FILTER (WHERE outlier_status = 'Выброс (верх)') AS high_outliers
FROM
    outliers
WHERE
    outlier_status IS NOT NULL
GROUP BY
    mine_name
ORDER BY
    outlier_count DESC;

-- ============================================================================

-- Задание 8. ТОП-3 рекордных дня для каждой единицы оборудования (среднее)
-- Использование ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)

WITH daily_production AS (
    SELECT
        e.equipment_id,
        e.equipment_name,
        et.type_name,
        d.full_date,
        SUM(fp.tons_mined) AS daily_tons
    FROM
        fact_production AS fp
    JOIN
        dim_equipment AS e ON fp.equipment_id = e.equipment_id
    JOIN
        dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20241231
    GROUP BY
        e.equipment_id,
        e.equipment_name,
        et.type_name,
        d.full_date
),
ranked_days AS (
    SELECT
        equipment_id,
        equipment_name,
        type_name,
        full_date,
        daily_tons,
        ROW_NUMBER() OVER (
            PARTITION BY equipment_id
            ORDER BY daily_tons DESC
        ) AS record_num,
        FIRST_VALUE(daily_tons) OVER (
            PARTITION BY equipment_id
            ORDER BY daily_tons DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS top1_tons
    FROM
        daily_production
)
SELECT
    equipment_name,
    type_name,
    full_date,
    ROUND(daily_tons, 2) AS daily_tons,
    record_num,
    ROUND(top1_tons - daily_tons, 2) AS diff_from_top1
FROM
    ranked_days
WHERE
    record_num <= 3
ORDER BY
    equipment_name,
    record_num;

-- ============================================================================
-- Задание 9. Парето-анализ причин простоев (сложное)
-- Использование SUM() OVER (ORDER BY ... DESC) для нарастающего итога
-- ============================================================================

WITH reason_totals AS (
    SELECT
        r.reason_name,
        r.category,
        SUM(f.duration_min) / 60.0 AS total_hours,
        SUM(SUM(f.duration_min)) OVER () AS grand_total_hours
    FROM
        fact_equipment_downtime AS f
    JOIN
        dim_downtime_reason AS r ON f.reason_id = r.reason_id
    JOIN
        dim_date AS d ON f.date_id = d.date_id
    WHERE
        d.date_id BETWEEN 20240101 AND 20240630
    GROUP BY
        r.reason_name,
        r.category
),
with_percentages AS (
    -- Расчёт процентов и нарастающего итога
    SELECT
        reason_name,
        category,
        total_hours,
        ROUND(total_hours / grand_total_hours * 100, 2) AS pct,
        ROUND(
            SUM(total_hours) OVER (
                ORDER BY total_hours DESC
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) / grand_total_hours * 100, 2
        ) AS cumulative_pct
    FROM
        reason_totals
)
SELECT
    reason_name,
    category,
    ROUND(total_hours, 2) AS total_hours,
    pct,
    cumulative_pct,
    CASE
        WHEN cumulative_pct <= 80 THEN 'A'
        WHEN cumulative_pct <= 95 THEN 'B'
        ELSE 'C'
    END AS pareto_category
FROM
    with_percentages
ORDER BY
    total_hours DESC;



-- ============================================================================
-- Задание 10. Дедупликация и обработка повторных записей (сложное)
-- Использование ROW_NUMBER() для удаления дубликатов телеметрии
-- ============================================================================

WITH telemetry_with_rn AS (
    SELECT
        telemetry_id,
        sensor_id,
        date_id,
        time_id,
        sensor_value,
        is_alarm,
        quality_flag,
        loaded_at,
        ROW_NUMBER() OVER (
            PARTITION BY sensor_id, date_id, time_id
            ORDER BY telemetry_id DESC
        ) AS rn
    FROM
        fact_equipment_telemetry
    WHERE
        date_id BETWEEN 20240101 AND 20240107
),
deduplicated AS (
    SELECT *
    FROM telemetry_with_rn
    WHERE rn = 1
),
stats AS (
    SELECT
        (SELECT COUNT(*) FROM telemetry_with_rn) AS total_before,
        (SELECT COUNT(*) FROM deduplicated) AS total_after,
        (SELECT COUNT(*) FROM telemetry_with_rn) - 
        (SELECT COUNT(*) FROM deduplicated) AS duplicates_removed
)
SELECT
    total_before,
    total_after,
    duplicates_removed,
    ROUND(duplicates_removed::NUMERIC / NULLIF(total_before, 0) * 100, 2) AS duplicate_pct
FROM
    stats;

-- Просмотр дедуплицированных данных (отдельный запрос)
WITH telemetry_with_rn AS (
    SELECT
        telemetry_id,
        sensor_id,
        date_id,
        time_id,
        sensor_value,
        is_alarm,
        quality_flag,
        loaded_at,
        ROW_NUMBER() OVER (
            PARTITION BY sensor_id, date_id, time_id
            ORDER BY telemetry_id DESC
        ) AS rn
    FROM
        fact_equipment_telemetry
    WHERE
        date_id BETWEEN 20240101 AND 20240107
)
SELECT
    telemetry_id,
    sensor_id,
    date_id,
    time_id,
    sensor_value,
    is_alarm,
    quality_flag,
    loaded_at
FROM
    telemetry_with_rn
WHERE
    rn = 1
    AND sensor_id = 1
ORDER BY
    date_id,
    time_id
LIMIT 20;



-- ============================================================================
-- Задание 11. Предиктивное обслуживание: обнаружение аномалий в телеметрии
-- Использование скользящих окон, LAG, PERCENT_RANK для выявления рисков
-- ============================================================================

WITH sensor_anomalies AS (
    SELECT
        ft.telemetry_id,
        ft.sensor_id,
        ft.date_id,
        ft.time_id,
        d.full_date,
        ft.sensor_value,
        AVG(ft.sensor_value) OVER w8 AS moving_avg_8,
        STDDEV(ft.sensor_value) OVER w8 AS moving_stddev_8,
        ft.sensor_value - LAG(ft.sensor_value, 1) OVER w_seq AS delta_from_prev,
        PERCENT_RANK() OVER w_seq AS pct_rank
    FROM
        fact_equipment_telemetry AS ft
    JOIN
        dim_date AS d ON ft.date_id = d.date_id
    WHERE
        ft.equipment_id = 1
        AND ft.date_id BETWEEN 20240101 AND 20240107
    WINDOW
        w8 AS (
            PARTITION BY ft.sensor_id
            ORDER BY ft.date_id, ft.time_id
            ROWS BETWEEN 7 PRECEDING AND CURRENT ROW
        ),
        w_seq AS (
            PARTITION BY ft.sensor_id
            ORDER BY ft.date_id, ft.time_id
        )
),
with_risk_level AS (
    SELECT
        telemetry_id,
        sensor_id,
        full_date,
        time_id,
        ROUND(sensor_value::NUMERIC, 2) AS sensor_value,         
        ROUND(moving_avg_8::NUMERIC, 2) AS moving_avg_8,         
        ROUND(moving_stddev_8::NUMERIC, 2) AS moving_stddev_8,   
        ROUND(delta_from_prev::NUMERIC, 2) AS delta_from_prev,    
        ROUND(pct_rank::NUMERIC, 4) AS pct_rank,   
        CASE
            WHEN pct_rank > 0.95 THEN 'ОПАСНОСТЬ'
            WHEN pct_rank > 0.85 THEN 'ВНИМАНИЕ'
            ELSE 'Норма'
        END AS risk_level
    FROM
        sensor_anomalies
)
SELECT
    sensor_id,
    full_date,
    time_id,
    sensor_value,
    moving_avg_8,
    moving_stddev_8,
    delta_from_prev,
    pct_rank,
    risk_level
FROM
    with_risk_level
WHERE
    risk_level IN ('ОПАСНОСТЬ', 'ВНИМАНИЕ')
ORDER BY
    sensor_id,
    full_date,
    time_id;




-- ============================================================================
-- Задание 12. Комплексный производственный дашборд (сложное)
-- ============================================================================

WITH daily_production AS (
    -- Базовая агрегация: суточная добыча по шахте 1 за январь 2024
    SELECT
        d.full_date,
        d.date_id,
        SUM(fp.tons_mined) AS daily_tons
    FROM
        fact_production AS fp
    JOIN
        dim_date AS d ON fp.date_id = d.date_id
    WHERE
        fp.mine_id = 1
        AND d.date_id BETWEEN 20240101 AND 20240131
    GROUP BY
        d.full_date,
        d.date_id
),
median_calc AS (
    -- Расчет медианы в отдельном CTE (агрегат, а не окно)
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_tons)::NUMERIC AS median_tons
    FROM
        daily_production
),
with_window_metrics AS (
    -- Расчёт всех оконных функций с именованными окнами
    SELECT
        dp.full_date,
        dp.date_id,
        dp.daily_tons,
        m.median_tons,
        -- Добыча предыдущего дня
        LAG(dp.daily_tons, 1) OVER w_seq AS prev_day_tons,
        -- Изменение день-к-дню (%) - ИСПРАВЛЕНО: CAST всего выражения
        ROUND(
            (
                (dp.daily_tons - LAG(dp.daily_tons, 1) OVER w_seq)::NUMERIC / 
                NULLIF(LAG(dp.daily_tons, 1) OVER w_seq, 0) * 100
            ),
            2
        ) AS day_over_day_pct,
        -- 7-дневное скользящее среднее - ИСПРАВЛЕНО: CAST внутри ROUND
        ROUND(
            (AVG(dp.daily_tons) OVER w7)::NUMERIC, 2
        ) AS moving_avg_7d,
        -- Нарастающий итог с начала месяца
        SUM(dp.daily_tons) OVER w_seq AS running_total,
        -- Ранг дня по добыче за месяц
        RANK() OVER (
            ORDER BY dp.daily_tons DESC
        ) AS month_rank,
        -- NTILE(3) для категоризации
        NTILE(3) OVER w_seq AS production_tile
    FROM
        daily_production AS dp
    CROSS JOIN
        median_calc AS m
    WINDOW
        w_seq AS (ORDER BY dp.full_date),
        w7 AS (
            ORDER BY dp.full_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )
),
with_final_metrics AS (
    -- Финальные расчёты: отклонение от медианы и текстовый тренд
    SELECT
        full_date,
        date_id,
        daily_tons,
        prev_day_tons,
        day_over_day_pct,
        moving_avg_7d,
        running_total,
        month_rank,
        production_tile,
        ROUND(median_tons, 2) AS median_tons,
        -- Отклонение от медианы (%)
        ROUND(
            (
                (daily_tons - median_tons)::NUMERIC / 
                NULLIF(median_tons, 0) * 100
            ),
            2
        ) AS deviation_from_median_pct,
        CASE
            WHEN day_over_day_pct IS NULL THEN 'нет данных'
            WHEN day_over_day_pct > 5 THEN 'рост'
            WHEN day_over_day_pct < -5 THEN 'снижение'
            ELSE 'стабильно'
        END AS trend,
        -- Категория добычи по NTILE
        CASE
            WHEN production_tile = 1 THEN 'Низкая'
            WHEN production_tile = 2 THEN 'Средняя'
            WHEN production_tile = 3 THEN 'Высокая'
        END AS production_category
    FROM
        with_window_metrics
)
SELECT
    full_date,
    daily_tons,
    prev_day_tons,
    day_over_day_pct,
    moving_avg_7d,
    running_total,
    month_rank,
    production_category,
    median_tons,
    deviation_from_median_pct,
    trend
FROM
    with_final_metrics
ORDER BY
    full_date;
   


