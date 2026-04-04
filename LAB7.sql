

-- Задание 1. Анализ существующих индексов
-- Пункт 1: Список всех индексов для факт-таблиц
SELECT
    tablename,
    indexname,
    indexdef
FROM
    pg_indexes
WHERE
    tablename IN (
        'fact_production',
        'fact_equipment_telemetry',
        'fact_equipment_downtime',
        'fact_ore_quality'
    )
ORDER BY
    tablename,
    indexname;

-- Пункт 2: Размер и статистика использования индексов для fact_production
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS times_used,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM
    pg_stat_user_indexes
WHERE
    relname = 'fact_production'
ORDER BY
    pg_relation_size(indexrelid) DESC;

-- Пункт 3: Сравнение размера таблиц и индексов
SELECT
    relname AS table_name,
    pg_size_pretty(pg_table_size(relid)) AS table_size,
    pg_size_pretty(pg_indexes_size(relid)) AS indexes_size,
    pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
    ROUND(
        pg_indexes_size(relid)::numeric /
        NULLIF(pg_table_size(relid), 0) * 100, 1
    ) AS index_pct
FROM
    pg_stat_user_tables
WHERE
    relname IN (
        'fact_production',
        'fact_equipment_telemetry',
        'fact_equipment_downtime',
        'fact_ore_quality'
    )
ORDER BY
    pg_total_relation_size(relid) DESC;



-- Задание 2. Анализ плана выполнения
-- Пункт 1: EXPLAIN (оценочный план, запрос НЕ выполняется)
EXPLAIN
SELECT
    e.equipment_name,
    SUM(p.tons_mined) AS total_tons,
    SUM(p.fuel_consumed_l) AS total_fuel,
    SUM(p.operating_hours) AS total_hours
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
WHERE
    p.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_tons DESC;

-- Пункт 2: EXPLAIN ANALYZE (реальное время выполнения)
EXPLAIN ANALYZE
SELECT
    e.equipment_name,
    SUM(p.tons_mined) AS total_tons,
    SUM(p.fuel_consumed_l) AS total_fuel,
    SUM(p.operating_hours) AS total_hours
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
WHERE
    p.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_tons DESC;

-- Пункт 3: EXPLAIN (ANALYZE, BUFFERS) (анализ ввода/вывода)
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    e.equipment_name,
    SUM(p.tons_mined) AS total_tons,
    SUM(p.fuel_consumed_l) AS total_fuel,
    SUM(p.operating_hours) AS total_hours
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
WHERE
    p.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_tons DESC;


-- ============================================================================
-- Анализ результатов Задания 2 :
--
-- 1. Какой тип сканирования используется для fact_production?
--    Ответ: Index Scan (idx_prod_date_low_ff)
--
-- 2. Какой тип соединения (Join) выбран планировщиком?
--    Ответ: Hash Join
--
-- 3. Где тратится больше всего времени?
--    Ответ: Hash Join (0.240 мс из 0.551 мс общего времени)
--
-- 4. Сколько страниц (buffers) прочитано?
--    Ответ: 11 страниц (Buffers: shared hit=11, shared read=0)
--
-- 5. Узкое место запроса:
--    Ответ: Сканирование fact_production с фильтрацией по date_id
-- ============================================================================




-- Задание 3. Оптимизация поиска по расходу топлива
-- Пункт 1: План запроса до создания индекса
EXPLAIN ANALYZE
SELECT
    p.date_id,
    e.equipment_name,
    o.last_name,
    p.fuel_consumed_l
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
JOIN
    dim_operator AS o ON p.operator_id = o.operator_id
WHERE
    p.fuel_consumed_l > 80
ORDER BY
    p.fuel_consumed_l DESC;

-- Пункт 2: Оценка избирательности (selectivity) условия
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE fuel_consumed_l > 80) AS matching_rows,
    ROUND(
        COUNT(*) FILTER (WHERE fuel_consumed_l > 80)::numeric /
        COUNT(*) * 100, 2
    ) AS selectivity_pct
FROM
    fact_production;

