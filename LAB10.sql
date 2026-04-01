
-- Задание 1. Скалярный подзапрос — фильтрация (простое)
SELECT
    o.last_name || ' ' || LEFT(o.first_name, 1) || '.' AS full_name,
    SUM(fp.tons_mined) AS total_mined,
    (
        SELECT AVG(shift_total)
        FROM (
            SELECT SUM(fp2.tons_mined) AS shift_total
            FROM fact_production AS fp2
            JOIN dim_date AS d2 ON fp2.date_id = d2.date_id
            WHERE d2.date_id BETWEEN 20240301 AND 20240331
            GROUP BY fp2.operator_id
        ) AS operator_averages
    ) AS avg_production
FROM
    fact_production AS fp
JOIN
    dim_operator AS o ON fp.operator_id = o.operator_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    o.last_name,
    o.first_name
HAVING
    SUM(fp.tons_mined) > (
        SELECT AVG(shift_total)
        FROM (
            SELECT SUM(fp2.tons_mined) AS shift_total
            FROM fact_production AS fp2
            JOIN dim_date AS d2 ON fp2.date_id = d2.date_id
            WHERE d2.date_id BETWEEN 20240301 AND 20240331
            GROUP BY fp2.operator_id
        ) AS operator_averages
    )
ORDER BY
    total_mined DESC;

-- Задание 2. Многозначный подзапрос с IN (простое)
SELECT
    s.sensor_code,
    st.type_name AS sensor_type_name,
    e.equipment_name,
    s.status
FROM
    dim_sensor AS s
JOIN
    dim_sensor_type AS st ON s.sensor_type_id = st.sensor_type_id
JOIN
    dim_equipment AS e ON s.equipment_id = e.equipment_id
WHERE
    s.equipment_id IN (
        SELECT DISTINCT fp.equipment_id
        FROM fact_production AS fp
        JOIN dim_date AS d ON fp.date_id = d.date_id
        WHERE d.date_id BETWEEN 20240101 AND 20240331
    )
ORDER BY
    e.equipment_name,
    s.sensor_code;


-- Задание 3. NOT IN и ловушка с NULL (среднее)
-- Вариант 1: NOT IN 

SELECT
    e.equipment_name,
    et.type_name,
    m.mine_name,
    e.status
FROM
    dim_equipment AS e
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
WHERE
    e.equipment_id NOT IN (
        SELECT fp.equipment_id
        FROM fact_production AS fp
        WHERE fp.equipment_id IS NOT NULL
    )
ORDER BY
    e.equipment_name;

-- Вариант 2: NOT EXISTS 
SELECT
    e.equipment_name,
    et.type_name,
    m.mine_name,
    e.status
FROM
    dim_equipment AS e
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
WHERE
    NOT EXISTS (
        SELECT 1
        FROM fact_production AS fp
        WHERE fp.equipment_id = e.equipment_id
    )
ORDER BY
    e.equipment_name;

-- Вопрос для размышления:
/*
Если убрать WHERE equipment_id IS NOT NULL из подзапроса NOT IN,
и в fact_production есть хотя бы один NULL в equipment_id,
то весь запрос вернёт ПУСТОЙ результат.
Причина: в SQL только (TRUE, FALSE, UNKNOWN).
Сравнение с NULL даёт UNKNOWN, а NOT IN с NULL в списке всегда UNKNOWN.
WHERE UNKNOWN не пропускает строки, значит результат будет пуст.
NOT EXISTS не имеет этой проблемы, так как проверяет существование строк,
а не сравнивает значения с NULL.
*/

-- Задание 4. Коррелированный подзапрос — сравнение внутри группы (среднее)
SELECT
    m.mine_name,
    d.full_date,
    e.equipment_name,
    fp.tons_mined,
    (
        SELECT AVG(fp2.tons_mined)
        FROM fact_production AS fp2
        WHERE fp2.mine_id = fp.mine_id
          AND fp2.date_id BETWEEN 20240101 AND 20240331
    ) AS mine_avg,
    fp.tons_mined - (
        SELECT AVG(fp2.tons_mined)
        FROM fact_production AS fp2
        WHERE fp2.mine_id = fp.mine_id
          AND fp2.date_id BETWEEN 20240101 AND 20240331
    ) AS deviation
FROM
    fact_production AS fp
JOIN
    dim_mine AS m ON fp.mine_id = m.mine_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
WHERE
    fp.date_id BETWEEN 20240101 AND 20240331
    AND fp.tons_mined < (
        SELECT AVG(fp2.tons_mined)
        FROM fact_production AS fp2
        WHERE fp2.mine_id = fp.mine_id
          AND fp2.date_id BETWEEN 20240101 AND 20240331
    )
