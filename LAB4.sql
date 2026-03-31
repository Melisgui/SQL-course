-- Задание 1. Анализ длины строковых полей
SELECT
    equipment_name,
    LENGTH(equipment_name) AS name_len,
    LENGTH(inventory_number) AS inv_len,
    LENGTH(model) AS model_len,
    LENGTH(manufacturer) AS manuf_len,
    COALESCE(LENGTH(equipment_name), 0)
    + COALESCE(LENGTH(inventory_number), 0)
    + COALESCE(LENGTH(model), 0)
    + COALESCE(LENGTH(manufacturer), 0) AS total_text_length
FROM
    dim_equipment
ORDER BY
    total_text_length DESC;

-- Задание 2. Разбор инвентарного номера
SELECT
    equipment_name,
    inventory_number,
    SPLIT_PART(inventory_number, '-', 1) AS prefix,
    SPLIT_PART(inventory_number, '-', 2) AS type_code,
    CAST(SPLIT_PART(inventory_number, '-', 3) AS INTEGER) AS serial_number,
    CASE
        WHEN SPLIT_PART(inventory_number, '-', 2) = 'LHD' THEN 'Погрузочно-доставочная машина'
        WHEN SPLIT_PART(inventory_number, '-', 2) = 'TRUCK' THEN 'Шахтный самосвал'
        WHEN SPLIT_PART(inventory_number, '-', 2) = 'CART' THEN 'Вагонетка'
        WHEN SPLIT_PART(inventory_number, '-', 2) = 'SKIP' THEN 'Скиповой подъёмник'
        ELSE 'Неизвестный тип'
    END AS type_description
FROM
    dim_equipment
ORDER BY
    type_code,
    serial_number;

-- Задание 3. Формирование краткого имени оператора
SELECT
    o.last_name || ' ' || 
    UPPER(LEFT(o.first_name, 1)) || '.' || 
    COALESCE(UPPER(LEFT(o.middle_name, 1)) || '.', '') AS short_name_fio,
    UPPER(LEFT(o.first_name, 1)) || '.' || 
    COALESCE(UPPER(LEFT(o.middle_name, 1)) || '.', '') || ' ' || o.last_name AS short_name_ifo,
    UPPER(o.last_name) AS last_name_upper,
    LOWER(o.position) AS position_lower
FROM
    dim_operator AS o
ORDER BY
    o.last_name;

-- Задание 4. Поиск оборудования по шаблону
-- 4.1. Оборудование с «ПДМ» в названии
SELECT
    equipment_name,
    inventory_number,
    manufacturer
FROM
    dim_equipment
WHERE
    equipment_name LIKE '%ПДМ%';

-- 4.2. Производители, начинающиеся на «S» (без учёта регистра)
SELECT
    equipment_name,
    manufacturer
FROM
    dim_equipment
WHERE
    manufacturer ILIKE 'S%';

-- 4.3. Шахты с кавычками в названии
SELECT
    mine_name,
    mine_code,
    region
FROM
    dim_mine
WHERE
    mine_name LIKE '%"%' 
    OR POSITION('"' IN mine_name) > 0;

-- 4.4. Инвентарные номера с серийной частью 001-010 (regex)
SELECT
    equipment_name,
    inventory_number
FROM
    dim_equipment
WHERE
    inventory_number ~ '-[A-Z]+-0(0[1-9]|10)$';

-- Задание 5. Список оборудования по шахтам
SELECT
    m.mine_name,
    COUNT(e.equipment_id) AS equipment_count,
    STRING_AGG(e.equipment_name, ', ' ORDER BY e.equipment_name) AS equipment_list,
    STRING_AGG(DISTINCT e.manufacturer, ', ' ORDER BY e.manufacturer) AS manufacturers_list
FROM
    dim_mine AS m
JOIN
    dim_equipment AS e ON m.mine_id = e.mine_id
GROUP BY
    m.mine_name
ORDER BY
    m.mine_name;


-- Задание 6. Возраст оборудования
SELECT
    e.equipment_name,
    e.commissioning_date,
    AGE(CURRENT_DATE, e.commissioning_date) AS age,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.commissioning_date))::INTEGER AS years,
    CURRENT_DATE - e.commissioning_date AS days_in_operation,
    CASE
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.commissioning_date)) < 2 THEN 'Новое'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.commissioning_date)) BETWEEN 2 AND 4 THEN 'Рабочее'
        ELSE 'Требует внимания'
    END AS category
