-- 2026-11-27 (the user): account_info.minty_changed_at and xero_contact_sync.minty_changed_at - an
-- account or contact added or changed in Minty while Xero was off, for a database already recorded at
-- 0001. A disconnected company is Minty-only: its accounts and contacts, linked ones too, are edited
-- there. A reconnect then opens the matching for them (accounts-api matching.needs_matching) and Finish
-- clears the mark. NULL = nothing to check; existing rows start NULL.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql, so a fresh build already has them:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_minty_changed_at.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_minty_changed_at.sql --apply
--
-- Old code ignores the columns, so the patch goes first. Not re-runnable: a second run stops at the
-- guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND column_name = 'minty_changed_at'
               AND table_name IN ('account_info', 'xero_contact_sync')) THEN
    RAISE EXCEPTION 'minty_changed_at is already in this schema';
  END IF;
END $$;

ALTER TABLE account_info ADD COLUMN minty_changed_at TIMESTAMPTZ NULL;
ALTER TABLE xero_contact_sync ADD COLUMN minty_changed_at TIMESTAMPTZ NULL;

SELECT (SELECT count(*) FROM account_info) AS accounts,
       (SELECT count(*) FROM xero_contact_sync) AS contacts;