-- Пункт 3: Создание B-tree индекса на столбец fuel_consumed_l
CREATE INDEX IF NOT EXISTS idx_fact_production_fuel_consumed
ON fact_production (fuel_consumed_l);

-- Пункт 4: Обновление статистики таблицы
ANALYZE fact_production;

-- Пункт 5: План запроса после создания индекса
EXPLAIN ANALYZE
SELECT
    p.date_id,
    e.equipment_name,
    o.last_name,
    p.fuel_consumed_l
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
JOIN
    dim_operator AS o ON p.operator_id = o.operator_id
WHERE
    p.fuel_consumed_l > 80
ORDER BY
    p.fuel_consumed_l DESC;

-- ============================================================================
-- Анализ результатов Задания 3 (заполните после выполнения):

-- Вопрос: Если избирательность > 20-30%, почему PostgreSQL может оставить Seq Scan?
-- Ответ: При высокой избирательности (большая доля строк удовлетворяет условию)
-- планировщик считает, что случайные чтения по индексу будут дороже,
-- чем последовательное сканирование всей таблицы. Индекс выгоден только
-- при низкой избирательности (< 5-10% строк).
-- ============================================================================







-- Задание 4. Частичный индекс для аварийной телеметрии
-- Пункт 1: План запроса до создания индекса
EXPLAIN ANALYZE
SELECT
    t.telemetry_id,
    t.date_id,
    t.equipment_id,
    t.sensor_id,
    t.sensor_value
FROM
    fact_equipment_telemetry AS t
WHERE
    t.date_id = 20240315
    AND t.is_alarm = TRUE;

-- Пункт 2: Создание частичного индекса (partial index)
CREATE INDEX IF NOT EXISTS idx_telemetry_alarm_partial
ON fact_equipment_telemetry (date_id)
WHERE is_alarm = TRUE;

-- Пункт 3: Создание полного индекса для сравнения
CREATE INDEX IF NOT EXISTS idx_telemetry_alarm_full
ON fact_equipment_telemetry (date_id, is_alarm);

-- Пункт 4: Сравнение размеров индексов
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM
    pg_stat_user_indexes
WHERE
    indexrelname IN ('idx_telemetry_alarm_partial', 'idx_telemetry_alarm_full')
ORDER BY
    pg_relation_size(indexrelid);

-- Пункт 5: План запроса после создания индексов
EXPLAIN ANALYZE
SELECT
    t.telemetry_id,
    t.date_id,
    t.equipment_id,
    t.sensor_id,
    t.sensor_value
FROM
    fact_equipment_telemetry AS t
WHERE
    t.date_id = 20240315
    AND t.is_alarm = TRUE;

-- ============================================================================
-- Анализ результатов Задания 4:

-- Преимущества частичного индекса:
-- 1. Занимает меньше места (только ~2% строк с is_alarm = TRUE)
-- 2. Быстрее обновляется при INSERT (только для аварийных записей)
-- 3. Лучше помещается в буферный кеш (shared buffers)
-- 4. Планировщик выбирает его автоматически для запросов с is_alarm = TRUE
-- ============================================================================

-- Задание 5. Композитный индекс для отчета по добыче
-- Пункт 1: План запроса до создания индексов
EXPLAIN ANALYZE
SELECT
    date_id,
    tons_mined,
    tons_transported,
    trips_count,
    operating_hours
FROM
    fact_production
WHERE
    equipment_id = 5
    AND date_id BETWEEN 20240301 AND 20240331;

-- Пункт 2: Создание композитного индекса (equipment_id, date_id)
CREATE INDEX IF NOT EXISTS idx_prod_equip_date
ON fact_production (equipment_id, date_id);

-- Пункт 3: Создание композитного индекса с обратным порядком (date_id, equipment_id)
CREATE INDEX IF NOT EXISTS idx_prod_date_equip
ON fact_production (date_id, equipment_id);

-- Пункт 4: Обновление статистики
ANALYZE fact_production;

