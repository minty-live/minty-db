-- 2026-11-23: ai_policy.location and ck_ai_policy_location go (owner: "no need for setting region") -
-- for a database already at 0001.
--
-- Every AI read now runs on Vertex AI's global endpoint (minty-shared v0.12: ai.VERTEX_LOCATION =
-- "global"; its load_policy selects named columns and no longer reads location). The column came in
-- with 2026-11-20_ai_reader_settings.sql. The baseline is minty_db/schema/01_schema_rebased.sql, so a
-- fresh build already lacks it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-23_drop_ai_policy_location.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-23_drop_ai_policy_location.sql --apply
--
-- ORDER: run it only once petty-cash-api and payment-request-api pin minty-db v0.17. Their services
-- are safe either way (named columns), but petty-cash-api's hand-run `manage.py ai_policy` loads the
-- whole row through a model that, before v0.17, still declares location - and fails once it is gone.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = current_schema() AND table_name = 'ai_policy' AND column_name = 'location') THEN
    RAISE EXCEPTION 'ai_policy.location is already gone from this schema';
  END IF;
END $$;

SELECT id, location AS location_dropped FROM ai_policy;

ALTER TABLE ai_policy
  DROP CONSTRAINT ck_ai_policy_location,
  DROP COLUMN location;
