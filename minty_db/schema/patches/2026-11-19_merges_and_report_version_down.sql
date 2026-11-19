-- 2026-11-19: the way back from 2026-11-19_merges_and_report_version.sql. It forgets every merge's
-- record of what moved (the moved records stay where the merges put them, and the merged rows stay
-- archived with merged_into_id) and every report's edit version. One transaction, rolled back unless
-- --apply. Run it only with the services back on a minty-db before v0.14.

DROP TABLE minty_merge_record;  -- with its index and foreign key
DROP TABLE minty_merge;         -- with its indexes
ALTER TABLE report
  DROP CONSTRAINT ck_report_edit_version,
  DROP CONSTRAINT fk_report_saved_by,
  DROP COLUMN saved_by_user_id,
  DROP COLUMN edit_version;

SELECT 'minty_merge, minty_merge_record and report.edit_version / saved_by_user_id removed' AS done;