-- Пункт 5: Выполнение запроса из п.1 (определение выбранного индекса)
EXPLAIN ANALYZE
SELECT
    date_id,
    tons_mined,
    tons_transported,
    trips_count,
    operating_hours
FROM
    fact_production
WHERE
    equipment_id = 5
    AND date_id BETWEEN 20240301 AND 20240331;

-- Пункт 6: Проверка использования индекса для запроса только по date_id
EXPLAIN ANALYZE
SELECT
    *
FROM
    fact_production
WHERE
    date_id = 20240315;

-- ============================================================================
-- Анализ результатов Задания 5:

-- Вопрос 1: Какой индекс выбран для запроса с equipment_id = 5 AND date_id BETWEEN?
-- Ответ: idx_prod_equip_date (equipment_id, date_id)
-- Причина: Сначала фильтр по равенству (equipment_id = 5), затем диапазон (date_id)

-- Вопрос 2: Будет ли использован индекс (equipment_id, date_id) для запроса только по date_id?
-- Ответ: НЕТ (нарушение правила левого префикса)
-- Причина: date_id не является первым столбцом в индексе

-- Правило левого префикса:
-- Индекс (A, B) эффективен для:
--   WHERE A = ?                    -- ДА (левый префикс)
--   WHERE A = ? AND B = ?          -- ДА
--   WHERE A = ? AND B BETWEEN ?    -- ДА (сначала равенство, потом диапазон)
--   WHERE B = ?                    -- НЕТ (B не левый префикс)
--   WHERE B BETWEEN ?              -- НЕТ

-- ============================================================================





-- Задание 6. Индекс по выражению для поиска операторов
-- Пункт 1: План запроса до создания индекса
EXPLAIN ANALYZE
SELECT
    operator_id,
    last_name,
    first_name,
    middle_name,
    position,
    qualification
FROM
    dim_operator
WHERE
    LOWER(last_name) = 'петров';

-- Пункт 2: Создание индекса по выражению LOWER(last_name)
CREATE INDEX IF NOT EXISTS idx_dim_operator_last_name_lower
ON dim_operator (LOWER(last_name));

-- Пункт 3: Обновление статистики таблицы
ANALYZE dim_operator;

-- Пункт 4: План запроса после создания индекса
EXPLAIN ANALYZE
SELECT
    operator_id,
    last_name,
    first_name,
    middle_name,
    position,
    qualification
FROM
    dim_operator
WHERE
    LOWER(last_name) = 'петров';

-- Пункт 5: Проверка -- запрос без LOWER (индекс НЕ будет использован)
EXPLAIN ANALYZE
SELECT
    operator_id,
    last_name,
    first_name
FROM
    dim_operator
WHERE
    last_name = 'Петров';

-- Пункт 6: Проверка -- запрос с UPPER (индекс НЕ будет использован)
EXPLAIN ANALYZE
SELECT
    operator_id,
    last_name,
    first_name
FROM
    dim_operator
WHERE
    UPPER(last_name) = 'ПЕТРОВ';

-- ============================================================================
-- Анализ результатов Задания 6:
--
-- Вопрос 1: Будет ли индекс использован для запроса без LOWER?
-- Ответ: НЕТ
-- Причина: Индекс создан по выражению LOWER(last_name), а запрос использует
-- просто last_name. Выражения должны точно совпадать.
--
-- Вопрос 2: Будет ли индекс использован для запроса с UPPER?
-- Ответ: НЕТ
-- Причина: UPPER(last_name) != LOWER(last_name). Индексы по выражению работают
-- только при точном совпадении выражения в запросе и в определении индекса.

-- ============================================================================

-- Задание 7. Покрывающий индекс для дашборда
-- Пункт 1: План запроса до создания индекса
EXPLAIN ANALYZE
SELECT
    date_id,
    equipment_id,
    tons_mined
FROM
    fact_production
WHERE
    date_id = 20240315;

-- Пункт 2: Создание покрывающего индекса с INCLUDE
CREATE INDEX IF NOT EXISTS idx_prod_date_cover
ON fact_production (date_id)
INCLUDE (equipment_id, tons_mined);

