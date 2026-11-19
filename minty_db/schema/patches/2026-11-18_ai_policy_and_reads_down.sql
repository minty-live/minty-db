-- 2026-11-18: the way back from 2026-11-18_ai_policy_and_reads.sql. It forgets the AI policy, every
-- company's grants and every recorded read (the allowance starts again from nothing if the patch is
-- run again). One transaction, rolled back unless --apply. Run it only with the services back on a
-- minty-db before v0.13.

DROP TABLE ai_read;     -- with its indexes and foreign keys
DROP TABLE ai_grant;    -- with its indexes (uq_ai_grant_one_default included)
DROP TABLE ai_policy;   -- with trg_ai_policy_updated

SELECT 'ai_policy, ai_grant and ai_read removed' AS done;
