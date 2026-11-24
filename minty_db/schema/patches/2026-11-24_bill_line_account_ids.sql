-- 2026-11-24: a DATA repair, not a schema change (the user: "backfill and also add this on the rehearse").
-- Run by hand on each database:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_bill_line_account_ids.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_bill_line_account_ids.sql --apply
--
-- The rule (the user, 2026-11-24): a record keeps its account and supplier by id, and every screen
-- and download reads the code and name from the chart now; the text copies are kept in step too.
-- What was wrong: bill_line.account_id (minty-db v0.5, 2026-11-10) is filled only by a save, so the
-- bills the v2->v3 load brought (1,548 of 1,552 lines on local postgres) name their account by code
-- only, and their text still says what it said when they were made.
--   1. a line with a code and no account gets the company's account with that code: an active one
--      first (Xero's code before Minty's own), else one merged away (its kept account), else any;
--   2. a line on an account merged away moves to the kept account (merges already move them; this
--      catches any left);
--   3. every line on an account takes its code (when it fits 20) and name now, published or not;
--   4. each bill's header code is its first line's code; each bill's supplier name is its supplier's.
-- No Xero call; what was sent to Xero (published_*) is untouched. Steps 3-4 change a row only when
-- its text differs (the updated_at trigger then stamps it: the tracker's "latest bill update" moves
-- for those companies, and a kept edit draft of such a bill is dropped, as for any change).
-- One transaction, rolled back unless --apply. Re-runnable: a second run changes nothing. The SELECTs
-- are the report. Minty's load runs the same statements at the end of 03 (gen.py BILL_ACCOUNTS).

-- ---- before ---------------------------------------------------------------------------------

SELECT 'bill lines with a code and no account' AS check, count(*) AS lines FROM bill_line l
 WHERE l.account_id IS NULL AND btrim(coalesce(l.account_code, '')) <> '';

-- ---- 1. by the code, in the same company -----------------------------------------------------

UPDATE bill_line l SET account_id = m.account_id
  FROM (SELECT DISTINCT ON (l2.id) l2.id AS line_id, coalesce(a.merged_into_id, a.id) AS account_id
          FROM bill_line l2
          JOIN bill b ON b.id = l2.bill_id
          JOIN account_info a
            ON a.entity_id = b.entity_id
           AND (a.xero_code = btrim(l2.account_code) OR a.code = btrim(l2.account_code))
         WHERE l2.account_id IS NULL AND btrim(coalesce(l2.account_code, '')) <> ''
         ORDER BY l2.id,
                  (a.record_status = 'active' AND a.status = 'ACTIVE') DESC,
                  (a.merged_into_id IS NOT NULL) DESC,
                  (a.xero_code = btrim(l2.account_code)) DESC,
                  a.created_at, a.id) m
 WHERE l.id = m.line_id;

-- ---- 2. off an account merged away ----------------------------------------------------------

UPDATE bill_line l SET account_id = a.merged_into_id
  FROM account_info a
 WHERE a.id = l.account_id AND a.merged_into_id IS NOT NULL;

-- ---- 3. each line's text is its account's now ------------------------------------------------

UPDATE bill_line l
   SET account_code = CASE WHEN length(a.now_code) BETWEEN 1 AND 20 THEN a.now_code ELSE l.account_code END,
       account_name = a.now_name
  FROM (SELECT id, btrim(coalesce(nullif(btrim(xero_code), ''), code, '')) AS now_code,
               left(coalesce(name, ''), 150) AS now_name
          FROM account_info) a
 WHERE a.id = l.account_id
   AND (l.account_name IS DISTINCT FROM a.now_name
        OR (length(a.now_code) BETWEEN 1 AND 20 AND l.account_code IS DISTINCT FROM a.now_code));

-- ---- 4. each bill's header code and supplier name --------------------------------------------

UPDATE bill b SET xero_account_code = f.account_code
  FROM (SELECT DISTINCT ON (l.bill_id) l.bill_id, l.account_code
          FROM bill_line l
         WHERE l.account_id IS NOT NULL AND btrim(coalesce(l.account_code, '')) <> ''
         ORDER BY l.bill_id, l.sort_order, l.created_at, l.id) f
 WHERE b.id = f.bill_id AND b.xero_account_code IS DISTINCT FROM f.account_code;

UPDATE bill b SET contact_name = left(c.name, 100)
  FROM xero_contact_sync c
 WHERE c.id = b.contact_id AND btrim(coalesce(c.name, '')) <> ''
   AND b.contact_name IS DISTINCT FROM left(c.name, 100);

-- ---- after ----------------------------------------------------------------------------------

SELECT 'bill lines with a code and no account after (shown by their text)' AS check, count(*) AS lines
  FROM bill_line l
 WHERE l.account_id IS NULL AND btrim(coalesce(l.account_code, '')) <> '';
