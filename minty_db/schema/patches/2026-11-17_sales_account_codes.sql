-- 2026-11-17: entity_pettycash_settings.electronic_sale_account_id and delivery_sale_account_id -
-- Sales - Electronic Payment's and Sales - Delivery's account codes (owner, 2026-11-17: "each sales
-- should be tied"), as cash_sale_account_id is Sales - Cash's - for a database already at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (both in the table's CREATE), so a fresh
-- build already has them. Schema changes stay baseline (owner, 2026-11-10):
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-17_sales_account_codes.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-17_sales_account_codes.sql --apply
--
-- Settings' Account mapping picks them (a Xero company from its Xero chart); a company keeping its
-- books in Minty gets them from onboarding (4001 Credit Card Sales; 4002 Online Sales, 4004 Delivery
-- Sales for General). The day's sales invoice has a line for each. No backfill. Old code ignores
-- them. Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'entity_pettycash_settings'
               AND column_name IN ('electronic_sale_account_id', 'delivery_sale_account_id')) THEN
    RAISE EXCEPTION 'entity_pettycash_settings.electronic_sale_account_id / delivery_sale_account_id is already in this schema';
  END IF;
END $$;

ALTER TABLE entity_pettycash_settings
  ADD COLUMN electronic_sale_account_id UUID NULL,
  ADD COLUMN delivery_sale_account_id   UUID NULL,
  ADD CONSTRAINT fk_eps_elecsale_acct FOREIGN KEY (electronic_sale_account_id) REFERENCES account_info (id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_eps_delsale_acct  FOREIGN KEY (delivery_sale_account_id)   REFERENCES account_info (id) ON DELETE SET NULL;

SELECT count(*) AS companies_with_settings FROM entity_pettycash_settings;
