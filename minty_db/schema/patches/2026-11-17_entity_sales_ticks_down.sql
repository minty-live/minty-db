-- 2026-11-17: the way back from 2026-11-17_entity_sales_ticks.sql. It forgets every company's
-- Electronic Payment / Delivery ticks. One transaction, rolled back unless --apply. Run it only
-- with the services back on a minty-db before v0.11.

ALTER TABLE entities
  DROP COLUMN sells_electronic,
  DROP COLUMN sells_delivery;

SELECT 'entities.sells_electronic and sells_delivery removed' AS done;