-- Пункт 3: Обновление карты видимости (Visibility Map) для Index Only Scan
VACUUM fact_production;

-- Пункт 4: Обновление статистики таблицы
ANALYZE fact_production;

-- Пункт 5: План запроса после создания покрывающего индекса
EXPLAIN ANALYZE
SELECT
    date_id,
    equipment_id,
    tons_mined
FROM
    fact_production
WHERE
    date_id = 20240315;

-- Пункт 6: Проверка -- добавление столбца вне INCLUDE (Index Only Scan пропадёт)
EXPLAIN ANALYZE
SELECT
    date_id,
    equipment_id,
    tons_mined,
    fuel_consumed_l
FROM
    fact_production
WHERE
    date_id = 20240315;

-- Пункт 7: Создание расширенного покрывающего индекса
CREATE INDEX IF NOT EXISTS idx_prod_date_cover_extended
ON fact_production (date_id)
INCLUDE (equipment_id, tons_mined, fuel_consumed_l);

-- Пункт 8: Обновление карты видимости и статистики
VACUUM fact_production;
ANALYZE fact_production;

-- Пункт 9: План запроса с расширенным покрывающим индексом
EXPLAIN ANALYZE
SELECT
    date_id,
    equipment_id,
    tons_mined,
    fuel_consumed_l
FROM
    fact_production
WHERE
    date_id = 20240315;

-- ============================================================================
-- Анализ результатов Задания 7:

-- Вопрос 1: Почему нужен VACUUM для Index Only Scan?
-- Ответ: PostgreSQL использует Visibility Map (VM) для определения видимости
--строк без обращения к таблице. VACUUM обновляет VM. Без VACUUM
--планировщик может выбрать Index Scan вместо Index Only Scan.


-- Вопрос 2: Что происходит при добавлении столбца вне INCLUDE?
-- Ответ: Index Only Scan превращается в Index Scan с обращением к таблице
--        (Heap Fetch), так как данных в индексе недостаточно.

-- ============================================================================







-- Задание 8. BRIN-индекс для телеметрии
-- Пункт 1: Проверка размера существующего B-tree индекса
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM
    pg_stat_user_indexes
WHERE
    indexrelname = 'idx_fact_telemetry_date';

-- Пункт 2: Создание BRIN-индекса на столбец date_id
CREATE INDEX IF NOT EXISTS idx_telemetry_date_brin
ON fact_equipment_telemetry USING brin (date_id)
WITH (pages_per_range = 128);

-- Пункт 3: Обновление статистики таблицы
ANALYZE fact_equipment_telemetry;

-- Пункт 4: Сравнение размеров B-tree и BRIN индексов
SELECT
    indexrelname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM
    pg_stat_user_indexes
WHERE
    indexrelname IN ('idx_fact_telemetry_date', 'idx_telemetry_date_brin')
ORDER BY
    pg_relation_size(indexrelid) DESC;

-- Пункт 5: Тест производительности с B-tree (отключаем Bitmap Scan)
SET enable_bitmapscan = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    *
FROM
    fact_equipment_telemetry
WHERE
    date_id BETWEEN 20240301 AND 20240331;

RESET enable_bitmapscan;

-- Пункт 6: Тест производительности с BRIN (отключаем Index Scan)
SET enable_indexscan = off;

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    *
FROM
    fact_equipment_telemetry
WHERE
    date_id BETWEEN 20240301 AND 20240331;

RESET enable_indexscan;

-- ============================================================================
-- Анализ результатов Задания 8:
-- Когда BRIN эффективен:
-- 1. Таблица очень большая (> 1 млн строк)
-- 2. Данные вставляются последовательно (физический порядок коррелирует с indexed столбцом)
-- 3. Запросы по диапазону значений (BETWEEN, >, <)
-- 4. Критичен размер индекса (экономия места)
-- 5. Допустимо небольшое замедление чтения
--
-- Когда B-tree лучше:
-- 1. Таблица небольшая или средняя
-- 2. Данные не отсортированы физически
-- 3. Запросы по точным значениям (=)
-- 4. Требуется максимальная скорость чтения
-- 5. Высокая избирательность запроса






