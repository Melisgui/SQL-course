CREATE TABLE IF NOT EXISTS error_log (
    log_id      SERIAL PRIMARY KEY,
    log_time    TIMESTAMP DEFAULT NOW(),
    severity    VARCHAR(20),
    source      VARCHAR(100),
    sqlstate    VARCHAR(5),
    message     TEXT,
    detail      TEXT,
    hint        TEXT,
    context     TEXT,
    username    VARCHAR(100) DEFAULT CURRENT_USER,
    parameters  JSONB
);

CREATE OR REPLACE FUNCTION log_error(
    p_severity VARCHAR, p_source VARCHAR,
    p_sqlstate VARCHAR DEFAULT NULL, p_message TEXT DEFAULT NULL,
    p_detail TEXT DEFAULT NULL, p_hint TEXT DEFAULT NULL,
    p_context TEXT DEFAULT NULL, p_parameters JSONB DEFAULT NULL
)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_log_id INT;
BEGIN
    INSERT INTO error_log (severity, source, sqlstate, message, detail, hint, context, parameters)
    VALUES (p_severity, p_source, p_sqlstate, p_message, p_detail, p_hint, p_context, p_parameters)
    RETURNING log_id INTO v_log_id;
    RETURN v_log_id;
END;
$$;

-- ============================================================================
-- ЗАДАНИЕ 1. Безопасное деление (простое)
-- ============================================================================