FROM
    dim_equipment AS e
ORDER BY
    years DESC;

-- Задание 7. Форматирование дат для отчётов
SELECT
    e.equipment_name,
    e.commissioning_date,
    TO_CHAR(e.commissioning_date, 'DD.MM.YYYY') AS date_russian,
    TO_CHAR(e.commissioning_date, 'DD "Марта" YYYY "г."') AS date_full,
    TO_CHAR(e.commissioning_date, 'YYYY-MM-DD') AS date_iso,
    TO_CHAR(e.commissioning_date, 'YYYY-"Q"Q') AS year_quarter,
    TO_CHAR(e.commissioning_date, 'Day') AS day_of_week,
    TO_CHAR(e.commissioning_date, 'YYYY-MM') AS year_month
FROM
    dim_equipment AS e
ORDER BY
    e.commissioning_date;

-- Задание 8. Анализ простоев по дням недели и часам
-- 8.1. Группировка по дням недели
SELECT
    TO_CHAR(f.start_time, 'Day') AS day_of_week,
    COUNT(*) AS downtime_count,
    ROUND(AVG(f.duration_min), 1) AS avg_duration_min
FROM
    fact_equipment_downtime AS f
GROUP BY
    TO_CHAR(f.start_time, 'Day'),
    EXTRACT(DOW FROM f.start_time)
ORDER BY
    EXTRACT(DOW FROM f.start_time);

-- 8.2. Группировка по часам (поиск пикового часа)
SELECT
    EXTRACT(HOUR FROM f.start_time)::INTEGER AS hour_of_day,
    COUNT(*) AS downtime_count,
    ROUND(AVG(f.duration_min), 1) AS avg_duration_min
FROM
    fact_equipment_downtime AS f
GROUP BY
    EXTRACT(HOUR FROM f.start_time)
ORDER BY
    downtime_count DESC
LIMIT 1;

-- Задание 9. Расчёт графика калибровки датчиков
SELECT
    e.equipment_name,
    s.sensor_code,
    s.calibration_date,
    CURRENT_DATE - s.calibration_date AS days_since_calibration,
    s.calibration_date + INTERVAL '180 days' AS next_calibration_date,
    CASE
        WHEN CURRENT_DATE - s.calibration_date > 180 THEN 'Просрочена'
        WHEN CURRENT_DATE - s.calibration_date BETWEEN 150 AND 180 THEN 'Скоро'
        ELSE 'В норме'
    END AS status
FROM
    dim_sensor AS s
JOIN
    dim_equipment AS e ON s.equipment_id = e.equipment_id
ORDER BY
    CASE
        WHEN CURRENT_DATE - s.calibration_date > 180 THEN 1
        WHEN CURRENT_DATE - s.calibration_date BETWEEN 150 AND 180 THEN 2
        ELSE 3
    END,
    s.calibration_date;

-- Задание 10. Комплексный отчёт: карточка оборудования
SELECT
    '[' || et.type_name || '] ' ||
    e.equipment_name || ' (' || e.manufacturer || ' ' || e.model || ') | ' ||
    'Шахта: ' || m.mine_name || ' | ' ||
    'Введён: ' || TO_CHAR(e.commissioning_date, 'DD.MM.YYYY') || ' | ' ||
    'Возраст: ' || EXTRACT(YEAR FROM AGE(CURRENT_DATE, e.commissioning_date))::INTEGER || ' лет | ' ||
    'Статус: ' || UPPER(
        CASE e.status
            WHEN 'active' THEN 'АКТИВЕН'
            WHEN 'maintenance' THEN 'НА ТО'
            WHEN 'decommissioned' THEN 'СПИСАН'
            ELSE e.status
        END
    ) || ' | ' ||
    'Видеорег.: ' || CASE WHEN e.has_video_recorder = TRUE THEN 'ДА' ELSE 'НЕТ' END || ' | ' ||
    'Навигация: ' || CASE WHEN e.has_navigation = TRUE THEN 'ДА' ELSE 'НЕТ' END AS equipment_card
FROM
    dim_equipment AS e
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id
JOIN
    dim_mine AS m ON e.mine_id = m.mine_id
ORDER BY
    e.equipment_name;