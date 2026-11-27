-- The way back from 2026-11-27_minty_changed_at.sql: drops account_info.minty_changed_at and
-- xero_contact_sync.minty_changed_at (any marks are lost; a reconnect then opens the matching only for
-- unlinked accounts, as before). Run it only with code that does not read them deployed.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_minty_changed_at_down.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_minty_changed_at_down.sql --apply

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = current_schema() AND table_name = 'account_info'
                   AND column_name = 'minty_changed_at') THEN
    RAISE EXCEPTION 'account_info.minty_changed_at is not in this schema';
  END IF;
END $$;

ALTER TABLE account_info DROP COLUMN minty_changed_at;
ALTER TABLE xero_contact_sync DROP COLUMN minty_changed_at;
