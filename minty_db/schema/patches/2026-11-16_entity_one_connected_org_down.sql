-- 2026-11-16: the way back from 2026-11-16_entity_one_connected_org.sql. It drops the index only
-- (no data changes); accounts-api's connect check still holds the rule. One transaction, rolled
-- back unless --apply.

DROP INDEX uq_entities_connected_xero_org;

SELECT 'uq_entities_connected_xero_org removed' AS done;
