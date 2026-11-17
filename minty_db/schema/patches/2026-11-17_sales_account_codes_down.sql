-- 2026-11-17: the way back from 2026-11-17_sales_account_codes.sql. It forgets Sales - Electronic
-- Payment's and Sales - Delivery's account codes. One transaction, rolled back unless --apply. Run it
-- only with the services back on a minty-db before v0.12.

ALTER TABLE entity_pettycash_settings
  DROP COLUMN electronic_sale_account_id,   -- with fk_eps_elecsale_acct
  DROP COLUMN delivery_sale_account_id;     -- with fk_eps_delsale_acct

SELECT 'electronic_sale_account_id and delivery_sale_account_id removed' AS done;
