-- 2026-11-19: report_expense and bill gain how an AI-read amount in another currency was converted
-- (owner; Frankfurter v1, the European Central Bank's reference rates), for a database already
-- recorded at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_exchange_rate.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_exchange_rate.sql --apply
--
-- Six nullable columns on each table: the document's currency and amount, the rate, the day it is
-- for, whether that day was the document's ('receipt') or the report's ('report_date'), and the
-- source. All six or none (the CHECK). `amount` stays in the company currency. Every existing row
-- has none; old code ignores them.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name IN ('report_expense', 'bill')
               AND column_name = 'exchange_rate') THEN
    RAISE EXCEPTION 'the exchange-rate columns are already in this schema';
  END IF;
END $$;

ALTER TABLE report_expense
  ADD COLUMN original_currency    CHAR(3)        NULL,
  ADD COLUMN original_amount      NUMERIC(14,2)  NULL,
  ADD COLUMN exchange_rate        NUMERIC(20,10) NULL,
  ADD COLUMN exchange_rate_date   DATE           NULL,
  ADD COLUMN exchange_rate_basis  VARCHAR(16)    NULL,
  ADD COLUMN exchange_rate_source VARCHAR(32)    NULL,
  ADD CONSTRAINT ck_report_expense_exchange CHECK (
    (original_currency IS NULL AND original_amount IS NULL AND exchange_rate IS NULL
       AND exchange_rate_date IS NULL AND exchange_rate_basis IS NULL AND exchange_rate_source IS NULL)
    OR (original_currency IS NOT NULL AND original_amount IS NOT NULL AND exchange_rate IS NOT NULL AND exchange_rate > 0
       AND exchange_rate_date IS NOT NULL AND exchange_rate_basis IS NOT NULL
       AND exchange_rate_basis IN ('receipt', 'report_date')
       AND exchange_rate_source IS NOT NULL));
ALTER TABLE bill
  ADD COLUMN original_currency    CHAR(3)        NULL,
  ADD COLUMN original_amount      NUMERIC(14,2)  NULL,
  ADD COLUMN exchange_rate        NUMERIC(20,10) NULL,
  ADD COLUMN exchange_rate_date   DATE           NULL,
  ADD COLUMN exchange_rate_basis  VARCHAR(16)    NULL,
  ADD COLUMN exchange_rate_source VARCHAR(32)    NULL,
  ADD CONSTRAINT ck_bill_exchange CHECK (
    (original_currency IS NULL AND original_amount IS NULL AND exchange_rate IS NULL
       AND exchange_rate_date IS NULL AND exchange_rate_basis IS NULL AND exchange_rate_source IS NULL)
    OR (original_currency IS NOT NULL AND original_amount IS NOT NULL AND exchange_rate IS NOT NULL AND exchange_rate > 0
       AND exchange_rate_date IS NOT NULL AND exchange_rate_basis IS NOT NULL
       AND exchange_rate_basis IN ('receipt', 'report_date')
       AND exchange_rate_source IS NOT NULL));

SELECT 'report_expense and bill: the six exchange-rate columns added' AS done;
