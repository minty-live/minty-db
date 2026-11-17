-- 2026-11-17: entities.sells_electronic and entities.sells_delivery - Accounting Setup's sales
-- accounts screen (owner-approved, 2026-11-17) - for a database already recorded at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (beside uses_sales_cash in the entities
-- ALTER), so a fresh build already has them. Schema changes stay baseline (owner, 2026-11-10):
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-17_entity_sales_ticks.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-17_entity_sales_ticks.sql --apply
--
-- The screen lists three sales accounts: Sales - Cash (uses_sales_cash, unchanged), Sales -
-- Electronic Payment and Sales - Delivery. A ticked account's sales methods are asked for in Petty
-- Cash Settings; an unticked one's are not. NULL = not chosen yet: the business type decides
-- (onboarding-api). No backfill - every company starts NULL. Old code ignores the columns.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'entities'
               AND column_name IN ('sells_electronic', 'sells_delivery')) THEN
    RAISE EXCEPTION 'entities.sells_electronic / sells_delivery is already in this schema';
  END IF;
END $$;

ALTER TABLE entities
  ADD COLUMN sells_electronic BOOLEAN NULL,
  ADD COLUMN sells_delivery   BOOLEAN NULL;

SELECT count(*) AS companies FROM entities;
