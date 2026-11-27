-- The way back from 2026-11-27_ai_grant_cycles.sql: ai_policy loses cycle_tokens and ai_grant's
-- source is back to 'default' and 'manual'. It stops if any 'trial' or 'cycle' grant exists (delete
-- or re-source them first: their reads would lose their grant). One transaction, rolled back unless
-- --apply. Run it only with every service back on a minty-db before v0.22.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_grant_cycles_down.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_grant_cycles_down.sql --apply

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM ai_grant WHERE source IN ('trial', 'cycle')) THEN
    RAISE EXCEPTION 'ai_grant still holds trial or cycle grants';
  END IF;
END $$;

ALTER TABLE ai_policy
  DROP CONSTRAINT ck_ai_policy_cycle_tokens,
  DROP COLUMN cycle_tokens;
DROP INDEX uq_ai_grant_cycle;
DROP INDEX uq_ai_grant_one_trial;
ALTER TABLE ai_grant
  DROP CONSTRAINT ck_ai_grant_source,
  ADD CONSTRAINT ck_ai_grant_source CHECK (source IN ('default', 'manual'));

SELECT 'ai_grant: trial and cycle sources removed; ai_policy: cycle_tokens removed' AS done;
