-- ============================================================================
-- ЗАДАНИЕ 1. Анонимный блок — статистика по шахтам (простое)
-- ============================================================================

DO $$
DECLARE
    v_mine_count INT;
    v_total_tons NUMERIC;
    v_avg_fe NUMERIC;
    v_downtime_count INT;
BEGIN
    -- Количество шахт
    SELECT COUNT(*) INTO v_mine_count FROM dim_mine WHERE status = 'active';
    
    -- Добыча за январь 2025
    SELECT COALESCE(SUM(tons_mined), 0) INTO v_total_tons
    FROM fact_production
    WHERE date_id BETWEEN 20250101 AND 20250131;
    
    -- Среднее содержание Fe
    SELECT COALESCE(ROUND(AVG(fe_content), 1), 0) INTO v_avg_fe
    FROM fact_ore_quality
    WHERE date_id BETWEEN 20250101 AND 20250131;
    
    -- Количество простоев
    SELECT COUNT(*) INTO v_downtime_count
    FROM fact_equipment_downtime
    WHERE date_id BETWEEN 20250101 AND 20250131;
    
    -- Вывод отчёта
    RAISE NOTICE '';
    RAISE NOTICE '===== Сводка по предприятию «Руда+» =====';
    RAISE NOTICE 'Количество шахт: %', v_mine_count;
    RAISE NOTICE 'Добыча за январь 2025: % т', v_total_tons;
    RAISE NOTICE 'Среднее содержание Fe: % %%', v_avg_fe;
    RAISE NOTICE 'Количество простоев: %', v_downtime_count;
    RAISE NOTICE '==========================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- ЗАДАНИЕ 2. Переменные и классификация — категории оборудования (простое)
-- ============================================================================

DO $$
DECLARE
    rec RECORD;
    v_age_years INT;
    v_category VARCHAR;
    v_new_count INT := 0;
    v_working_count INT := 0;
    v_attention_count INT := 0;
    v_replacement_count INT := 0;
    v_commissioning_date DATE;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===== Классификация оборудования по возрасту =====';
    RAISE NOTICE '';
    
    -- Проход по всему оборудованию
    FOR rec IN 
        SELECT equipment_id, equipment_name, type_name
        FROM dim_equipment e
        JOIN dim_equipment_type et ON e.equipment_type_id = et.equipment_type_id
        WHERE e.status = 'active'
        ORDER BY e.equipment_name
    LOOP
        -- Генерация тестовой даты ввода в эксплуатацию 
        v_commissioning_date := CURRENT_DATE - ((rec.equipment_id * 100)::INT + (random() * 1000)::INT);
        
        -- Вычисление возраста в годах
        v_age_years := EXTRACT(YEAR FROM AGE(CURRENT_DATE, v_commissioning_date))::INT;
        
        -- Классификация
        IF v_age_years < 2 THEN
            v_category := 'Новое';
            v_new_count := v_new_count + 1;
        ELSIF v_age_years BETWEEN 2 AND 5 THEN
            v_category := 'Рабочее';
            v_working_count := v_working_count + 1;
        ELSIF v_age_years BETWEEN 5 AND 10 THEN
            v_category := 'Требует внимания';
            v_attention_count := v_attention_count + 1;
        ELSE
            v_category := 'На замену';
            v_replacement_count := v_replacement_count + 1;
        END IF;
        
        -- Вывод строки
        RAISE NOTICE '% | % | % лет | %', 
            rec.equipment_name, rec.type_name, v_age_years, v_category;
    END LOOP;
    
    -- Сводка
    RAISE NOTICE '';
    RAISE NOTICE '===== Сводка по категориям =====';
    RAISE NOTICE 'Новое: %', v_new_count;
    RAISE NOTICE 'Рабочее: %', v_working_count;
    RAISE NOTICE 'Требует внимания: %', v_attention_count;
    RAISE NOTICE 'На замену: %', v_replacement_count;
    RAISE NOTICE 'Всего: %', v_new_count + v_working_count + v_attention_count + v_replacement_count;
    RAISE NOTICE '================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- ЗАДАНИЕ 3. Циклы — подневной анализ добычи (простое)
-- ============================================================================

