-- ============================================================
--  Bahaghari Retail — Data Cleaning & Integration Script
--  Assessment: Part B, Items 10-13
--  Database:   SQLite  (compatible with VS Code + SQLTools)
--  Author:     [Student Name]
--  Date:       2025
-- ============================================================

-- ============================================================
-- STEP 1 — RAW TABLE IMPORTS
--   Import the three CSV files into SQLite via SQLTools
--   "New Connection → SQLite → browse to bahaghari.db"
--   then run the three .import commands in the SQLite CLI,
--   or use the VS Code CSV-import extension.
--   The three raw tables assumed to already exist:
--     transactions_raw, stores_raw, products_raw
-- ============================================================

-- ============================================================
-- STEP 2 — CLEAN: STORES
--   Issues fixed:
--     • TRIM leading/trailing whitespace in all text columns
--     • NULL region for S005 (Bahaghari Iloilo) → 'Visayas'
-- ============================================================
DROP TABLE IF EXISTS stores_clean;

CREATE TABLE stores_clean AS
SELECT
    TRIM(store_id)   AS store_id,
    TRIM(store_name) AS store_name,
    CASE
        WHEN TRIM(region) IS NULL OR TRIM(region) = ''
        THEN 'Visayas'           -- Iloilo City is in Western Visayas
        ELSE TRIM(region)
    END AS region
FROM stores_raw;

-- Verify
SELECT * FROM stores_clean;


-- ============================================================
-- STEP 3 — CLEAN: PRODUCTS
--   Issues fixed:
--     • TRIM all text columns
--     • Standardize category to Title Case
--       (SQLite has no native INITCAP; we use UPPER on first
--        char + LOWER on the rest via substr)
-- ============================================================
DROP TABLE IF EXISTS products_clean;

CREATE TABLE products_clean AS
SELECT
    TRIM(product_id)   AS product_id,
    TRIM(product_name) AS product_name,
    -- Normalize category: Title Case
    UPPER(SUBSTR(TRIM(category), 1, 1))
        || LOWER(SUBSTR(TRIM(category), 2))   AS category,
    unit_cost
FROM (
    -- Handle two-word categories like "Personal Care"
    -- by first collapsing all to lower, then applying INITCAP logic word-by-word.
    -- SQLite workaround: map the four known categories explicitly.
    SELECT
        product_id, product_name, unit_cost,
        CASE LOWER(TRIM(category))
            WHEN 'beverages'    THEN 'Beverages'
            WHEN 'snacks'       THEN 'Snacks'
            WHEN 'groceries'    THEN 'Groceries'
            WHEN 'personal care' THEN 'Personal Care'
            ELSE TRIM(category)
        END AS category
    FROM products_raw
);

-- Verify — should show exactly 4 distinct categories
SELECT DISTINCT category FROM products_clean ORDER BY category;


-- ============================================================
-- STEP 4 — CLEAN: TRANSACTIONS
--   Issues fixed:
--     • Remove 5 exact duplicate rows (keep first occurrence)
--     • TRIM all text columns
--     • Standardize date to ISO-8601 (YYYY-MM-DD)
--       Mixed formats: M/D/YYYY, YYYY-MM-DD, "Mon DD, YYYY"
--       → parsed via SQLite's date() + strftime()
--     • NULL units: derive from total_amount / unit_price
--     • NULL total_amount: derive from units × unit_price
--     • Cast units to INTEGER
--   Filter:
--     • Keep only 2025 (the single full year present)
-- ============================================================
DROP TABLE IF EXISTS transactions_clean;

