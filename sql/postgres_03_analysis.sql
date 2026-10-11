-- =====================================================================
-- Blinkit case study: analysis queries (PostgreSQL)
-- Run after postgres_01_setup_and_clean.sql.
-- Uses daily_clean and po_clean; every query states the expected result.
-- =====================================================================


-- =============== PHASE 4: Reproduce the manager's headline ===============

-- A1. Weekly availability by city, all rows (the manager's view)
-- Expect: Coimbatore ~95.8 in weeks 1-4, then 93.0 / 81.1 / 87.7 / 90.3; Salem flat ~96
--         Coimbatore rows jump from 2310 to ~3080 from week 5 (new stores)
SELECT city, week,
       COUNT(*) AS rows,
       ROUND(100.0 * SUM(in_stock_hours) / SUM(operating_hours), 2) AS availability
FROM daily_clean
GROUP BY city, week
ORDER BY city, week;


-- =============== PHASE 5: Remove distortions ===============

-- A2. Coimbatore: raw vs closures included vs old stores open days vs new stores
-- Expect week 6: raw 81.07 | old stores incl. closed 83.17 | old store open 90.02 | new 74.78
SELECT week,
  ROUND(100.0 * SUM(in_stock_hours) / SUM(operating_hours), 2) AS raw_all,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE NOT is_new_store)
              / SUM(operating_hours) FILTER (WHERE NOT is_new_store), 2) AS old_incl_closed,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE is_old_store_open)
              / SUM(operating_hours) FILTER (WHERE is_old_store_open), 2) AS old_store_open,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE is_new_store)
              / SUM(operating_hours) FILTER (WHERE is_new_store), 2) AS new_stores
FROM daily_clean
WHERE city = 'Coimbatore'
GROUP BY week
ORDER BY week;


-- =============== PHASE 6: Locate the problem ===============

-- A3. Old-store open-day availability by category and week (Coimbatore)
-- Expect: FnV ~96-97 every week; Milk ~94 -> ~79 from week 6
SELECT category, week,
       ROUND(100.0 * SUM(in_stock_hours) / SUM(operating_hours), 1) AS availability
FROM daily_clean
WHERE city = 'Coimbatore' AND is_old_store_open
GROUP BY category, week
ORDER BY category, week;

-- A4. Milk availability by store, before vs after 10 Aug (open days only)
-- Expect: every old store drops by a similar amount; CBE04/CBE09 look normal
SELECT store_id,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE date <  DATE '2026-08-10')
              / SUM(operating_hours) FILTER (WHERE date <  DATE '2026-08-10'), 1) AS before,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE date >= DATE '2026-08-10')
              / SUM(operating_hours) FILTER (WHERE date >= DATE '2026-08-10'), 1) AS after
FROM daily_clean
WHERE city = 'Coimbatore' AND category = 'Milk' AND NOT is_closed
GROUP BY store_id
ORDER BY store_id;

-- A5. Milk availability by SKU, before vs after 10 Aug (old stores, open days)
-- Expect: all 8 milk SKUs drop together
SELECT sku_id,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE date <  DATE '2026-08-10')
              / SUM(operating_hours) FILTER (WHERE date <  DATE '2026-08-10'), 1) AS before,
  ROUND(100.0 * SUM(in_stock_hours)  FILTER (WHERE date >= DATE '2026-08-10')
              / SUM(operating_hours) FILTER (WHERE date >= DATE '2026-08-10'), 1) AS after
FROM daily_clean
WHERE city = 'Coimbatore' AND category = 'Milk' AND is_old_store_open
GROUP BY sku_id
ORDER BY sku_id;

-- A6. Daily availability around the break, stores that never closed
-- Expect: ~96.7 up to 9 Aug, ~90 from Mon 10 Aug -> not caused by maintenance
SELECT date,
       ROUND(100.0 * SUM(in_stock_hours) / SUM(operating_hours), 1) AS availability
FROM daily_clean
WHERE city = 'Coimbatore' AND NOT is_new_store
  AND store_id NOT IN (SELECT DISTINCT store_id FROM store_closures)
  AND date BETWEEN DATE '2026-08-05' AND DATE '2026-08-16'