DO $$
DECLARE
    i INT;
    v_date_id INT;
    v_daily_tons NUMERIC := 0;
    v_running_total NUMERIC := 0;
    v_avg_so_far NUMERIC := 0;
    v_best_day INT := 1;
    v_best_tons NUMERIC := 0;
    v_record_flag VARCHAR := '';
    v_total_tons NUMERIC := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===== Подневной анализ добычи (январь 2025, дни 1-14) =====';
    RAISE NOTICE '';
    
    -- Цикл по дням
    FOR i IN 1..14 LOOP
        -- Формирование date_id (20250101 + i - 1)
        v_date_id := 20250100 + i;
        
        -- Получение добычи за день
        SELECT COALESCE(SUM(tons_mined), 0) INTO v_daily_tons
        FROM fact_production
        WHERE date_id = v_date_id;
        
        -- Нарастающий итог
        v_running_total := v_running_total + v_daily_tons;
        
        -- Средняя добыча за предыдущие дни
        IF i > 1 THEN
            v_avg_so_far := (v_running_total - v_daily_tons) / (i - 1);
        ELSE
            v_avg_so_far := 0;
        END IF;
        
        -- Определение рекорда
        IF v_daily_tons > v_avg_so_far AND i > 1 THEN
            v_record_flag := ' | ★ РЕКОРД';
        ELSE
            v_record_flag := '';
        END IF;
        
        -- Обновление лучшего дня
        IF v_daily_tons > v_best_tons THEN
            v_best_tons := v_daily_tons;
            v_best_day := i;
        END IF;
        
        -- Вывод строки
        RAISE NOTICE 'День %02d: %10.1f т | Нарастающий: %10.1f т%', 
            i, v_daily_tons, v_running_total, v_record_flag;
        
        -- Накопление общего итога
        v_total_tons := v_total_tons + v_daily_tons;
    END LOOP;
    
    -- Финальная сводка
    RAISE NOTICE '';
    RAISE NOTICE '===== Итоги за 14 дней =====';
    RAISE NOTICE 'Общая добыча: % т', v_total_tons;
    RAISE NOTICE 'Средняя добыча в день: % т', ROUND(v_total_tons / 14, 1);
    RAISE NOTICE 'Лучший день: % (добыча: % т)', v_best_day, v_best_tons;
    RAISE NOTICE '================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- ТЕСТИРОВАНИЕ БЛОКОВ
-- ============================================================================

-- Тест 1: Проверка наличия данных за январь 2025
SELECT 
    'fact_production' AS table_name,
    COUNT(*) AS row_count,
    MIN(date_id) AS min_date,
    MAX(date_id) AS max_date
FROM fact_production
WHERE date_id BETWEEN 20250101 AND 20250131;

-- Тест 2: Проверка dim_mine
SELECT 
    COUNT(*) AS active_mines,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count
FROM dim_mine;

-- Тест 3: Проверка dim_equipment
SELECT 
    COUNT(*) AS active_equipment,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count
FROM dim_equipment;



-- ============================================================================
-- ЗАДАНИЕ 4. WHILE — мониторинг порога простоев (среднее)
-- ============================================================================

DO $$
DECLARE
    v_threshold NUMERIC := 500;  -- Порог в часах
    v_current_date_id INT := 20250101;
    v_end_date_id INT := 20250131;
    v_daily_downtime NUMERIC := 0;
    v_total_downtime NUMERIC := 0;
    v_day_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===== Мониторинг порога простоев =====';
    RAISE NOTICE 'Порог: % часов', v_threshold;
    RAISE NOTICE '';
    
    WHILE v_current_date_id <= v_end_date_id LOOP
        -- Получение простоев за день (в часах)
        SELECT COALESCE(SUM(duration_min) / 60.0, 0) INTO v_daily_downtime
        FROM fact_equipment_downtime
        WHERE date_id = v_current_date_id;
        
        -- Накопление итога
        v_total_downtime := v_total_downtime + v_daily_downtime;
        v_day_count := v_day_count + 1;
        
        -- Проверка порога
        IF v_total_downtime >= v_threshold THEN
            RAISE NOTICE ' ПОРОГ ДОСТИГНУТ!';
            RAISE NOTICE 'Дата: %', TO_DATE(v_current_date_id::TEXT, 'YYYYMMDD');
            RAISE NOTICE 'Суммарные простои: %.2f часов', v_total_downtime;
            RAISE NOTICE 'Дней прошло: %', v_day_count;
            EXIT;  -- Выход из цикла
        END IF;
        
        CONTINUE;  -- Переход к следующему дню
    END LOOP;
    
    -- Если порог не достигнут
    IF v_total_downtime < v_threshold THEN
        RAISE NOTICE '';
        RAISE NOTICE ' Порог НЕ достигнут за январь 2025';
        RAISE NOTICE 'Суммарные простои: %.2f часов (из % требуемых)', 
            v_total_downtime, v_threshold;
    END IF;
    
    RAISE NOTICE '====================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- ЗАДАНИЕ 5. CASE и FOREACH — анализ датчиков (среднее)
-- ============================================================================

