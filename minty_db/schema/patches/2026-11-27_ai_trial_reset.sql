-- 2026-11-27 (the user): every company starts again on a fresh AI trial. A DATA change, no schema
-- change and no version bump; it needs 2026-11-27_ai_grant_cycles.sql (minty-db v0.22) first.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_trial_reset.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_ai_trial_reset.sql --apply
--
-- 1. ai_policy: default_grant is the AI trial (280,000 tokens, 30 days), cycle_tokens each billing
--    period's grant after it (280,000, about HK$20 of Flash-Lite), no extra caps.
-- 2. Every one-time 'default' grant still open is ended now (kept as the record, with its reads).
-- 3. Every company not archived and without a trial gets one: 280,000 tokens for 30 days from now.
--    A company made later gets its trial from its first module subscription (minty-shared v0.28).
--
-- Old code (minty-shared before v0.28) just counts the trial rows as grants, so this can run before
-- the services move to v0.28. Re-runnable: a second run ends and gives nothing (the policy UPDATE
-- writes the same values). The way back is by hand: the trial rows carry note 'AI trial reset
-- 2026-11-27', the ended default grants ended_by 'AI trial reset 2026-11-27'.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = current_schema() AND table_name = 'ai_policy'
                   AND column_name = 'cycle_tokens') THEN
    RAISE EXCEPTION 'ai_policy.cycle_tokens is missing: apply 2026-11-27_ai_grant_cycles.sql first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ai_policy WHERE id = 1) THEN
    RAISE EXCEPTION 'ai_policy has no row: load seed_catalogue.sql first';
  END IF;
END $$;

SELECT
  (SELECT count(*) FROM ai_grant
    WHERE source = 'default' AND ended_at IS NULL AND (expires_at IS NULL OR expires_at > now()))
    AS default_grants_to_end,
  (SELECT count(*) FROM entities e
    WHERE e.archived_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM ai_grant g WHERE g.entity_id = e.id AND g.source = 'trial'))
    AS trials_to_give;

UPDATE ai_policy
   SET default_grant = '{"tokens": 280000, "days": 30}',
       cycle_tokens  = 280000,
       limit_rules   = '[]',
       updated_by    = '2026-11-27_ai_trial_reset.sql'
 WHERE id = 1;

UPDATE ai_grant
   SET expires_at = now(), ended_at = now(), ended_by = 'AI trial reset 2026-11-27'
 WHERE source = 'default' AND ended_at IS NULL AND (expires_at IS NULL OR expires_at > now());

INSERT INTO ai_grant (entity_id, tokens_total, expires_at, source, granted_by, note)
SELECT e.id, 280000, now() + interval '30 days', 'trial', 'ai_policy', 'AI trial reset 2026-11-27'
  FROM entities e
 WHERE e.archived_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM ai_grant g WHERE g.entity_id = e.id AND g.source = 'trial');

SELECT
  (SELECT count(*) FROM ai_grant
    WHERE source = 'default' AND ended_at IS NULL AND (expires_at IS NULL OR expires_at > now()))
    AS default_grants_open,
  (SELECT count(*) FROM ai_grant WHERE source = 'trial') AS trial_grants,
  (SELECT default_grant::text || ' / ' || cycle_tokens FROM ai_policy WHERE id = 1) AS policy;