-- Задание 9. Анализ влияния индексов на INSERT
-- Пункт 1: Подсчёт текущего количества индексов на fact_production
SELECT
    COUNT(*) AS index_count
FROM
    pg_indexes
WHERE
    tablename = 'fact_production';

-- Пункт 2: Замер времени INSERT с текущими индексами
EXPLAIN ANALYZE
INSERT INTO fact_production (
    date_id,
    shift_id,
    mine_id,
    shaft_id,
    equipment_id,
    operator_id,
    location_id,
    ore_grade_id,
    tons_mined,
    tons_transported,
    trips_count,
    distance_km,
    fuel_consumed_l,
    operating_hours
) VALUES (
    20240401,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    120.50,
    115.00,
    8,
    12.5,
    45.2,
    7.5
);

-- Пункт 3: Создание 3 дополнительных индексов для теста
CREATE INDEX IF NOT EXISTS idx_test_1
ON fact_production (tons_mined);

CREATE INDEX IF NOT EXISTS idx_test_2
ON fact_production (fuel_consumed_l, operating_hours);

CREATE INDEX IF NOT EXISTS idx_test_3
ON fact_production (date_id, shift_id, mine_id);

-- Пункт 4: Подсчёт нового количества индексов
SELECT
    COUNT(*) AS index_count
FROM
    pg_indexes
WHERE
    tablename = 'fact_production';

-- Пункт 5: Замер времени INSERT после создания индексов
EXPLAIN ANALYZE
INSERT INTO fact_production (
    date_id,
    shift_id,
    mine_id,
    shaft_id,
    equipment_id,
    operator_id,
    location_id,
    ore_grade_id,
    tons_mined,
    tons_transported,
    trips_count,
    distance_km,
    fuel_consumed_l,
    operating_hours
) VALUES (
    20240401,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    130.00,
    125.00,
    9,
    14.0,
    50.1,
    8.0
);


-- Вопрос: Как организовать массовую загрузку 10 000+ строк для минимизации времени?
--
-- Ответ -- Стратегия массовой загрузки:
--
-- 1. Временное удаление индексов (для очень больших загрузок):

-- 2. Использование COPY вместо INSERT:

-- 3. Пакетная вставка (Batch INSERT):

-- 4. Отключение триггеров и ограничений (если возможно):

-- 5. Увеличение maintenance_work_mem для ускорения создания индексов:

-- 6. Использование временной таблицы:






-- Задание 10. Комплексная оптимизация: кейс «Руда+»
-- ============================================================================
-- ЧАСТЬ 1: Фиксация планов выполнения ДО создания индексов
-- ============================================================================

-- Запрос 1: Суммарная добыча по шахте за месяц
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    m.mine_name,
    SUM(p.tons_mined) AS total_tons,
    SUM(p.operating_hours) AS total_hours
FROM
    fact_production AS p
JOIN
    dim_mine AS m ON p.mine_id = m.mine_id
WHERE
    p.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    m.mine_name;

-- Запрос 2: Средний показатель качества руды по сорту за квартал
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    g.grade_name,
    AVG(q.fe_content) AS avg_fe,
    AVG(q.sio2_content) AS avg_sio2,
    COUNT(*) AS samples
FROM
    fact_ore_quality AS q
JOIN
    dim_ore_grade AS g ON q.ore_grade_id = g.ore_grade_id
WHERE
    q.date_id BETWEEN 20240101 AND 20240331
GROUP BY
    g.grade_name;

-- Запрос 3: Топ-5 оборудования по длительности внеплановых простоев
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    e.equipment_name,
    SUM(dt.duration_min) AS total_downtime_min,
    COUNT(*) AS incidents
FROM
    fact_equipment_downtime AS dt
JOIN
    dim_equipment AS e ON dt.equipment_id = e.equipment_id
WHERE
    dt.is_planned = FALSE
    AND dt.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_downtime_min DESC
LIMIT 5;

