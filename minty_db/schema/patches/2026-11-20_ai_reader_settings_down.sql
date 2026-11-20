-- The way back from 2026-11-20_ai_reader_settings.sql: the readers' settings leave ai_policy (what
-- they held is lost). One transaction, rolled back unless --apply. Run it only with the services
-- back on minty-shared before v0.11, whose readers take these settings from their environment.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_reader_settings_down.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-20_ai_reader_settings_down.sql --apply

ALTER TABLE ai_policy
  DROP CONSTRAINT ck_ai_policy_timeout,
  DROP CONSTRAINT ck_ai_policy_output,
  DROP CONSTRAINT ck_ai_policy_thinking,
  DROP CONSTRAINT ck_ai_policy_file_size,
  DROP CONSTRAINT ck_ai_policy_location,
  DROP COLUMN receipt_reader_on,
  DROP COLUMN invoice_reader_on,
  DROP COLUMN timeout_s,
  DROP COLUMN max_output_tokens,
  DROP COLUMN thinking_level,
  DROP COLUMN max_file_mb,
  DROP COLUMN location;

SELECT 'ai_policy: the AI reader settings removed' AS done;
