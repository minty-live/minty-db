-- 2026-11-20: ai_grant gains ended_at and ended_by (owner) - a superuser can end a company's AI
-- grant early, and the AI allowances dialog shows when and who - for a database already recorded
-- at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_grant_ended.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_grant_ended.sql --apply
--
-- Ending a grant sets its expires_at to now (the allowance already stops counting an expired grant)
-- and these two columns; both set or both empty. Every existing grant has neither; old code ignores
-- them, so the patch can go first.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'ai_grant'
               AND column_name = 'ended_at') THEN
    RAISE EXCEPTION 'ai_grant.ended_at is already in this schema';
  END IF;
END $$;

ALTER TABLE ai_grant
  ADD COLUMN ended_at TIMESTAMPTZ  NULL,
  ADD COLUMN ended_by VARCHAR(255) NULL,
  ADD CONSTRAINT ck_ai_grant_ended CHECK (
    (ended_at IS NULL AND ended_by IS NULL) OR (ended_at IS NOT NULL AND ended_by IS NOT NULL));

SELECT 'ai_grant: ended_at and ended_by added' AS done;
