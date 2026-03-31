-- Задание 1. Добавление нового оборудования (INSERT — одна строка)

BEGIN;

INSERT INTO practice_dim_equipment (
    equipment_id,
    equipment_type_id,
    mine_id,
    equipment_name,
    inventory_number,
    manufacturer,
    model,
    year_manufactured,
    commissioning_date,
    status,
    has_video_recorder,
    has_navigation
) VALUES (
    200,
    2,
    2,
    'Самосвал МоАЗ-7529',
    'INV-TRK-200',
    'МоАЗ',
    '7529',
    2025,
    '2025-03-15',
    'active',
    TRUE,
    TRUE
);

-- Проверка: что запись создана
SELECT
    equipment_id,
    equipment_name,
    inventory_number,
    manufacturer,
    status,
    commissioning_date
FROM
    practice_dim_equipment
WHERE
    equipment_id = 200;

COMMIT;

-- Задание 2. Массовая вставка операторов (INSERT — несколько строк)
BEGIN;

INSERT INTO practice_dim_operator (
    operator_id,
    tab_number,
    last_name,
    first_name,
    middle_name,
    position,
    qualification,
    hire_date,
    mine_id
) VALUES
    (200, 'TAB-200', 'Сидоров', 'Михаил', 'Иванович', 'Машинист ПДМ', '4 разряд', '2025-03-01', 1),
    (201, 'TAB-201', 'Петрова', 'Елена', 'Сергеевна', 'Оператор скипа', '3 разряд', '2025-03-01', 2),
    (202, 'TAB-202', 'Волков', 'Дмитрий', 'Алексеевич', 'Водитель самосвала', '5 разряд', '2025-03-10', 2);

-- Проверка: должно быть 3 новых строки с operator_id >= 200
SELECT
    operator_id,
    tab_number,
    last_name || ' ' || first_name AS full_name,
    position,
    hire_date,
    mine_id
FROM
    practice_dim_operator
WHERE
    operator_id >= 200
ORDER BY
    operator_id;

COMMIT;

-- Задание 3. Загрузка из staging (INSERT ... SELECT)
BEGIN;

-- количество строк до INSERT
SELECT COUNT(*) AS count_before FROM practice_fact_production;

INSERT INTO practice_fact_production (
    production_id,
    date_id,
    shift_id,
    equipment_id,
    operator_id,
    tons_mined,
    operating_hours,
    fuel_consumed_l
)
SELECT
    3000 + sp.staging_id,
    sp.date_id,
    sp.shift_id,
    sp.equipment_id,
    sp.operator_id,
    sp.tons_mined,
    sp.operating_hours,
    sp.fuel_consumed_l
FROM
    staging_production AS sp
WHERE
    sp.is_validated = TRUE
    AND NOT EXISTS (
        SELECT 1
        FROM practice_fact_production AS pf
        WHERE
            pf.date_id = sp.date_id
            AND pf.shift_id = sp.shift_id
            AND pf.equipment_id = sp.equipment_id
            AND pf.operator_id = sp.operator_id
    );

-- Проверка: количество строк после INSERT
SELECT COUNT(*) AS count_after FROM practice_fact_production;

-- Проверка: новые записи
SELECT
    production_id,
    date_id,
    shift_id,
    equipment_id,
    operator_id,
    tons_mined
FROM
    practice_fact_production
WHERE
    production_id >= 3000
ORDER BY
    production_id;

COMMIT;




-- Задание 4. INSERT ... RETURNING с логированием

BEGIN;

WITH new_grade AS (
    INSERT INTO practice_dim_ore_grade (
        ore_grade_id,
        grade_name,
        grade_code,
        fe_content_min,
        fe_content_max,
        description
    ) VALUES (
        300,
        'Экспортный',
        'EXPORT',
        63.00,
        68.00,
        'Руда для экспортных поставок'
    )
    RETURNING ore_grade_id, grade_name, grade_code
)
INSERT INTO practice_equipment_log (
    equipment_id,
    action,
    details,
    changed_at
)
SELECT
    0,
    'INSERT',
    'Добавлен сорт руды: ' || ng.grade_name || ' (' || ng.grade_code || ')',
    CURRENT_TIMESTAMP
