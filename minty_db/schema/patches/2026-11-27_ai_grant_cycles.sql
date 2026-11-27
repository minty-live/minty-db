-- 2026-11-27: the AI allowance follows the subscription (the user) - ai_grant's source gains 'trial'
-- (one 30-day AI trial per company, ever) and 'cycle' (one grant per billing period), and ai_policy
-- gains cycle_tokens (a period's tokens; NULL = no period grants) - for a database already recorded
-- at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_grant_cycles.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_grant_cycles.sql --apply
--
-- Every existing grant is 'default' or 'manual', which the new CHECK still allows; old code writes
-- only those and ignores cycle_tokens, so the patch goes first. Setting the policy (default_grant,
-- cycle_tokens) and resetting the companies' trials is a separate step, after the code is live.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'ai_policy'
               AND column_name = 'cycle_tokens') THEN
    RAISE EXCEPTION 'ai_policy.cycle_tokens is already in this schema';
  END IF;
END $$;

ALTER TABLE ai_grant
  DROP CONSTRAINT ck_ai_grant_source,
  ADD CONSTRAINT ck_ai_grant_source CHECK (source IN ('default', 'manual', 'trial', 'cycle'));
CREATE UNIQUE INDEX uq_ai_grant_one_trial ON ai_grant (entity_id) WHERE source = 'trial';
CREATE UNIQUE INDEX uq_ai_grant_cycle ON ai_grant (entity_id, expires_at) WHERE source = 'cycle';
ALTER TABLE ai_policy
  ADD COLUMN cycle_tokens INTEGER NULL,
  ADD CONSTRAINT ck_ai_policy_cycle_tokens CHECK (cycle_tokens IS NULL OR cycle_tokens > 0);

SELECT 'ai_grant: trial and cycle sources; ai_policy: cycle_tokens added' AS done;