ORDER BY
    deviation ASC
LIMIT 20;


-- Задание 5. EXISTS — оборудование с тревожными показаниями (среднее)
SELECT
    e.equipment_name,
    et.type_name,
    m.mine_name,
    (
        SELECT COUNT(*)
        FROM fact_equipment_telemetry AS ft
        WHERE ft.equipment_id = e.equipment_id
          AND ft.is_alarm = TRUE
          AND ft.date_id BETWEEN 20240301 AND 20240331
    ) AS alarm_count
FROM
    dim_equipment AS e
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
WHERE
    EXISTS (
        SELECT 1
        FROM fact_equipment_telemetry AS ft
        WHERE ft.equipment_id = e.equipment_id
          AND ft.is_alarm = TRUE
          AND ft.date_id BETWEEN 20240301 AND 20240331
    )
ORDER BY
    alarm_count DESC;

-- Вопрос: Можно ли решить через JOIN + GROUP BY?

SELECT
    e.equipment_name,
    et.type_name,
    m.mine_name,
    COUNT(*) AS alarm_count
FROM
    dim_equipment AS e
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
JOIN
    fact_equipment_telemetry AS ft ON e.equipment_id = ft.equipment_id
WHERE
    ft.is_alarm = TRUE
    AND ft.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name,
    et.type_name,
    m.mine_name
ORDER BY
    alarm_count DESC;

-- Сравнение:
-- EXISTS + подзапрос: гибкий, медленный
-- JOIN + GROUP BY: читаемый, производительный

-- Задание 6. NOT EXISTS — поиск «пробелов» в данных (среднее)
SELECT
    d.full_date,
    d.day_of_week_name,
    d.is_weekend
FROM
    dim_date AS d
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
    AND NOT EXISTS (
        SELECT 1
        FROM fact_production AS fp
        WHERE fp.date_id = d.date_id
          AND fp.equipment_id = 5
    )
ORDER BY
    d.full_date;

-- Альтернативный вариант с LEFT JOIN (для сравнения):
SELECT
    d.full_date,
    d.day_of_week_name,
    d.is_weekend
FROM
    dim_date AS d
LEFT JOIN
    fact_production AS fp ON d.date_id = fp.date_id AND fp.equipment_id = 5
WHERE
    d.date_id BETWEEN 20240301 AND 20240331
    AND fp.production_id IS NULL
ORDER BY
    d.full_date;



-- Задание 7. Подзапрос с ANY/ALL (среднее)
-- Вариант 1: ALL
SELECT
    e.equipment_name,
    et.type_name,
    d.full_date,
    s.shift_name,
    fp.tons_mined
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
JOIN
    dim_shift AS s ON fp.shift_id = s.shift_id
WHERE
    fp.tons_mined > ALL (
        SELECT fp2.tons_mined
        FROM fact_production AS fp2
        JOIN dim_equipment AS e2 ON fp2.equipment_id = e2.equipment_id
        JOIN dim_equipment_type AS et2 ON e2.equipment_type_id = et2.equipment_type_id
        WHERE et2.type_code = 'TRUCK'
    )
ORDER BY
    fp.tons_mined DESC;

-- Вариант 2: (SELECT MAX(...)) 
SELECT
    e.equipment_name,
    et.type_name,
    d.full_date,
    s.shift_name,
    fp.tons_mined
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
JOIN
    dim_shift AS s ON fp.shift_id = s.shift_id
WHERE
    fp.tons_mined > (
        SELECT MAX(fp2.tons_mined)
        FROM fact_production AS fp2
        JOIN dim_equipment AS e2 ON fp2.equipment_id = e2.equipment_id
        JOIN dim_equipment_type AS et2 ON e2.equipment_type_id = et2.equipment_type_id
        WHERE et2.type_code = 'TRUCK'
    )
ORDER BY
    fp.tons_mined DESC;

-- Вариант 3: ANY (SELECT MIN(...))
SELECT
    e.equipment_name,
    et.type_name,
    d.full_date,
    s.shift_name,
    fp.tons_mined
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
JOIN
    dim_shift AS s ON fp.shift_id = s.shift_id
WHERE
    fp.tons_mined > ANY (
        SELECT fp2.tons_mined
        FROM fact_production AS fp2
        JOIN dim_equipment AS e2 ON fp2.equipment_id = e2.equipment_id
        JOIN dim_equipment_type AS et2 ON e2.equipment_type_id = et2.equipment_type_id
        WHERE et2.type_code = 'TRUCK'
    )
ORDER BY
    fp.tons_mined DESC;