FROM
    new_grade AS ng;

-- Проверка: что сорт руды добавлен
SELECT
    ore_grade_id,
    grade_name,
    grade_code,
    fe_content_min,
    fe_content_max
FROM
    practice_dim_ore_grade
WHERE
    ore_grade_id = 300;

-- Проверка: что запись в лог добавлена
SELECT
    log_id,
    equipment_id,
    action,
    details,
    changed_at
FROM
    practice_equipment_log
WHERE
    action = 'INSERT'
    AND details LIKE '%Экспортный%'
ORDER BY
    changed_at DESC
LIMIT 1;

COMMIT;

-- Задание 5. Обновление статуса оборудования (UPDATE)
BEGIN;

-- Обновление статуса с возвратом затронутых записей
UPDATE practice_dim_equipment
SET
    status = 'maintenance'
WHERE
    mine_id = 1
    AND year_manufactured <= 2018
RETURNING
    equipment_id,
    equipment_name,
    year_manufactured,
    status;

-- Проверка: все единицы со статусом 'maintenance'
SELECT
    equipment_id,
    equipment_name,
    mine_id,
    year_manufactured,
    status,
    commissioning_date
FROM
    practice_dim_equipment
WHERE
    status = 'maintenance'
ORDER BY
    year_manufactured,
    equipment_id;

COMMIT;


-- Задание 6. UPDATE с подзапросом
BEGIN;

-- Проверка: сколько записей имеет has_navigation = FALSE до обновления
SELECT COUNT(*) AS before_update
FROM practice_dim_equipment
WHERE has_navigation = FALSE;


-- Вариант 1: Если есть столбец type_code или type_name для фильтрации по 'NAV'
UPDATE practice_dim_equipment AS e
SET
    has_navigation = TRUE
WHERE
    e.has_navigation = FALSE
    AND EXISTS (
        SELECT 1
        FROM dim_sensor AS s
        JOIN dim_sensor_type AS st ON s.sensor_type_id = st.sensor_type_id
        WHERE
            s.equipment_id = e.equipment_id
            AND st.type_code = 'NAV'  -- Или type_name, или другой столбец с кодом типа
            AND s.status = 'active'
    );
   


-- Проверка: обновлённые записи
SELECT
    equipment_id,
    equipment_name,
    has_navigation,
    commissioning_date
FROM
    practice_dim_equipment
WHERE
    has_navigation = TRUE
ORDER BY
    equipment_id;

-- Проверка: сколько записей осталось с has_navigation = FALSE
SELECT COUNT(*) AS after_update
FROM practice_dim_equipment
WHERE has_navigation = FALSE;

COMMIT;


-- Задание 7. DELETE с условием и архивированием
BEGIN;

-- Проверка: количество записей с is_alarm = TRUE за 20240315 до удаления
SELECT COUNT(*) AS alarms_before
FROM practice_fact_telemetry
WHERE is_alarm = TRUE AND date_id = 20240315;

-- Проверка: структура таблицы practice_fact_telemetry
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'practice_fact_telemetry'
ORDER BY ordinal_position;

-- CTE с DELETE ... RETURNING для архивирования
WITH deleted_telemetry AS (
    DELETE FROM practice_fact_telemetry
    WHERE
        is_alarm = TRUE
        AND date_id = 20240315
    RETURNING
        telemetry_id,
        date_id,
        time_id,
        equipment_id,
        sensor_id,
        location_id,
        sensor_value,
        is_alarm,
        quality_flag,
        loaded_at
)
INSERT INTO practice_archive_telemetry (
    telemetry_id,
    date_id,
    time_id,
    equipment_id,
    sensor_id,
    location_id,
    sensor_value,
    is_alarm,
    quality_flag,
    loaded_at,
    archived_at
)
SELECT
    dt.telemetry_id,
    dt.date_id,
    dt.time_id,
    dt.equipment_id,
    dt.sensor_id,
    dt.location_id,
    dt.sensor_value,
    dt.is_alarm,
    dt.quality_flag,
    dt.loaded_at,
    CURRENT_TIMESTAMP
FROM
    deleted_telemetry AS dt;