-- Запрос 4: Последние аварийные показания по оборудованию
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.date_id,
    t.time_id,
    t.sensor_id,
    t.sensor_value,
    t.quality_flag
FROM
    fact_equipment_telemetry AS t
WHERE
    t.equipment_id = 5
    AND t.is_alarm = TRUE
ORDER BY
    t.date_id DESC,
    t.time_id DESC
LIMIT 20;

-- Запрос 5: Добыча конкретного оператора за неделю
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    p.date_id,
    e.equipment_name,
    p.tons_mined,
    p.trips_count,
    p.operating_hours
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
WHERE
    p.operator_id = 3
    AND p.date_id BETWEEN 20240311 AND 20240317
ORDER BY
    p.date_id;

-- ============================================================================
-- ЧАСТЬ 2: Проверка существующих индексов (чтобы не создавать дубликаты)
-- ============================================================================

SELECT
    tablename,
    indexname,
    indexdef
FROM
    pg_indexes
WHERE
    tablename IN (
        'fact_production',
        'fact_ore_quality',
        'fact_equipment_downtime',
        'fact_equipment_telemetry'
    )
ORDER BY
    tablename,
    indexname;

-- ============================================================================
-- ЧАСТЬ 3: Создание оптимальных индексов (не более 7)
-- ============================================================================

-- Индекс 1: Для запроса 1 (добыча по шахте за месяц)

CREATE INDEX IF NOT EXISTS idx_prod_date_mine
ON fact_production (date_id, mine_id);

-- Индекс 2: Для запроса 2 (качество руды по сорту за квартал)

CREATE INDEX IF NOT EXISTS idx_quality_date
ON fact_ore_quality (date_id);

-- Индекс 3: Для запроса 3 (внеплановые простои)

CREATE INDEX IF NOT EXISTS idx_downtime_unplanned
ON fact_equipment_downtime (date_id, equipment_id)
WHERE is_planned = FALSE;

-- Индекс 4: Для запроса 4 (аварийная телеметрия)

CREATE INDEX IF NOT EXISTS idx_telemetry_equip_alarm
ON fact_equipment_telemetry (equipment_id, date_id DESC, time_id DESC)
WHERE is_alarm = TRUE;

-- Индекс 5: Для запроса 5 (добыча оператора за неделю)

CREATE INDEX IF NOT EXISTS idx_prod_operator_date
ON fact_production (operator_id, date_id);

-- Индекс 6: Покрывающий индекс для запроса 1 (опционально, для Index Only Scan)

CREATE INDEX IF NOT EXISTS idx_prod_date_mine_cover
ON fact_production (date_id, mine_id)
INCLUDE (tons_mined, operating_hours);

-- Индекс 7: Для запроса 3 -- покрывающий индекс с duration_min

CREATE INDEX IF NOT EXISTS idx_downtime_unplanned_cover
ON fact_equipment_downtime (date_id, equipment_id)
INCLUDE (duration_min)
WHERE is_planned = FALSE;

-- ============================================================================
-- ЧАСТЬ 4: Обновление статистики и карты видимости
-- ============================================================================

ANALYZE fact_production;
ANALYZE fact_ore_quality;
ANALYZE fact_equipment_downtime;
ANALYZE fact_equipment_telemetry;

VACUUM fact_production;
VACUUM fact_equipment_downtime;
VACUUM fact_equipment_telemetry;

-- ============================================================================
-- ЧАСТЬ 5: Фиксация планов выполнения ПОСЛЕ создания индексов
-- ============================================================================

-- Запрос 1: Суммарная добыча по шахте за месяц
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    m.mine_name,
    SUM(p.tons_mined) AS total_tons,
    SUM(p.operating_hours) AS total_hours
FROM
    fact_production AS p
JOIN
    dim_mine AS m ON p.mine_id = m.mine_id
WHERE
    p.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    m.mine_name;

-- Запрос 2: Средний показатель качества руды по сорту за квартал
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    g.grade_name,
    AVG(q.fe_content) AS avg_fe,
    AVG(q.sio2_content) AS avg_sio2,
    COUNT(*) AS samples