CREATE OR REPLACE FUNCTION safe_production_rate(
    p_tons NUMERIC,
    p_hours NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_tons IS NULL OR p_hours IS NULL THEN
        RETURN NULL;
    END IF;
    
    RETURN ROUND(p_tons / p_hours, 2);
    
EXCEPTION
    WHEN division_by_zero THEN
        RAISE WARNING 'Деление на ноль: tons=%, hours=%', p_tons, p_hours;
        RETURN 0;
END;
$$;

-- Тестирование
SELECT 'Тест 1: Корректные данные' AS test, safe_production_rate(150, 8) AS result;  -- 18.75
SELECT 'Тест 2: Деление на ноль' AS test, safe_production_rate(150, 0) AS result;    -- 0 + WARNING
SELECT 'Тест 3: NULL параметры' AS test, safe_production_rate(NULL, 8) AS result;     -- NULL

-- Применение к fact_production
SELECT
    equipment_id,
    tons_mined,
    operating_hours,
    safe_production_rate(tons_mined, operating_hours) AS rate
FROM
    fact_production
WHERE
    date_id = 20240115
ORDER BY
    rate DESC NULLS LAST
LIMIT 10;

-- ============================================================================
-- ЗАДАНИЕ 2. Валидация данных телеметрии (простое)
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_sensor_reading(
    p_sensor_type VARCHAR,
    p_value NUMERIC
)
RETURNS VARCHAR
LANGUAGE plpgsql
AS $$
DECLARE
    v_min NUMERIC;
    v_max NUMERIC;
BEGIN
    IF p_value IS NULL THEN
        RAISE EXCEPTION 'S0003' USING
            MESSAGE = 'Значение датчика не может быть NULL',
            HINT = 'Проверьте источник данных';
    END IF;
    
    CASE p_sensor_type
        WHEN 'Температура' THEN v_min := -40; v_max := 200;
        WHEN 'Давление' THEN v_min := 0; v_max := 500;
        WHEN 'Вибрация' THEN v_min := 0; v_max := 100;
        WHEN 'Скорость' THEN v_min := 0; v_max := 50;
        ELSE
            RAISE EXCEPTION 'S0001' USING
                MESSAGE = 'Неизвестный тип датчика: ' || p_sensor_type,
                HINT = 'Допустимые: Температура, Давление, Вибрация, Скорость';
    END CASE;
    
    IF p_value < v_min OR p_value > v_max THEN
        RAISE EXCEPTION 'S0002' USING
            MESSAGE = 'Значение вне диапазона: ' || p_value,
            HINT = 'Допустимый диапазон: ' || v_min || '..' || v_max;
    END IF;
    
    RETURN 'OK';
END;
$$;

-- Тестирование: корректные данные
SELECT 'Температура OK' AS test, validate_sensor_reading('Температура', 25) AS result;
SELECT 'Давление OK' AS test, validate_sensor_reading('Давление', 100) AS result;
SELECT 'Вибрация OK' AS test, validate_sensor_reading('Вибрация', 50) AS result;
SELECT 'Скорость OK' AS test, validate_sensor_reading('Скорость', 30) AS result;

-- Тестирование: ошибки
DO $$
BEGIN
    PERFORM validate_sensor_reading('Температура', 250);  -- S0002
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Ошибка S0002: %', SQLERRM;
END $$;

DO $$
BEGIN
    PERFORM validate_sensor_reading('Влажность', 50);  -- S0001
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Ошибка S0001: %', SQLERRM;
END $$;

-- ============================================================================
-- ЗАДАНИЕ 3. Обработка ошибок при вставке (среднее)
-- ============================================================================


-- Не получилось


-- ============================================================================
-- ЗАДАНИЕ 4. GET STACKED DIAGNOSTICS — детальный отчёт (среднее)
-- ============================================================================
CREATE OR REPLACE FUNCTION test_error_diagnostics(p_error_type INT)
RETURNS TABLE (field_name VARCHAR, field_value TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql_state VARCHAR;
    v_sql_message TEXT;
    v_sql_detail TEXT;
    v_sql_hint TEXT;
    v_sql_context TEXT;
    v_schema_name VARCHAR;
    v_table_name VARCHAR;
    v_column_name VARCHAR;
    v_constraint_name VARCHAR;
BEGIN
    -- Генерация ошибки по типу
    CASE p_error_type
        WHEN 1 THEN
            PERFORM 1 / 0;  
        WHEN 2 THEN
            INSERT INTO dim_mine (mine_id, mine_name, mine_code, status)
            VALUES (1, 'Дубль', 'DUP', 'active');  
        WHEN 3 THEN
            INSERT INTO fact_production (date_id, shift_id, equipment_id, operator_id, ore_grade_id, tons_mined, tons_transported, trips_count, distance_km, fuel_consumed_l, operating_hours, mine_id, shaft_id, location_id)
            VALUES (20240115, 1, 99999, 1, 1, 100, 95, 10, 50, 40, 8, 1, 1, 1);  
        WHEN 4 THEN
            PERFORM 'abc'::INT;
        WHEN 5 THEN
            RAISE EXCEPTION 'USER_DEFINED' USING
                MESSAGE = 'Пользовательская ошибка',
                DETAIL = 'Детали',
                HINT = 'Подсказка';
        ELSE
            RAISE EXCEPTION 'Неизвестный тип: %', p_error_type;
    END CASE;
    
    RETURN;
    
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_sql_state = RETURNED_SQLSTATE,
        v_sql_message = MESSAGE_TEXT,
        v_sql_detail = PG_EXCEPTION_DETAIL,
        v_sql_hint = PG_EXCEPTION_HINT,
        v_sql_context = PG_EXCEPTION_CONTEXT,
        v_schema_name = SCHEMA_NAME,
        v_table_name = TABLE_NAME,
        v_column_name = COLUMN_NAME,
        v_constraint_name = CONSTRAINT_NAME;
    
    -- Логирование ошибки в error_log
    PERFORM log_error(
        p_severity := 'ERROR',
        p_source := 'test_error_diagnostics(type=' || p_error_type || ')',
        p_sqlstate := v_sql_state,
        p_message := v_sql_message,
        p_detail := v_sql_detail,
        p_hint := v_sql_hint,
        p_context := v_sql_context
    );
    
    -- Возврат полей как таблицу
    RETURN QUERY SELECT 'RETURNED_SQLSTATE'::VARCHAR, v_sql_state::TEXT
    UNION ALL SELECT 'MESSAGE_TEXT', v_sql_message
    UNION ALL SELECT 'PG_EXCEPTION_DETAIL', v_sql_detail
    UNION ALL SELECT 'PG_EXCEPTION_HINT', v_sql_hint
    UNION ALL SELECT 'PG_EXCEPTION_CONTEXT', v_sql_context
    UNION ALL SELECT 'SCHEMA_NAME', v_schema_name
    UNION ALL SELECT 'TABLE_NAME', v_table_name
    UNION ALL SELECT 'COLUMN_NAME', v_column_name
    UNION ALL SELECT 'CONSTRAINT_NAME', v_constraint_name;
END;
$$;

-- Тестирование для каждого типа ошибки
SELECT '=== Тип 1: Division by zero ===' AS test;
SELECT * FROM test_error_diagnostics(1);

SELECT '=== Тип 2: Unique violation ===' AS test;
SELECT * FROM test_error_diagnostics(2);

SELECT '=== Тип 3: Foreign key violation ===' AS test;
SELECT * FROM test_error_diagnostics(3);

SELECT '=== Тип 4: Invalid text representation ===' AS test;
SELECT * FROM test_error_diagnostics(4);

SELECT '=== Тип 5: Пользовательская ошибка ===' AS test;
SELECT * FROM test_error_diagnostics(5);

-- Проверка всех записей в error_log
SELECT
    log_id,
    log_time,
    severity,
    source,
    sqlstate,
    message,
    detail,
    hint,
    context
FROM
    error_log
WHERE
    source LIKE 'test_error_diagnostics%'
ORDER BY
    log_id DESC
LIMIT 20;


-- ============================================================================
-- ЗАДАНИЕ 5. Безопасный импорт с логированием (среднее)
-- ============================================================================

-- Создание таблицы промежуточного хранения
CREATE TABLE IF NOT EXISTS staging_lab_results (
    row_id       SERIAL PRIMARY KEY,
    mine_name    TEXT,
    sample_date  TEXT,
    fe_content   TEXT,
    moisture     TEXT,
    status       VARCHAR(20) DEFAULT 'NEW',
    error_msg    TEXT
);

-- Очистка и вставка тестовых данных
TRUNCATE TABLE staging_lab_results RESTART IDENTITY;

INSERT INTO staging_lab_results (mine_name, sample_date, fe_content, moisture, status) VALUES
    ('Северная', '2025-01-15', '58.5', '12.3', 'NEW'),      -- 1: Корректная
    ('Южная', '2025-01-15', '62.1', '10.5', 'NEW'),          -- 2: Корректная
    ('Неизвестная', '2025-01-15', '55.0', '11.0', 'NEW'),    -- 3: Несуществующая шахта
    ('Северная', '32-01-2025', '59.0', '13.0', 'NEW'),       -- 4: Некорректная дата
    ('Южная', '2025-01-15', 'N/A', '10.0', 'NEW'),           -- 5: Fe = N/A (не число)
    ('Северная', '2025-01-15', '150', '12.0', 'NEW'),        -- 6: Fe = 150 (вне диапазона)
    ('Западная', '2025-01-15', '61.5', '11.5', 'NEW'),       -- 7: Корректная
    ('Восточная', '2025-01-15', '57.8', '-5.0', 'NEW'),      -- 8: Moisture < 0
    ('Северная', '2025-01-15', '63.2', '14.1', 'NEW'),       -- 9: Корректная
    ('Южная', '2025-01-15', '60.0', '100.5', 'NEW');         -- 10: Moisture > 100

-- Функция обработки импорта
CREATE OR REPLACE FUNCTION process_lab_import()
RETURNS TABLE (total INT, valid INT, errors INT)
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_total INT := 0;
    v_valid INT := 0;
    v_errors INT := 0;
    v_fe NUMERIC;
    v_moisture NUMERIC;
    v_sample_date DATE;
    v_mine_id INT;
    v_error_msg TEXT;
BEGIN
    -- Перебор всех записей со status = 'NEW'
    FOR rec IN 
        SELECT row_id, mine_name, sample_date, fe_content, moisture
        FROM staging_lab_results
        WHERE status = 'NEW'
    LOOP
        v_total := v_total + 1;
        v_error_msg := NULL;
        
        -- Валидация в подблоке
        BEGIN
            -- 1. Проверка шахты
            SELECT mine_id INTO v_mine_id
            FROM dim_mine
            WHERE mine_name = rec.mine_name;
            
            IF v_mine_id IS NULL THEN
                RAISE EXCEPTION 'Шахта не найдена: %', rec.mine_name;
            END IF;
            
            -- 2. Преобразование и проверка даты
            BEGIN
                v_sample_date := rec.sample_date::DATE;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Некорректная дата: %', rec.sample_date;
            END;
            
            -- 3. Преобразование и проверка Fe
            BEGIN
                v_fe := rec.fe_content::NUMERIC;
                IF v_fe < 0 OR v_fe > 100 THEN
                    RAISE EXCEPTION 'Fe вне диапазона 0-100: %', v_fe;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Fe не является числом: %', rec.fe_content;
            END;
            
            -- 4. Преобразование и проверка влажности
            BEGIN
                v_moisture := rec.moisture::NUMERIC;
                IF v_moisture < 0 OR v_moisture > 100 THEN
                    RAISE EXCEPTION 'Влажность вне диапазона 0-100: %', v_moisture;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Влажность не является числом: %', rec.moisture;
            END;
            
            -- Все проверки пройдены - обновляем статус
            UPDATE staging_lab_results
            SET status = 'VALID',
                error_msg = NULL
            WHERE row_id = rec.row_id;
            
            v_valid := v_valid + 1;
            
        EXCEPTION WHEN OTHERS THEN
            -- Ошибка валидации
            v_errors := v_errors + 1;
            v_error_msg := SQLERRM;
            
            UPDATE staging_lab_results
            SET status = 'ERROR',
                error_msg = v_error_msg
            WHERE row_id = rec.row_id;
            
            -- Логирование ошибки
            PERFORM log_error(
                p_severity := 'WARNING',
                p_source := 'process_lab_import',
                p_sqlstate := SQLSTATE,
                p_message := v_error_msg,
                p_detail := 'row_id=' || rec.row_id || ', mine=' || rec.mine_name,
                p_context := 'Lab results validation',
                p_parameters := jsonb_build_object(
                    'row_id', rec.row_id,
                    'mine_name', rec.mine_name,
                    'fe_content', rec.fe_content,
                    'moisture', rec.moisture
                )
            );
        END;
    END LOOP;
    
    -- Возврат статистики
    RETURN QUERY SELECT v_total, v_valid, v_errors;
END;
$$;

-- Тестирование функции
SELECT * FROM process_lab_import();

-- Проверка результатов
SELECT row_id, mine_name, sample_date, fe_content, moisture, status, error_msg
FROM staging_lab_results
ORDER BY row_id;

-- Проверка error_log
SELECT log_id, severity, source, sqlstate, message, detail, context
FROM error_log
WHERE source = 'process_lab_import'
ORDER BY log_id DESC;