-- Проверка: в practice_fact_telemetry нет записей с is_alarm = TRUE за 20240315
SELECT COUNT(*) AS alarms_after
FROM practice_fact_telemetry
WHERE is_alarm = TRUE AND date_id = 20240315;

-- Проверка: в practice_archive_telemetry появились архивные записи
SELECT
    COUNT(*) AS archived_count,
    MIN(archived_at) AS first_archived,
    MAX(archived_at) AS last_archived
FROM
    practice_archive_telemetry
WHERE
    date_id = 20240315
    AND is_alarm = TRUE;

COMMIT;

-- Задание 8. MERGE — синхронизация справочника (PostgreSQL 15+)

BEGIN;

-- Проверка перед синхронизацией: содержимое целевой таблицы
SELECT
    reason_id,
    reason_code,
    reason_name,
    category
FROM
    practice_dim_downtime_reason
ORDER BY
    reason_code;

-- Проверка перед синхронизацией: содержимое staging-таблицы
SELECT
    reason_code,
    reason_name,
    category,
    description
FROM
    staging_downtime_reasons
ORDER BY
    reason_code;

-- Синхронизация через INSERT ... ON CONFLICT 
INSERT INTO practice_dim_downtime_reason (
    reason_id,
    reason_code,
    reason_name,
    category,
    description
)
SELECT
    COALESCE(
        (SELECT MAX(reason_id) FROM practice_dim_downtime_reason), 0
    ) + ROW_NUMBER() OVER (ORDER BY s.reason_code) AS reason_id,
    s.reason_code,
    s.reason_name,
    s.category,
    s.description
FROM
    staging_downtime_reasons AS s
ON CONFLICT (reason_code) DO UPDATE SET
    reason_name = EXCLUDED.reason_name,
    category = EXCLUDED.category,
    description = EXCLUDED.description;

-- Проверка после синхронизации: что записи обновлены/добавлены
SELECT
    reason_id,
    reason_code,
    reason_name,
    category,
    description
FROM
    practice_dim_downtime_reason
ORDER BY
    reason_code;

-- Проверка: нет дубликатов по reason_code
SELECT
    reason_code,
    COUNT(*) AS duplicate_count
FROM
    practice_dim_downtime_reason
GROUP BY
    reason_code
HAVING
    COUNT(*) > 1;

COMMIT;

-- Задание 9. UPSERT —  загрузка (INSERT ... ON CONFLICT)
BEGIN;

-- Проверка: текущее состояние операторов с TAB-200 и TAB-201
SELECT
    operator_id,
    tab_number,
    last_name || ' ' || first_name AS full_name,
    position,
    qualification
FROM
    practice_dim_operator
WHERE
    tab_number IN ('TAB-200', 'TAB-201', 'TAB-NEW')
ORDER BY
    tab_number;

--  вставка/обновление операторов
INSERT INTO practice_dim_operator (
    operator_id,
    tab_number,
    last_name,
    first_name,
    middle_name,
    position,
    qualification,
    hire_date,
    mine_id
) VALUES
    (200, 'TAB-200', 'Сидоров', 'Михаил', 'Иванович', 'Машинист ПДМ', '5 разряд', '2025-03-01', 1),
    (201, 'TAB-201', 'Петрова', 'Елена', 'Сергеевна', 'Оператор скипа', '4 разряд', '2025-03-01', 2),
    (203, 'TAB-NEW', 'Новиков', 'Андрей', 'Петрович', 'Машинист самосвала', '3 разряд', '2025-03-15', 2)
ON CONFLICT (tab_number) DO UPDATE SET
    position = EXCLUDED.position,
    qualification = EXCLUDED.qualification;

-- Проверка: что записи вставлены/обновлены
SELECT
    operator_id,
    tab_number,
    last_name || ' ' || first_name AS full_name,
    position,
    qualification,
    hire_date
FROM
    practice_dim_operator
WHERE
    tab_number IN ('TAB-200', 'TAB-201', 'TAB-NEW')
ORDER BY
    tab_number;

-- Проверка: повторный запуск не создаст дубликатов 
SELECT
    tab_number,
    COUNT(*) AS record_count
FROM
    practice_dim_operator
WHERE
    tab_number IN ('TAB-200', 'TAB-201', 'TAB-NEW')
GROUP BY
    tab_number;

COMMIT;

