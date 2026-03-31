
-- Задание 1 Справочник шахт
SELECT
    mine_name,
    mine_code,
    region,
    city,
    max_depth_m,
    status
FROM
    dim_mine
ORDER BY
    mine_name;


--Задание 2. Фильтрация оборудования 
SELECT
    equipment_name,
    inventory_number,
    manufacturer,
    model,
    year_manufactured
FROM
    dim_equipment
WHERE
    year_manufactured <= 2019
    AND has_video_recorder = True
ORDER BY
    year_manufactured ASC;




--Задание 3. Операторы шахты "Южная"(фильтр по связанной таблице)


SELECT
    o.last_name || ' ' || o.first_name || ' ' || o.middle_name AS full_name,
    o.position,
    o.qualification,
    o.hire_date
FROM
    dim_operator AS o
JOIN
    dim_mine AS m ON o.mine_id = m.mine_id 
WHERE
    m.mine_name = 'Шахта "Южная"'
    AND o.status = 'active'
ORDER BY
    o.hire_date ASC;





--Задание 4. Простои за конкретный месяц


SELECT
    d.full_date,
    e.equipment_name,
    r.reason_name,
    r.category,
    f.duration_min,
    f.is_planned,
    f.comment
FROM
    fact_equipment_downtime AS f
JOIN
    dim_date AS d ON f.date_id = d.date_id
JOIN
    dim_equipment AS e ON f.equipment_id = e.equipment_id
JOIN
    dim_downtime_reason AS r ON f.reason_id = r.reason_id
WHERE
    f.date_id >= 20240301
    AND f.date_id <= 20240331
ORDER BY
    f.duration_min DESC;




--Задание 5. Добыча по типам оборудования 

SELECT
    et.type_name,
    SUM(fp.tons_mined) AS total_tons,
    AVG(fp.tons_mined) AS avg_per_shift,
    COUNT(*) AS shift_count,
    SUM(fp.fuel_consumed_l) AS total_fuel
FROM
    fact_production AS fp
JOIN
    dim_equipment AS e ON fp.equipment_id = e.equipment_id 
JOIN
    dim_equipment_type AS et ON e.equipment_type_id = et.equipment_type_id 
GROUP BY
    et.type_name
ORDER BY
    total_tons DESC;



--Задание 6.Среджнее содержаник Fe по шахтам и сменам

SELECT
    m.mine_name,
    s.shift_name,
    COUNT(*) AS sample_count,
    ROUND(AVG(oq.fe_content), 2) AS avg_fe,
    ROUND(MIN(oq.fe_content), 2) AS min_fe,
    ROUND(MAX(oq.fe_content), 2) AS max_fe
FROM
    fact_ore_quality AS oq
JOIN
    dim_mine AS m ON oq.mine_id = m.mine_id
JOIN
    dim_shift AS s ON oq.shift_id = s.shift_id
GROUP BY
    m.mine_name,
    s.shift_name
ORDER BY
    m.mine_name,
    s.shift_name;


--Задачние 7. Топ 3 месяца по добыче для каждой шахты

SELECT
    d.year_month,
    SUM(fp.tons_mined) AS total_tons,
    AVG(fp.tons_mined) AS avg_per_shift
FROM
    fact_production AS fp
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    fp.mine_id = 1
GROUP BY
    d.year_month
ORDER BY
    total_tons DESC
LIMIT 3;


--Задание 8. анализ простоев по оборудованию 

SELECT
    e.equipment_name,
    COUNT(*) AS downtime_count,
    SUM(f.duration_min) AS total_duration,
    AVG(f.duration_min) AS avg_duration
FROM
    fact_equipment_downtime AS f
JOIN
    dim_equipment AS e ON f.equipment_id = e.equipment_id
WHERE
    f.is_planned = FALSE  
GROUP BY
    e.equipment_name
HAVING
    SUM(f.duration_min) > 1000  
ORDER BY
    total_duration DESC;


--Задание 9. Сравнение производительности операторов 

SELECT
    o.last_name || ' ' || o.first_name || ' ' || COALESCE(o.middle_name, '') AS full_name,
    o.position,
    COUNT(*) AS shift_count,
    SUM(fp.tons_mined) AS total_tons,
    AVG(fp.tons_mined) AS avg_tons_shift,
    SUM(fp.operating_hours) AS total_hours,
    SUM(fp.tons_mined) / NULLIF(SUM(fp.operating_hours), 0) AS productivity
FROM
    fact_production AS fp
JOIN
    dim_operator AS o ON fp.operator_id = o.operator_id
GROUP BY
    o.last_name,
    o.first_name,
    o.middle_name,
    o.position
ORDER BY
    productivity DESC;



-- Задание 10. Комплексный кейс: ежкемесячнфый отчет джля директора

--10.1 добыча по шахтам за январь 2024
SELECT
    m.mine_name,
    SUM(fp.tons_mined) AS total_tons,
    AVG(fp.tons_mined) AS avg_per_shift,
    COUNT(*) AS shift_count,
    SUM(fp.fuel_consumed_l) AS total_fuel,
    SUM(fp.fuel_consumed_l) / NULLIF(SUM(fp.tons_mined), 0) AS fuel_per_ton
FROM
    fact_production AS fp
JOIN
    dim_mine AS m ON fp.mine_id = m.mine_id
JOIN
    dim_date AS d ON fp.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240101 AND 20240131
GROUP BY
    m.mine_name
ORDER BY
    total_tons DESC;



--10.2 Простои за январь 2024 по категориям
SELECT
    r.category,
    COUNT(*) AS downtime_count,
    SUM(f.duration_min) / 60.0 AS total_hours, 
    AVG(f.duration_min) AS avg_minutes
FROM
    fact_equipment_downtime AS f
JOIN
    dim_downtime_reason AS r ON f.reason_id = r.reason_id
JOIN
    dim_date AS d ON f.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240101 AND 20240131
GROUP BY
    r.category
ORDER BY
    total_hours DESC;


--10.3 качество руды за январь 2024
SELECT
    m.mine_name,
    g.grade_name,
    COUNT(*) AS sample_count,
    ROUND(AVG(oq.fe_content), 2) AS avg_fe,
    ROUND(AVG(oq.moisture), 2) AS avg_moisture
FROM
    fact_ore_quality AS oq
JOIN
    dim_mine AS m ON oq.mine_id = m.mine_id
JOIN
    dim_ore_grade AS g ON oq.ore_grade_id = g.ore_grade_id
JOIN
    dim_date AS d ON oq.date_id = d.date_id
WHERE
    d.date_id BETWEEN 20240101 AND 20240131
GROUP BY
    m.mine_name,
    g.grade_name
ORDER BY
    m.mine_name,
    g.grade_name;


