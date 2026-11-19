-- The way back from 2026-11-19_exchange_rate.sql: the six exchange-rate columns leave report_expense
-- and bill (what they held is lost; `amount` is untouched). One transaction, rolled back unless
-- --apply. Run it only with the services back on a minty-db before v0.14.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_exchange_rate_down.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_exchange_rate_down.sql --apply

ALTER TABLE report_expense
  DROP CONSTRAINT ck_report_expense_exchange,
  DROP COLUMN original_currency,
  DROP COLUMN original_amount,
  DROP COLUMN exchange_rate,
  DROP COLUMN exchange_rate_date,
  DROP COLUMN exchange_rate_basis,
  DROP COLUMN exchange_rate_source;
ALTER TABLE bill
  DROP CONSTRAINT ck_bill_exchange,
  DROP COLUMN original_currency,
  DROP COLUMN original_amount,
  DROP COLUMN exchange_rate,
  DROP COLUMN exchange_rate_date,
  DROP COLUMN exchange_rate_basis,
  DROP COLUMN exchange_rate_source;

SELECT 'report_expense and bill: the six exchange-rate columns removed' AS done;