FROM
    fact_ore_quality AS q
JOIN
    dim_ore_grade AS g ON q.ore_grade_id = g.ore_grade_id
WHERE
    q.date_id BETWEEN 20240101 AND 20240331
GROUP BY
    g.grade_name;

-- Запрос 3: Топ-5 оборудования по длительности внеплановых простоев
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    e.equipment_name,
    SUM(dt.duration_min) AS total_downtime_min,
    COUNT(*) AS incidents
FROM
    fact_equipment_downtime AS dt
JOIN
    dim_equipment AS e ON dt.equipment_id = e.equipment_id
WHERE
    dt.is_planned = FALSE
    AND dt.date_id BETWEEN 20240301 AND 20240331
GROUP BY
    e.equipment_name
ORDER BY
    total_downtime_min DESC
LIMIT 5;

-- Запрос 4: Последние аварийные показания по оборудованию
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.date_id,
    t.time_id,
    t.sensor_id,
    t.sensor_value,
    t.quality_flag
FROM
    fact_equipment_telemetry AS t
WHERE
    t.equipment_id = 5
    AND t.is_alarm = TRUE
ORDER BY
    t.date_id DESC,
    t.time_id DESC
LIMIT 20;

-- Запрос 5: Добыча конкретного оператора за неделю
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    p.date_id,
    e.equipment_name,
    p.tons_mined,
    p.trips_count,
    p.operating_hours
FROM
    fact_production AS p
JOIN
    dim_equipment AS e ON p.equipment_id = e.equipment_id
WHERE
    p.operator_id = 3
    AND p.date_id BETWEEN 20240311 AND 20240317
ORDER BY
    p.date_id;


-- Запрос | Время до (мс)*| Время после (мс) | Созданный индекс               | Тип сканирования до | Тип сканирования после
-- -------|---------------|------------------|--------------------------------|---------------------|------------------------
-- 1      | 2.5           | 0.459            | idx_prod_date_mine_cover       | Seq Scan            | Index Only Scan
-- 2      | 5.0           | 1.481            | idx_quality_date               | Seq Scan            | Index Scan
-- 3      | 1.2           | 0.123            | idx_downtime_unplanned_cover   | Seq Scan            | Index Only Scan
-- 4      | 0.5           | 0.033            | idx_telemetry_equip_alarm      | Seq Scan            | Index Scan
-- 5      | 0.8           | 0.100            | idx_prod_operator_date**       | Seq Scan            | Index Scan



-- ============================================================
-- Удаление индексов, созданных в ходе лабораторной работы
-- ============================================================

-- Задание 3
DROP INDEX IF EXISTS idx_prod_fuel;

-- Задание 4
DROP INDEX IF EXISTS idx_telemetry_alarm_partial;
DROP INDEX IF EXISTS idx_telemetry_alarm_full;

-- Задание 5
DROP INDEX IF EXISTS idx_prod_equip_date;
DROP INDEX IF EXISTS idx_prod_date_equip;

-- Задание 6
DROP INDEX IF EXISTS idx_operator_lower_lastname;

-- Задание 7
DROP INDEX IF EXISTS idx_prod_date_cover;
DROP INDEX IF EXISTS idx_prod_date_cover_ext;

-- Задание 8
DROP INDEX IF EXISTS idx_telemetry_date_brin;

-- Задание 9
DROP INDEX IF EXISTS idx_test_1;
DROP INDEX IF EXISTS idx_test_2;
DROP INDEX IF EXISTS idx_test_3;

-- Задание 10
DROP INDEX IF EXISTS idx_prod_date_mine;
DROP INDEX IF EXISTS idx_quality_date;
DROP INDEX IF EXISTS idx_downtime_unplanned;
DROP INDEX IF EXISTS idx_telemetry_equip_alarm;
DROP INDEX IF EXISTS idx_prod_operator_date;

-- ============================================================
-- Удаление тестовых строк
-- ============================================================
DELETE FROM fact_production
WHERE date_id = 20240401;