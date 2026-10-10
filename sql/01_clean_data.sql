DROP TABLE IF EXISTS grn_clean;
CREATE TABLE grn_clean AS
SELECT DISTINCT grn_id, po_id, grn_date, received_qty FROM grn;

DROP TABLE IF EXISTS daily_clean;
CREATE TABLE daily_clean AS
SELECT d.*,
       s.city, s.launch_date, k.category, k.shelf_life_days,
       CAST((julianday(d.date) - julianday('2026-07-06')) / 7 AS INT) + 1 AS week,
       CASE WHEN c.store_id IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
       CASE WHEN s.launch_date >= '2026-07-06' THEN 1 ELSE 0 END AS is_new_store,
       CASE WHEN c.store_id IS NULL AND s.launch_date < '2026-07-06' THEN 1 ELSE 0 END AS is_like_for_like
FROM daily_store_sku d
JOIN stores s ON s.store_id = d.store_id
JOIN skus k   ON k.sku_id   = d.sku_id
LEFT JOIN store_closures c ON c.store_id = d.store_id AND c.date = d.date;

DROP TABLE IF EXISTS po_clean;
CREATE TABLE po_clean AS
SELECT p.*,
       g.received_qty,
       s.city, k.category,
       CAST((julianday(p.po_date) - julianday('2026-07-06')) / 7 AS INT) + 1 AS week,
       CASE WHEN c.store_id IS NOT NULL THEN 1 ELSE 0 END AS is_closed,
       CASE WHEN s.launch_date >= '2026-07-06' THEN 1 ELSE 0 END AS is_new_store
FROM purchase_orders p
LEFT JOIN grn_clean g ON g.po_id = p.po_id
JOIN stores s ON s.store_id = p.store_id
JOIN skus k   ON k.sku_id   = p.sku_id
LEFT JOIN store_closures c ON c.store_id = p.store_id AND c.date = p.po_date;
