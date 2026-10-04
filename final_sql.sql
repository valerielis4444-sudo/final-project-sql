-- Финальный проект. Блок SQL
-- Таблицы: customer_info (информация о клиентах), transactions_info (транзакции)
-- Период анализа: с 01.06.2015 по 01.06.2016
-- Операция = один чек (Id_check), сумма операции = сумма Sum_payment по чеку

USE final_project;

SET SQL_SAFE_UPDATES = 0;
UPDATE transactions_info
SET date_new = STR_TO_DATE(date_new, '%d/%m/%Y')
WHERE date_new LIKE '__/__/____';
ALTER TABLE transactions_info MODIFY date_new DATE;
SET SQL_SAFE_UPDATES = 1;

-- Проверка загрузки данных
SELECT COUNT(*) AS customers FROM customer_info;
SELECT COUNT(*) AS transactions FROM transactions_info;


-- 1. Клиенты с непрерывной историей за год (операции в каждом месяце периода),
--    средний чек за период, средняя сумма покупок за месяц, количество операций
WITH period_months AS (
    SELECT COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS n_months
    FROM transactions_info
    WHERE DATE(date_new) BETWEEN '2015-06-01' AND '2016-06-01'
),
client_stats AS (
    SELECT
        ID_client,
        COUNT(DISTINCT DATE_FORMAT(date_new, '%Y-%m')) AS active_months,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT Id_check) AS operations
    FROM transactions_info
    WHERE DATE(date_new) BETWEEN '2015-06-01' AND '2016-06-01'
    GROUP BY ID_client
)
SELECT
    cs.ID_client,
    cs.operations,
    ROUND(cs.total_sum / cs.operations, 2) AS avg_check,
    ROUND(cs.total_sum / pm.n_months, 2) AS avg_month_sum,
    ROUND(cs.total_sum, 2) AS total_sum
FROM client_stats cs
CROSS JOIN period_months pm
WHERE cs.active_months = pm.n_months
ORDER BY cs.ID_client;


-- 2. Информация в разрезе месяцев:
--    средний чек, количество операций, среднее количество операций на клиента,
--    количество клиентов, доля месяца в операциях и в сумме за весь период
WITH monthly AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m') AS period_month,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT Id_check) AS operations,
        COUNT(DISTINCT ID_client) AS clients
    FROM transactions_info
    WHERE DATE(date_new) BETWEEN '2015-06-01' AND '2016-06-01'
    GROUP BY period_month
)
SELECT
    period_month,
    ROUND(total_sum / operations, 2) AS avg_check,
    operations,
    ROUND(operations / clients, 2) AS avg_operations_per_client,
    clients,
    ROUND(operations * 100 / SUM(operations) OVER (), 2) AS operations_share_pct,
    ROUND(total_sum * 100 / SUM(total_sum) OVER (), 2) AS sum_share_pct
FROM monthly
ORDER BY period_month;


-- 2.1. Средние значения по месяцам за весь период
WITH monthly AS (
    SELECT
        DATE_FORMAT(date_new, '%Y-%m') AS period_month,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT Id_check) AS operations,
        COUNT(DISTINCT ID_client) AS clients
    FROM transactions_info
    WHERE DATE(date_new) BETWEEN '2015-06-01' AND '2016-06-01'
    GROUP BY period_month
)
SELECT
    ROUND(AVG(total_sum / operations), 2) AS avg_check_per_month,
    ROUND(AVG(operations), 2) AS avg_operations_per_month,
    ROUND(AVG(clients), 2) AS avg_clients_per_month
FROM monthly;


-- 3. Соотношение M/F/NA в каждом месяце и их доля затрат
WITH gender_monthly AS (
    SELECT
        DATE_FORMAT(t.date_new, '%Y-%m') AS period_month,
        COALESCE(NULLIF(TRIM(c.Gender), ''), 'NA') AS gender,
        COUNT(DISTINCT t.ID_client) AS clients,
        SUM(t.Sum_payment) AS total_sum
    FROM transactions_info t
    JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE DATE(t.date_new) BETWEEN '2015-06-01' AND '2016-06-01'
    GROUP BY period_month, gender
)
SELECT
    period_month,
    gender,
    clients,
    ROUND(clients * 100 / SUM(clients) OVER (PARTITION BY period_month), 2) AS clients_pct,
    ROUND(total_sum, 2) AS total_sum,
    ROUND(total_sum * 100 / SUM(total_sum) OVER (PARTITION BY period_month), 2) AS sum_share_pct
FROM gender_monthly
ORDER BY period_month, gender;


-- 4. Возрастные группы с шагом 10 лет и клиенты без возраста (NA)
-- 4.1. Сумма и количество операций за весь период
WITH age_data AS (
    SELECT
        CASE
            WHEN c.Age IS NULL OR TRIM(c.Age) = '' THEN 'NA'
            ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
        END AS age_group,
        t.Id_check,
        t.Sum_payment
    FROM transactions_info t
    JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE DATE(t.date_new) BETWEEN '2015-06-01' AND '2016-06-01'
),
age_total AS (
    SELECT
        age_group,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT Id_check) AS operations
    FROM age_data
    GROUP BY age_group
)
SELECT
    age_group,
    ROUND(total_sum, 2) AS total_sum,
    operations,
    ROUND(total_sum * 100 / SUM(total_sum) OVER (), 2) AS sum_share_pct,
    ROUND(operations * 100 / SUM(operations) OVER (), 2) AS operations_share_pct
FROM age_total
ORDER BY age_group;


-- 4.2. Поквартально: средние показатели и доли (%) возрастных групп внутри квартала
WITH age_data AS (
    SELECT
        CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS quarter_name,
        CASE
            WHEN c.Age IS NULL OR TRIM(c.Age) = '' THEN 'NA'
            ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
        END AS age_group,
        t.ID_client,
        t.Id_check,
        t.Sum_payment
    FROM transactions_info t
    JOIN customer_info c ON t.ID_client = c.Id_client
    WHERE DATE(t.date_new) BETWEEN '2015-06-01' AND '2016-06-01'
),
age_quarter AS (
    SELECT
        quarter_name,
        age_group,
        SUM(Sum_payment) AS total_sum,
        COUNT(DISTINCT Id_check) AS operations,
        COUNT(DISTINCT ID_client) AS clients
    FROM age_data
    GROUP BY quarter_name, age_group
)
SELECT
    quarter_name,
    age_group,
    ROUND(total_sum, 2) AS total_sum,
    operations,
    clients,
    ROUND(total_sum / operations, 2) AS avg_check,
    ROUND(total_sum / clients, 2) AS avg_sum_per_client,
    ROUND(operations / clients, 2) AS avg_operations_per_client,
    ROUND(total_sum * 100 / SUM(total_sum) OVER (PARTITION BY quarter_name), 2) AS sum_share_pct,
    ROUND(operations * 100 / SUM(operations) OVER (PARTITION BY quarter_name), 2) AS operations_share_pct,
    ROUND(clients * 100 / SUM(clients) OVER (PARTITION BY quarter_name), 2) AS clients_share_pct
FROM age_quarter
ORDER BY quarter_name, age_group;
