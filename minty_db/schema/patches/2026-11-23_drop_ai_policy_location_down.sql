-- 2026-11-23: the way back from 2026-11-23_drop_ai_policy_location.sql. ai_policy gets its location
-- column back as 'global' (the endpoint every read uses since that day), with its CHECK. One
-- transaction, rolled back unless --apply. Nothing reads it from minty-shared v0.12 on.

ALTER TABLE ai_policy
  ADD COLUMN location VARCHAR(40) NOT NULL DEFAULT 'global',
  ADD CONSTRAINT ck_ai_policy_location CHECK (location ~ '^[a-z][a-z0-9-]*[a-z0-9]$');

SELECT 'ai_policy.location is back (global)' AS done;
