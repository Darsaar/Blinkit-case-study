-- =====================================================================
-- Blinkit case study: DuckDB setup + data cleaning
-- Run from the folder that contains the CSV files (blinkit_csv/).
-- After this, postgres_02_data_quality_checks.sql and
-- postgres_03_analysis.sql run unchanged in DuckDB.
-- =====================================================================

-- ---------- Step 1: load the CSVs (types are detected automatically) ----------
-- If your SQL tool cannot see local files (browser tools such as sqliteonline),
-- import the 6 CSVs through the tool instead and continue from Step 1b.
-- Desktop tools: use the full path, e.g. read_csv_auto('C:/.../problem/stores.csv').
CREATE OR REPLACE TABLE stores          AS SELECT * FROM read_csv_auto('stores.csv');
CREATE OR REPLACE TABLE skus            AS SELECT * FROM read_csv_auto('skus.csv');
CREATE OR REPLACE TABLE daily_store_sku AS SELECT * FROM read_csv_auto('daily_store_sku.csv');
CREATE OR REPLACE TABLE purchase_orders AS SELECT * FROM read_csv_auto('purchase_orders.csv');
CREATE OR REPLACE TABLE grn             AS SELECT * FROM read_csv_auto('grn.csv');
CREATE OR REPLACE TABLE store_closures  AS SELECT * FROM read_csv_auto('store_closures.csv');

-- ---------- Step 1b: make every date column a real DATE ----------
-- Some import tools store dates as epoch milliseconds (e.g. 1783296000000 = 2026-07-06),
-- which breaks date arithmetic ("Unimplemented type for cast (BIGINT -> DATE)").
-- Safe to run every time: COALESCE tries a normal date cast first (DATE, TIMESTAMP,
-- 'YYYY-MM-DD' text), then falls back to epoch milliseconds (BIGINT, DOUBLE, digit text).
-- Converting with epoch_ms alone would turn columns that are already dates into NULL.
ALTER TABLE daily_store_sku ALTER COLUMN date        TYPE DATE
  USING COALESCE(TRY_CAST(date AS DATE),        epoch_ms(TRY_CAST(date AS BIGINT))::DATE);
ALTER TABLE purchase_orders ALTER COLUMN po_date     TYPE DATE
  USING COALESCE(TRY_CAST(po_date AS DATE),     epoch_ms(TRY_CAST(po_date AS BIGINT))::DATE);
ALTER TABLE grn             ALTER COLUMN grn_date    TYPE DATE
  USING COALESCE(TRY_CAST(grn_date AS DATE),    epoch_ms(TRY_CAST(grn_date AS BIGINT))::DATE);
ALTER TABLE stores          ALTER COLUMN launch_date TYPE DATE
  USING COALESCE(TRY_CAST(launch_date AS DATE), epoch_ms(TRY_CAST(launch_date AS BIGINT))::DATE);
ALTER TABLE store_closures  ALTER COLUMN date        TYPE DATE
  USING COALESCE(TRY_CAST(date AS DATE),        epoch_ms(TRY_CAST(date AS BIGINT))::DATE);

-- Check: expect 2026-07-06 | 2026-08-30 | 0 missing dates
SELECT MIN(date) AS first_day, MAX(date) AS last_day,
       COUNT(*) FILTER (WHERE date IS NULL) AS missing_dates
FROM daily_store_sku;

-- ---------- Step 2: cleaned tables ----------

-- GRN without the duplicate rows
CREATE OR REPLACE TABLE grn_clean AS
SELECT DISTINCT grn_id, po_id, grn_date, received_qty
FROM grn;

-- Daily data with city, category, week number and edge-case flags
CREATE OR REPLACE TABLE daily_clean AS
SELECT d.*,
       s.city,
       s.launch_date,
       k.category,
       k.shelf_life_days,
       FLOOR((d.date::date - DATE '2026-07-06') / 7.0)::int + 1     AS week,
       (c.store_id IS NOT NULL)                                     AS is_closed,
       (s.launch_date >= DATE '2026-07-06')                         AS is_new_store,
       (c.store_id IS NULL AND s.launch_date < DATE '2026-07-06')   AS is_old_store_open
FROM daily_store_sku d
JOIN stores s ON s.store_id = d.store_id
JOIN skus   k ON k.sku_id   = d.sku_id
LEFT JOIN store_closures c ON c.store_id = d.store_id AND c.date = d.date;

-- POs with de-duplicated received qty and the same flags
CREATE OR REPLACE TABLE po_clean AS
SELECT p.*,
       g.received_qty,
       s.city,
       k.category,
       FLOOR((p.po_date::date - DATE '2026-07-06') / 7.0)::int + 1  AS week,
       (c.store_id IS NOT NULL)                                     AS is_closed,
       (s.launch_date >= DATE '2026-07-06')                         AS is_new_store
FROM purchase_orders p
LEFT JOIN grn_clean g ON g.po_id = p.po_id
JOIN stores s ON s.store_id = p.store_id
JOIN skus   k ON k.sku_id   = p.sku_id
LEFT JOIN store_closures c ON c.store_id = p.store_id AND c.date = p.po_date;

-- ---------- Sanity checks ----------
-- Expect: 33726 rows | 242 closed | 2926 new-store | 30558 old-store-open
SELECT COUNT(*),
       COUNT(*) FILTER (WHERE is_closed),
       COUNT(*) FILTER (WHERE is_new_store),
       COUNT(*) FILTER (WHERE is_old_store_open)
FROM daily_clean;

-- Expect: 33726 POs | 33115 received | 611 cancelled | 242 on closed days
SELECT COUNT(*),
       COUNT(received_qty),
       COUNT(*) FILTER (WHERE po_status = 'CANCELLED'),
       COUNT(*) FILTER (WHERE is_closed)
FROM po_clean;

-- Expect: 33115
SELECT COUNT(*) FROM grn_clean;

-- Expect: weeks 1-8, type INTEGER
SELECT week, typeof(week) AS type, COUNT(*) AS rows
FROM daily_clean
GROUP BY week
ORDER BY week;
