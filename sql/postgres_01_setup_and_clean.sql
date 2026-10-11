-- =====================================================================
-- Blinkit case study: PostgreSQL setup + data cleaning
-- Step 1: create the raw tables
-- Step 2: load the CSVs (pgAdmin Import/Export, or \copy in psql)
-- Step 3: build cleaned tables with edge-case flags
-- =====================================================================

-- ---------- Step 1: raw tables ----------
DROP TABLE IF EXISTS stores, skus, daily_store_sku, purchase_orders, grn, store_closures CASCADE;

CREATE TABLE stores (
    store_id     TEXT PRIMARY KEY,
    city         TEXT,
    launch_date  DATE
);

CREATE TABLE skus (
    sku_id           TEXT PRIMARY KEY,
    sku_name         TEXT,
    category         TEXT,
    shelf_life_days  INT
);

CREATE TABLE daily_store_sku (
    date             DATE,
    store_id         TEXT,
    sku_id           TEXT,
    operating_hours  NUMERIC,
    in_stock_hours   NUMERIC,
    units_sold       INT,
    units_dumped     INT
);

CREATE TABLE purchase_orders (
    po_id      TEXT,
    po_date    DATE,
    store_id   TEXT,
    sku_id     TEXT,
    vendor_id  TEXT,
    po_qty     INT,
    po_status  TEXT
);

-- no primary key on grn: the raw file has duplicate rows
CREATE TABLE grn (
    grn_id        TEXT,
    po_id         TEXT,
    grn_date      DATE,
    received_qty  INT
);

CREATE TABLE store_closures (
    store_id         TEXT,
    date             DATE,
    reason           TEXT,
    closed_full_day  INT
);

-- ---------- Step 2: load CSVs ----------
-- In psql, run from the folder that contains the CSV files:
-- \copy stores          FROM 'stores.csv'          WITH (FORMAT csv, HEADER true)
-- \copy skus            FROM 'skus.csv'            WITH (FORMAT csv, HEADER true)
-- \copy daily_store_sku FROM 'daily_store_sku.csv' WITH (FORMAT csv, HEADER true)
-- \copy purchase_orders FROM 'purchase_orders.csv' WITH (FORMAT csv, HEADER true)
-- \copy grn             FROM 'grn.csv'             WITH (FORMAT csv, HEADER true)
-- \copy store_closures  FROM 'store_closures.csv'  WITH (FORMAT csv, HEADER true)
-- In pgAdmin: right-click each table > Import/Export Data > Import,
-- choose the CSV, Format = csv, Header = on.

-- ---------- Step 3: cleaned tables ----------

-- GRN without the duplicate rows
DROP TABLE IF EXISTS grn_clean;
CREATE TABLE grn_clean AS
SELECT DISTINCT grn_id, po_id, grn_date, received_qty
FROM grn;

-- Daily data with city, category, week number and edge-case flags
DROP TABLE IF EXISTS daily_clean;
CREATE TABLE daily_clean AS
SELECT d.*,
       s.city,
       s.launch_date,
       k.category,
       k.shelf_life_days,
       FLOOR((d.date::date - DATE '2026-07-06') / 7.0)::int + 1      AS week,
       (c.store_id IS NOT NULL)                                       AS is_closed,
       (s.launch_date >= DATE '2026-07-06')                           AS is_new_store,
       (c.store_id IS NULL AND s.launch_date < DATE '2026-07-06')     AS is_old_store_open
FROM daily_store_sku d
JOIN stores s ON s.store_id = d.store_id
JOIN skus   k ON k.sku_id   = d.sku_id
LEFT JOIN store_closures c ON c.store_id = d.store_id AND c.date = d.date;

-- POs with de-duplicated received qty and the same flags
DROP TABLE IF EXISTS po_clean;
CREATE TABLE po_clean AS
SELECT p.*,
       g.received_qty,
       s.city,
       k.category,
       FLOOR((p.po_date::date - DATE '2026-07-06') / 7.0)::int + 1   AS week,
       (c.store_id IS NOT NULL)                                       AS is_closed,
       (s.launch_date >= DATE '2026-07-06')                           AS is_new_store
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