CREATE TABLE transactions_clean AS
WITH deduped AS (
    -- Remove exact duplicates; keep the row with the smallest rowid
    SELECT *
    FROM transactions_raw
    WHERE rowid IN (
        SELECT MIN(rowid)
        FROM transactions_raw
        GROUP BY transaction_id, date, store_id, product_id, units, unit_price, total_amount
    )
),
trimmed AS (
    SELECT
        TRIM(transaction_id) AS transaction_id,
        TRIM(date)           AS date_raw,
        TRIM(store_id)       AS store_id,
        TRIM(product_id)     AS product_id,
        units,
        unit_price,
        total_amount
    FROM deduped
),
dated AS (
    SELECT *,
        -- Normalise the three mixed date formats to ISO-8601
        CASE
            -- Already ISO: YYYY-MM-DD
            WHEN date_raw LIKE '____-__-__'
            THEN date_raw
            -- M/D/YYYY  or  MM/DD/YYYY
            WHEN date_raw LIKE '%/%/%'
            THEN strftime('%Y-%m-%d',
                    printf('%04d-%02d-%02d',
                        CAST(SUBSTR(date_raw, INSTR(date_raw,'/')+
                             LENGTH(SUBSTR(date_raw,1,INSTR(date_raw,'/')-1))+1,
                             INSTR(SUBSTR(date_raw,INSTR(date_raw,'/')+1),'/') -
                             INSTR(date_raw,'/')-1+1) AS INTEGER),
                        CAST(SUBSTR(date_raw, 1, INSTR(date_raw,'/')-1) AS INTEGER),
                        CAST(SUBSTR(date_raw, INSTR(date_raw,'/')+1,
                             INSTR(SUBSTR(date_raw,INSTR(date_raw,'/')+1),'/')-1) AS INTEGER)
                    ))
            -- "Mon DD, YYYY"  e.g. "Feb 25, 2025"
            ELSE date(
                TRIM(SUBSTR(date_raw, INSTR(date_raw,',')+2)) || '-' ||
                CASE SUBSTR(date_raw,1,3)
                    WHEN 'Jan' THEN '01' WHEN 'Feb' THEN '02'
                    WHEN 'Mar' THEN '03' WHEN 'Apr' THEN '04'
                    WHEN 'May' THEN '05' WHEN 'Jun' THEN '06'
                    WHEN 'Jul' THEN '07' WHEN 'Aug' THEN '08'
                    WHEN 'Sep' THEN '09' WHEN 'Oct' THEN '10'
                    WHEN 'Nov' THEN '11' WHEN 'Dec' THEN '12'
                END || '-' ||
                printf('%02d', CAST(TRIM(SUBSTR(date_raw,5, INSTR(date_raw,',')-5)) AS INTEGER))
            )
        END AS date_iso
    FROM trimmed
),
units_fixed AS (
    SELECT
        transaction_id,
        date_iso                AS date,
        store_id,
        product_id,
        -- Impute null units from total / price; round to nearest integer
        CAST(
            COALESCE(units, ROUND(total_amount / unit_price, 0))
        AS INTEGER)             AS units,
        unit_price,
        -- Impute null total from units × price
        COALESCE(total_amount,
            COALESCE(units, ROUND(total_amount / unit_price, 0)) * unit_price
        )                       AS total_amount
    FROM dated
)
SELECT *
FROM units_fixed
WHERE strftime('%Y', date) = '2025'   -- filter: most recent full year
ORDER BY date, transaction_id;

-- QA checks
SELECT 'Row count'         AS check_name, COUNT(*) AS result FROM transactions_clean
UNION ALL
SELECT 'Null units',    COUNT(*) FROM transactions_clean WHERE units IS NULL
UNION ALL
SELECT 'Null total',    COUNT(*) FROM transactions_clean WHERE total_amount IS NULL
UNION ALL
SELECT 'Null dates',    COUNT(*) FROM transactions_clean WHERE date IS NULL
UNION ALL
SELECT 'Duplicates',    COUNT(*) - COUNT(DISTINCT transaction_id) FROM transactions_clean;


-- ============================================================
-- STEP 5 — JOIN: Analysis-Ready Dataset
--   Star schema denormalised into one flat table:
--     fact: transactions_clean
--     dim1: products_clean   (product_id)
--     dim2: stores_clean     (store_id)
-- ============================================================
DROP VIEW IF EXISTS v_analysis_ready;

CREATE VIEW v_analysis_ready AS
SELECT
    -- Transaction (fact)
    t.transaction_id,
    t.date,
    strftime('%Y', t.date)  AS year,
    strftime('%m', t.date)  AS month_num,
    CASE strftime('%m', t.date)
        WHEN '01' THEN 'January'  WHEN '02' THEN 'February'
        WHEN '03' THEN 'March'    WHEN '04' THEN 'April'
        WHEN '05' THEN 'May'      WHEN '06' THEN 'June'
        WHEN '07' THEN 'July'     WHEN '08' THEN 'August'
        WHEN '09' THEN 'September' WHEN '10' THEN 'October'
        WHEN '11' THEN 'November' WHEN '12' THEN 'December'
    END                     AS month_name,
    t.store_id,
    t.product_id,
    t.units,
    t.unit_price,
    t.total_amount,
    -- Product dimension
    p.product_name,
    p.category,
    p.unit_cost,
    ROUND(t.total_amount - (t.units * p.unit_cost), 2) AS gross_profit,
    -- Store dimension
    s.store_name,
    s.region
FROM transactions_clean  t
LEFT JOIN products_clean p ON t.product_id = p.product_id
LEFT JOIN stores_clean   s ON t.store_id   = s.store_id;

-- Preview
SELECT * FROM v_analysis_ready LIMIT 10;

-- Summary by region
SELECT
    region,
    COUNT(*)                        AS transactions,
    SUM(total_amount)               AS total_sales,
    ROUND(AVG(total_amount), 2)     AS avg_order_value,
    SUM(gross_profit)               AS total_gross_profit
FROM v_analysis_ready
GROUP BY region
ORDER BY total_sales DESC;

-- Summary by category
SELECT
    category,
    COUNT(*)                        AS transactions,
    SUM(total_amount)               AS total_sales,
    ROUND(AVG(units), 2)            AS avg_units
FROM v_analysis_ready
GROUP BY category
ORDER BY total_sales DESC;
