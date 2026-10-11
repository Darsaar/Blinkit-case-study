-- =====================================================================
-- Blinkit case study: DuckDB setup + data cleaning
-- Run from the folder that contains the CSV files (blinkit_csv/).
-- After this, postgres_02_data_quality_checks.sql and
-- postgres_03_analysis.sql run unchanged in DuckDB.
-- =====================================================================

-- ---------- Step 1: load the CSVs (types are detected automatically) ----------
CREATE OR REPLACE TABLE stores          AS SELECT * FROM read_csv_auto('stores.csv');
CREATE OR REPLACE TABLE skus            AS SELECT * FROM read_csv_auto('skus.csv');
CREATE OR REPLACE TABLE daily_store_sku AS SELECT * FROM read_csv_auto('daily_store_sku.csv');
CREATE OR REPLACE TABLE purchase_orders AS SELECT * FROM read_csv_auto('purchase_orders.csv');
CREATE OR REPLACE TABLE grn             AS SELECT * FROM read_csv_auto('grn.csv');
CREATE OR REPLACE TABLE store_closures  AS SELECT * FROM read_csv_auto('store_closures.csv');

-- ---------- Step 1b (only if your tool loaded dates as numbers, e.g. 1783296000000) ----------
-- Remove the -- to run. Skip if the dates are already DATE: these lines would turn them into NULL.
-- ALTER TABLE daily_store_sku ALTER COLUMN date        TYPE DATE USING epoch_ms(TRY_CAST(date AS BIGINT))::DATE;
-- ALTER TABLE purchase_orders ALTER COLUMN po_date     TYPE DATE USING epoch_ms(TRY_CAST(po_date AS BIGINT))::DATE;
-- ALTER TABLE grn             ALTER COLUMN grn_date    TYPE DATE USING epoch_ms(TRY_CAST(grn_date AS BIGINT))::DATE;
-- ALTER TABLE stores          ALTER COLUMN launch_date TYPE DATE USING epoch_ms(TRY_CAST(launch_date AS BIGINT))::DATE;
-- ALTER TABLE store_closures  ALTER COLUMN date        TYPE DATE USING epoch_ms(TRY_CAST(date AS BIGINT))::DATE;

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
