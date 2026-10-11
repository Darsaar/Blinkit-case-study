-- =====================================================================
-- Blinkit case study: data-quality checks (PostgreSQL)
-- Run after loading the raw CSVs. Each check states the expected result.
-- =====================================================================

-- C1. Date range and number of days
-- Expect: 2026-07-06 to 2026-08-30, 56 days
SELECT MIN(date) AS first_day, MAX(date) AS last_day, COUNT(DISTINCT date) AS days
FROM daily_store_sku;

-- C2. Duplicate store x SKU x day rows in the daily table
-- Expect: 0
SELECT COUNT(*) AS duplicate_keys
FROM (SELECT date, store_id, sku_id
      FROM daily_store_sku
      GROUP BY 1, 2, 3
      HAVING COUNT(*) > 1) x;

-- C3. Duplicate rows in GRN
-- Expect: 33942 rows, 33115 unique grn_id -> 827 duplicates
SELECT COUNT(*)                          AS total_rows,
       COUNT(DISTINCT grn_id)            AS unique_grns,
       COUNT(*) - COUNT(DISTINCT grn_id) AS duplicate_rows
FROM grn;

-- C4. Are the GRN duplicates exact copies? (same qty on every copy)
-- Expect: 0 grn_ids with conflicting quantities
SELECT COUNT(*) AS grn_with_conflicting_qty
FROM (SELECT grn_id
      FROM grn
      GROUP BY grn_id
      HAVING COUNT(DISTINCT received_qty) > 1) x;

-- C5. Duplicate POs (same store x SKU x day, or same po_id)
-- Expect: 0 and 0
SELECT
  (SELECT COUNT(*) FROM (SELECT store_id, sku_id, po_date FROM purchase_orders
                         GROUP BY 1, 2, 3 HAVING COUNT(*) > 1) a) AS dup_store_sku_day,
  (SELECT COUNT(*) FROM (SELECT po_id FROM purchase_orders
                         GROUP BY 1 HAVING COUNT(*) > 1) b)       AS dup_po_id;

-- C6. Orphan keys: IDs that don't exist in the lookup tables
-- Expect: 0 for all
SELECT
  (SELECT COUNT(*) FROM daily_store_sku d WHERE NOT EXISTS (SELECT 1 FROM stores s WHERE s.store_id = d.store_id)) AS daily_bad_store,
  (SELECT COUNT(*) FROM daily_store_sku d WHERE NOT EXISTS (SELECT 1 FROM skus   k WHERE k.sku_id   = d.sku_id))   AS daily_bad_sku,
  (SELECT COUNT(*) FROM grn g             WHERE NOT EXISTS (SELECT 1 FROM purchase_orders p WHERE p.po_id = g.po_id)) AS grn_bad_po;

-- C7. Missing days: every store should have 22 SKUs x every day since launch
-- Expect: old stores 1232 rows (22 x 56); new stores fewer, starting at launch
SELECT d.store_id, s.city, s.launch_date,
       MIN(d.date)            AS first_day,
       COUNT(DISTINCT d.date) AS days,
       COUNT(*)               AS rows,
       COUNT(DISTINCT d.sku_id) AS skus
FROM daily_store_sku d
JOIN stores s ON s.store_id = d.store_id
GROUP BY 1, 2, 3
ORDER BY 1;

-- C8. Rows dated before a store's launch
-- Expect: 0
SELECT COUNT(*) AS rows_before_launch
FROM daily_store_sku d
JOIN stores s ON s.store_id = d.store_id
WHERE d.date < s.launch_date;

-- C9. Impossible values in the daily table
-- Expect: 0, 0, 0, 0 and 35 rows dumped while 0 hours in stock (plausible: expired then sold out)
SELECT
  COUNT(*) FILTER (WHERE in_stock_hours > operating_hours)                AS instock_gt_open,
  COUNT(*) FILTER (WHERE in_stock_hours < 0 OR units_sold < 0 OR units_dumped < 0) AS negatives,
  COUNT(*) FILTER (WHERE in_stock_hours = 0 AND units_sold > 0)           AS sold_while_oos,
  COUNT(*) FILTER (WHERE operating_hours <> 18)                           AS non_standard_hours,
  COUNT(*) FILTER (WHERE in_stock_hours = 0 AND units_dumped > 0)         AS dumped_while_oos
FROM daily_store_sku;

-- C10. PO status vs GRN: cancelled with a receipt, confirmed without one
-- Expect: CANCELLED 611 POs, 0 with GRN | CONFIRMED 33115 POs, all with GRN
SELECT p.po_status,
       COUNT(*)                              AS pos,
       COUNT(g.po_id)                        AS with_grn,
       COUNT(*) FILTER (WHERE g.po_id IS NULL) AS without_grn
FROM purchase_orders p
LEFT JOIN (SELECT DISTINCT po_id FROM grn) g ON g.po_id = p.po_id
GROUP BY p.po_status;

-- C11. Received more than ordered, zero received, or GRN date != PO date
-- Expect: 0, 0, 0
SELECT
  COUNT(*) FILTER (WHERE g.received_qty > p.po_qty) AS over_delivered,
  COUNT(*) FILTER (WHERE g.received_qty = 0)        AS zero_received,
  COUNT(*) FILTER (WHERE g.grn_date <> p.po_date)   AS date_mismatch
FROM purchase_orders p
JOIN (SELECT DISTINCT grn_id, po_id, grn_date, received_qty FROM grn) g ON g.po_id = p.po_id;

-- C12. Store closures: what the daily table records on closed days
-- Expect: 11 store-days (CBE04 11-16 Aug, CBE09 15-19 Aug),
--         396 operating hours (22 SKUs x 18h) but 0 in stock, 0 sold, 0 dumped
SELECT c.store_id, c.date, c.closed_full_day,
       SUM(d.operating_hours) AS operating_hours,
       SUM(d.in_stock_hours)  AS in_stock_hours,
       SUM(d.units_sold)      AS sold,
       SUM(d.units_dumped)    AS dumped
FROM store_closures c
JOIN daily_store_sku d ON d.store_id = c.store_id AND d.date = c.date
GROUP BY 1, 2, 3
ORDER BY 1, 2;

-- C13. POs raised for closed days
-- Expect: 242 POs, all CANCELLED
SELECT p.po_status, COUNT(*) AS pos, SUM(p.po_qty) AS qty
FROM purchase_orders p
JOIN store_closures c ON c.store_id = p.store_id AND c.date = p.po_date
GROUP BY p.po_status;

-- C14. New stores: launched inside the analysis window
-- Expect: CBE16-CBE20, launched 3-6 Aug 2026
SELECT store_id, city, launch_date
FROM stores
WHERE launch_date >= DATE '2026-07-06'
ORDER BY launch_date;

-- C15. Stock carry-over: days where sold + dumped exceeds what arrived that day
-- Expect: 1021 rows -> stock carries over between days
SELECT COUNT(*) AS days_out_gt_in
FROM daily_store_sku d
JOIN purchase_orders p ON p.store_id = d.store_id AND p.sku_id = d.sku_id AND p.po_date = d.date
JOIN (SELECT DISTINCT grn_id, po_id, received_qty FROM grn) g ON g.po_id = p.po_id
WHERE d.units_sold + d.units_dumped > g.received_qty;
