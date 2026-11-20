-- The way back from 2026-11-20_ai_grant_ended.sql: ended_at and ended_by leave ai_grant (who ended a
-- grant is lost; an ended grant stays ended, by its expires_at). One transaction, rolled back unless
-- --apply. Run it only with accounts-api back on a minty-db before v0.16.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_grant_ended_down.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_grant_ended_down.sql --apply

ALTER TABLE ai_grant
  DROP CONSTRAINT ck_ai_grant_ended,
  DROP COLUMN ended_at,
  DROP COLUMN ended_by;

SELECT 'ai_grant: ended_at and ended_by removed' AS done;