DO $$
DECLARE
    v_sensor_types INT[];
    v_type_id INT;
    v_sensor_count INT;
    v_telemetry_count BIGINT;
    v_avg_per_sensor NUMERIC;
    v_status VARCHAR;
    v_type_name VARCHAR;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===== Анализ датчиков по типам =====';
    RAISE NOTICE '';
    
    -- Получение массива уникальных sensor_type_id
    SELECT ARRAY_AGG(DISTINCT sensor_type_id) INTO v_sensor_types
    FROM dim_sensor;
    
    -- Перебор типов через FOREACH
    FOREACH v_type_id IN ARRAY v_sensor_types LOOP
        -- Название типа
        SELECT type_name INTO v_type_name
        FROM dim_sensor_type
        WHERE sensor_type_id = v_type_id;
        
        -- Количество датчиков этого типа
        SELECT COUNT(*) INTO v_sensor_count
        FROM dim_sensor
        WHERE sensor_type_id = v_type_id
          AND status = 'active';
        
        -- Количество показаний за январь 2025
        SELECT COALESCE(COUNT(*), 0) INTO v_telemetry_count
        FROM fact_equipment_telemetry t
        JOIN dim_sensor s ON t.sensor_id = s.sensor_id
        WHERE s.sensor_type_id = v_type_id
          AND t.date_id BETWEEN 20250101 AND 20250131;
        
        -- Среднее на датчик
        IF v_sensor_count > 0 THEN
            v_avg_per_sensor := v_telemetry_count::NUMERIC / v_sensor_count;
        ELSE
            v_avg_per_sensor := 0;
        END IF;
        
        -- Определение статуса через CASE
        CASE
            WHEN v_avg_per_sensor > 1000 THEN
                v_status := 'Активно работает';
            WHEN v_avg_per_sensor BETWEEN 100 AND 1000 THEN
                v_status := 'Нормальная работа';
            WHEN v_avg_per_sensor BETWEEN 1 AND 99 THEN
                v_status := 'Редкие показания';
            ELSE
                v_status := 'Нет данных';
        END CASE;
        
        -- Вывод строки
        RAISE NOTICE 'Тип: %-20s | Датчиков: %3d | Показаний: %6d | Статус: %s',
            v_type_name, v_sensor_count, v_telemetry_count, v_status;
    END LOOP;
    
    RAISE NOTICE '';
    RAISE NOTICE '====================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- ЗАДАНИЕ 6. Курсор — пакетное формирование отчёта по сменам (среднее)
-- ============================================================================

-- Создание таблицы отчётов
CREATE TABLE IF NOT EXISTS report_shift_summary (
    report_date    DATE,
    shift_name     VARCHAR(50),
    mine_name      VARCHAR(100),
    total_tons     NUMERIC(12,2),
    equipment_used INT,
    efficiency     NUMERIC(5,1),
    created_at     TIMESTAMP DEFAULT NOW()
);

TRUNCATE TABLE report_shift_summary;

DO $$
DECLARE
    cur_dates CURSOR FOR
        SELECT DISTINCT d.date_id, d.full_date
        FROM dim_date d
        WHERE d.date_id BETWEEN 20250101 AND 20250115
        ORDER BY d.date_id;
    
    v_date_id INT;
    v_full_date DATE;
    v_rows_inserted INT;
    v_total_rows INT := 0;
    v_processed_days INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '===== Формирование отчёта по сменам =====';
    RAISE NOTICE '';
    
    OPEN cur_dates;
    
    LOOP
        FETCH cur_dates INTO v_date_id, v_full_date;
        EXIT WHEN NOT FOUND;
        
        v_processed_days := v_processed_days + 1;
        
        -- Вставка агрегированных данных за день
        INSERT INTO report_shift_summary (
            report_date,
            shift_name,
            mine_name,
            total_tons,
            equipment_used,
            efficiency
        )
        SELECT
            v_full_date,
            s.shift_name,
            m.mine_name,
            COALESCE(SUM(fp.tons_mined), 0),
            COUNT(DISTINCT fp.equipment_id),
            ROUND(
                COALESCE(SUM(fp.operating_hours), 0) / 
                NULLIF(COUNT(DISTINCT fp.equipment_id) * 8, 0) * 100,
                1
            )
        FROM fact_production fp
        JOIN dim_shift s ON fp.shift_id = s.shift_id
        JOIN dim_mine m ON fp.mine_id = m.mine_id
        WHERE fp.date_id = v_date_id
        GROUP BY s.shift_name, m.mine_name;
        
        -- Получение количества вставленных строк
        GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
        v_total_rows := v_total_rows + v_rows_inserted;
        
        RAISE NOTICE 'День %: вставлено % строк', v_full_date, v_rows_inserted;
    END LOOP;
    
    CLOSE cur_dates;
    
    RAISE NOTICE '';
    RAISE NOTICE '===== Итого =====';
    RAISE NOTICE 'Обработано дней: %', v_processed_days;
    RAISE NOTICE 'Всего строк вставлено: %', v_total_rows;
    RAISE NOTICE '==================';
    RAISE NOTICE '';
