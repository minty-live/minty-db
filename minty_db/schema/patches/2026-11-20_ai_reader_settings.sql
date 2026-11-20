-- 2026-11-20: ai_policy gains the readers' settings (owner) - the two readers' on/off switches,
-- the call's timeout, the reply's token budget, the thinking level, the largest document and the
-- Vertex AI region - for a database already recorded at 0001. They were each service's environment
-- (EXPENSE_AI_* / BILL_AI_* / AI_LOCATION); the services read them from this row from minty-shared
-- v0.11.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_reader_settings.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_reader_settings.sql --apply
--
-- The row keeps what the services ran with on 2026-11-20: both readers ON, 25 s, 4096 tokens, 'low',
-- 10 MB, and the region asia-southeast1. Old code ignores the new columns, so the patch can go first.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'ai_policy'
               AND column_name = 'receipt_reader_on') THEN
    RAISE EXCEPTION 'the AI reader settings are already in this schema';
  END IF;
END $$;

ALTER TABLE ai_policy
  ADD COLUMN receipt_reader_on BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN invoice_reader_on BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN timeout_s         INTEGER     NOT NULL DEFAULT 25,
  ADD COLUMN max_output_tokens INTEGER     NOT NULL DEFAULT 4096,
  ADD COLUMN thinking_level    VARCHAR(10) NOT NULL DEFAULT 'low',
  ADD COLUMN max_file_mb       INTEGER     NOT NULL DEFAULT 10,
  ADD COLUMN location          VARCHAR(40) NOT NULL DEFAULT 'asia-southeast1',
  ADD CONSTRAINT ck_ai_policy_timeout     CHECK (timeout_s BETWEEN 5 AND 120),
  ADD CONSTRAINT ck_ai_policy_output      CHECK (max_output_tokens BETWEEN 256 AND 65536),
  ADD CONSTRAINT ck_ai_policy_thinking    CHECK (thinking_level IN ('minimal', 'low', 'medium', 'high')),
  ADD CONSTRAINT ck_ai_policy_file_size   CHECK (max_file_mb BETWEEN 1 AND 20),
  ADD CONSTRAINT ck_ai_policy_location    CHECK (location ~ '^[a-z][a-z0-9-]*[a-z0-9]$');

UPDATE ai_policy SET receipt_reader_on = true, invoice_reader_on = true,
                     updated_by = '2026-11-20_ai_reader_settings.sql'
 WHERE id = 1;

SELECT id, primary_model, backup_model, receipt_reader_on, invoice_reader_on, timeout_s,
       max_output_tokens, thinking_level, max_file_mb, location FROM ai_policy;