GROUP BY date
ORDER BY date;


-- =============== PHASE 7: Root cause ===============

-- A7. Which vendor supplies which city and category
-- Expect: CBE Milk = V03, CBE FnV = V11, Salem Milk = V04, Salem FnV = V12
SELECT city, category, vendor_id, COUNT(*) AS pos
FROM po_clean
GROUP BY city, category, vendor_id
ORDER BY city, category;

-- A8. Weekly fill rate by vendor (confirmed POs only)
-- Expect: V03 ~97 in weeks 1-5, ~71 in weeks 6-8; V04, V11, V12 flat ~95-97
SELECT vendor_id, week,
       SUM(po_qty)       AS ordered,
       SUM(received_qty) AS received,
       ROUND(100.0 * SUM(received_qty) / SUM(po_qty), 1) AS fill_rate
FROM po_clean
WHERE po_status = 'CONFIRMED'
GROUP BY vendor_id, week
ORDER BY vendor_id, week;

-- A9. V03 daily fill rate around the break
-- Expect: ~97 up to Sun 9 Aug, ~71 from Mon 10 Aug (overnight step)
SELECT po_date,
       ROUND(100.0 * SUM(received_qty) / SUM(po_qty), 1) AS fill_rate
FROM po_clean
WHERE vendor_id = 'V03' AND po_status = 'CONFIRMED'
  AND po_date BETWEEN DATE '2026-08-03' AND DATE '2026-08-16'
GROUP BY po_date
ORDER BY po_date;

-- A10. V03 fill rate before vs after, by SKU and by store
-- Expect: every SKU and every store ~97 -> ~71
SELECT sku_id,
  ROUND(100.0 * SUM(received_qty) FILTER (WHERE po_date <  DATE '2026-08-10')
              / SUM(po_qty)       FILTER (WHERE po_date <  DATE '2026-08-10'), 1) AS before,
  ROUND(100.0 * SUM(received_qty) FILTER (WHERE po_date >= DATE '2026-08-10')
              / SUM(po_qty)       FILTER (WHERE po_date >= DATE '2026-08-10'), 1) AS after
FROM po_clean
WHERE vendor_id = 'V03' AND po_status = 'CONFIRMED'
GROUP BY sku_id
ORDER BY sku_id;

SELECT store_id,
  ROUND(100.0 * SUM(received_qty) FILTER (WHERE po_date <  DATE '2026-08-10')
              / SUM(po_qty)       FILTER (WHERE po_date <  DATE '2026-08-10'), 1) AS before,
  ROUND(100.0 * SUM(received_qty) FILTER (WHERE po_date >= DATE '2026-08-10')
              / SUM(po_qty)       FILTER (WHERE po_date >= DATE '2026-08-10'), 1) AS after
FROM po_clean
WHERE vendor_id = 'V03' AND po_status = 'CONFIRMED'
GROUP BY store_id
ORDER BY store_id;

-- A11. Percentage cut or capacity cap? Fill rate by order size, after 10 Aug
-- Expect: ~71 in every order-size bucket -> proportional cut, not a ceiling
SELECT CASE WHEN po_qty < 20 THEN '1: <20'
            WHEN po_qty < 30 THEN '2: 20-29'
            WHEN po_qty < 40 THEN '3: 30-39'
            ELSE '4: 40+' END AS order_size,
       COUNT(*) AS pos,
       ROUND(100.0 * SUM(received_qty) / SUM(po_qty), 1) AS fill_rate
FROM po_clean
WHERE vendor_id = 'V03' AND po_status = 'CONFIRMED' AND po_date >= DATE '2026-08-10'
GROUP BY 1
ORDER BY 1;

-- A12. Funnel: ordered -> received -> sold + dumped, before vs after (Coimbatore)
-- Expect: Milk fill ~97 -> ~71 and sell-through ~93 -> ~99.7 (starved);
--         FnV ~95 fill and ~92 sell-through in both periods
SELECT p.category,
       CASE WHEN p.po_date < DATE '2026-08-10' THEN '1_before' ELSE '2_after' END AS period,
       SUM(p.po_qty)        AS ordered,
       SUM(p.received_qty)  AS received,
       SUM(d.units_sold)    AS sold,
       SUM(d.units_dumped)  AS dumped,
       ROUND(100.0 * SUM(p.received_qty) / SUM(p.po_qty), 1) AS fill_rate,
       ROUND(100.0 * SUM(d.units_sold + d.units_dumped) / SUM(p.received_qty), 1) AS sell_through