END $$;

-- Проверка результата
SELECT * FROM report_shift_summary
ORDER BY report_date, shift_name, mine_name;

-- ============================================================================
-- ЗАДАНИЕ 7. RETURN NEXT — функция генерации отчёта (сложное)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_quality_trend(
    p_year INT,
    p_mine_id INT DEFAULT NULL
)
RETURNS TABLE (
    month_num      INT,
    month_name     VARCHAR,
    samples_count  BIGINT,
    avg_fe         NUMERIC,
    min_fe         NUMERIC,
    max_fe         NUMERIC,
    running_avg_fe NUMERIC,
    trend          VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_month INT;
    v_prev_avg NUMERIC := 0;
    v_current_avg NUMERIC := 0;
    v_running_sum NUMERIC := 0;
    v_running_count BIGINT := 0;
BEGIN
    -- Цикл по месяцам 1..12
    FOR v_month IN 1..12 LOOP
        -- Расчёт статистики за месяц
        SELECT
            COALESCE(COUNT(*), 0),
            COALESCE(AVG(fe_content), 0),
            COALESCE(MIN(fe_content), 0),
            COALESCE(MAX(fe_content), 0)
        INTO
            samples_count,
            avg_fe,
            min_fe,
            max_fe
        FROM fact_ore_quality oq
        JOIN dim_date d ON oq.date_id = d.date_id
        WHERE EXTRACT(YEAR FROM d.full_date) = p_year
          AND EXTRACT(MONTH FROM d.full_date) = v_month
          AND (p_mine_id IS NULL OR oq.mine_id = p_mine_id);
        
        -- Нарастающее среднее
        IF samples_count > 0 THEN
            v_running_sum := v_running_sum + (avg_fe * samples_count);
            v_running_count := v_running_count + samples_count;
            v_current_avg := avg_fe;
        END IF;
        
        IF v_running_count > 0 THEN
            running_avg_fe := ROUND(v_running_sum / v_running_count, 2);
        ELSE
            running_avg_fe := 0;
        END IF;
        
        -- Определение тренда
        IF v_month = 1 OR samples_count = 0 THEN
            trend := 'Нет данных';
        ELSIF v_current_avg > v_prev_avg + 0.5 THEN
            trend := 'Улучшение';
        ELSIF v_current_avg < v_prev_avg - 0.5 THEN
            trend := 'Ухудшение';
        ELSE
            trend := 'Стабильно';
        END IF;
        
        -- Название месяца
        month_name := TO_CHAR(TO_DATE(v_month::TEXT, 'MM'), 'Month');
        month_num := v_month;
        
        -- Возврат строки
        RETURN NEXT;
        
        -- Сохранение для сравнения
        IF samples_count > 0 THEN
            v_prev_avg := avg_fe;
        END IF;
    END LOOP;
    
    RETURN;
END;
$$;

-- Тестирование функции
SELECT * FROM get_quality_trend(2024);
SELECT * FROM get_quality_trend(2024, 1);

-- ============================================================================
-- ТЕСТИРОВАНИЕ ВСЕХ БЛОКОВ
-- ============================================================================

-- Тест 4: Проверка данных о простоях
SELECT
    'fact_equipment_downtime' AS table_name,
    COUNT(*) AS total_downtimes,
    SUM(duration_min) / 60.0 AS total_hours,
    MIN(date_id) AS min_date,
    MAX(date_id) AS max_date
FROM fact_equipment_downtime
WHERE date_id BETWEEN 20250101 AND 20250131;

-- Тест 5: Проверка датчиков
SELECT
    st.type_name,
    COUNT(s.sensor_id) AS sensor_count,
    COUNT(t.telemetry_id) AS telemetry_count
FROM dim_sensor_type st
LEFT JOIN dim_sensor s ON st.sensor_type_id = s.sensor_type_id
LEFT JOIN fact_equipment_telemetry t ON s.sensor_id = t.sensor_id
    AND t.date_id BETWEEN 20250101 AND 20250131
GROUP BY st.type_name;

-- Тест 6: Проверка отчёта
SELECT
    report_date,
    shift_name,
    mine_name,
    total_tons,
    equipment_used,
    efficiency,
    created_at
FROM report_shift_summary
ORDER BY report_date, shift_name, mine_name
LIMIT 20;

-- Тест 7: Проверка функции
SELECT
    month_num,
    month_name,
    samples_count,
    avg_fe,
    running_avg_fe,
    trend
FROM get_quality_trend(2024)
WHERE samples_count > 0;


