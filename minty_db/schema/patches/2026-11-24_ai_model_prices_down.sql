-- 2026-11-24: the way back from 2026-11-24_ai_model_prices.sql. ai_policy loses model_prices and its
-- CHECK. One transaction, rolled back unless --apply. minty-shared before v0.19 never reads it; from
-- v0.19 on, reading is OFF without it (load_policy cannot parse the policy).

ALTER TABLE ai_policy
  DROP CONSTRAINT ck_ai_policy_prices,
  DROP COLUMN model_prices;

SELECT 'ai_policy.model_prices is gone' AS done;