FROM po_clean p
JOIN daily_clean d ON d.store_id = p.store_id AND d.sku_id = p.sku_id AND d.date = p.po_date
WHERE p.city = 'Coimbatore' AND p.po_status = 'CONFIRMED'
GROUP BY 1, 2
ORDER BY 1, 2;

-- A13. Demand and wastage per open store-day (old stores, open days, Coimbatore)
-- Expect: Milk sales ~250 -> ~200 per store-day and wastage ~1.4% -> ~0.4%;
--         FnV ~500 per store-day and ~11% wastage throughout
SELECT category, week,
       ROUND(1.0 * SUM(units_sold) / COUNT(DISTINCT (store_id, date)), 1) AS sold_per_store_day,
       ROUND(100.0 * SUM(units_dumped) / SUM(units_sold + units_dumped), 2) AS wastage_pct
FROM daily_clean
WHERE city = 'Coimbatore' AND is_old_store_open
GROUP BY category, week
ORDER BY category, week;

-- A14. Salem control: availability and wastage by category and week
-- Expect: flat ~94-97 availability; one wastage spike in FnV week 7
SELECT category, week,
       ROUND(100.0 * SUM(in_stock_hours) / SUM(operating_hours), 1) AS availability,
       ROUND(100.0 * SUM(units_dumped) / SUM(units_sold + units_dumped), 2) AS wastage_pct
FROM daily_clean
WHERE city = 'Salem'
GROUP BY category, week
ORDER BY category, week;


-- =============== PHASE 9: Cost of the +20% plan ===============

-- A15. Estimated lost sales from stock-outs since 10 Aug (Coimbatore, open days)
-- Assumption: demand while out of stock = sales rate while in stock
-- Expect: Milk ~21,000 units over 3 weeks (~7k/week); FnV ~5,800 (~2k/week)
SELECT category,
       SUM(units_sold) AS sold,
       ROUND(SUM(CASE WHEN in_stock_hours > 0
                      THEN units_sold / in_stock_hours * (operating_hours - in_stock_hours)
                      ELSE 0 END)) AS lost_units_est
FROM daily_clean
WHERE city = 'Coimbatore' AND NOT is_closed AND date >= DATE '2026-08-10'
GROUP BY category;

-- A16. Extra units a week that +20% would add (Coimbatore, weeks 6-8)
-- Expect: FnV ~76,500 received/week -> ~15,300 extra; Milk ~24,700 -> ~4,900 extra
SELECT category,
       ROUND(SUM(received_qty) / 3.0)       AS received_per_week,
       ROUND(0.2 * SUM(received_qty) / 3.0) AS extra_per_week_at_20pct
FROM po_clean
WHERE city = 'Coimbatore' AND po_status = 'CONFIRMED' AND week BETWEEN 6 AND 8
GROUP BY category;


-- =============== PHASE 10: Red herrings ===============

-- A17. Biggest single-day dumping by city
-- Expect: Salem 20 Aug ~4,400 units vs ~700 on a normal day (one-off)
SELECT date, city, SUM(units_dumped) AS dumped
FROM daily_clean
GROUP BY date, city
ORDER BY dumped DESC
LIMIT 10;

-- A18. Wastage by shelf life (healthy period, old stores, open days)
-- Expect: FnV ~11% for 2-, 5- and 7-day items -> no shelf-life effect in this data
SELECT category, shelf_life_days,
       ROUND(100.0 * SUM(units_dumped) / SUM(units_sold + units_dumped), 2) AS wastage_pct
FROM daily_clean
WHERE city = 'Coimbatore' AND is_old_store_open AND date < DATE '2026-08-10'
GROUP BY category, shelf_life_days
ORDER BY category, shelf_life_days;
