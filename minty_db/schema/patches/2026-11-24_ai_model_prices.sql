-- 2026-11-24 (the user): ai_policy.model_prices - each model's list price on Vertex AI's global
-- endpoint, USD per 1M tokens, {"<model>": {"input": n, "output": n, "cached_input": n}}, for a
-- database already recorded at 0001. Every read's ai_read.estimated_cost is worked out from it from
-- minty-shared v0.19 on; until now the prices were a constant in minty-shared's code.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_ai_model_prices.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_ai_model_prices.sql --apply
--
-- The prices (Vertex AI, global endpoint, standard pay-as-you-go, prompts up to 200K tokens; checked
-- 2026-11-24): gemini-3.5-flash-lite 0.30 in / 2.50 out / 0.03 cached in; gemini-3.5-flash 1.50 /
-- 9.00 / 0.15. The policy row must name only these models (else this stops: give the price by hand).
-- Old code ignores the column, so the patch can go first. Not re-runnable: a second run stops at the
-- guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'ai_policy'
               AND column_name = 'model_prices') THEN
    RAISE EXCEPTION 'ai_policy.model_prices is already in this schema';
  END IF;
END $$;

ALTER TABLE ai_policy ADD COLUMN model_prices JSONB NOT NULL DEFAULT '{}';

UPDATE ai_policy
   SET model_prices = '{"gemini-3.5-flash-lite": {"input": 0.30, "output": 2.50, "cached_input": 0.03},
                        "gemini-3.5-flash": {"input": 1.50, "output": 9.00, "cached_input": 0.15}}',
       updated_by = '2026-11-24_ai_model_prices.sql';

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM ai_policy
             WHERE NOT (model_prices ? primary_model)
                OR (backup_model IS NOT NULL AND NOT (model_prices ? backup_model))) THEN
    RAISE EXCEPTION 'ai_policy names a model this patch has no price for - add its price to the UPDATE above';
  END IF;
END $$;

ALTER TABLE ai_policy
  ALTER COLUMN model_prices DROP DEFAULT,
  ADD CONSTRAINT ck_ai_policy_prices CHECK (
    jsonb_typeof(model_prices) = 'object'
    AND model_prices ? primary_model
    AND (backup_model IS NULL OR model_prices ? backup_model));

SELECT id, primary_model, backup_model, model_prices FROM ai_policy;
