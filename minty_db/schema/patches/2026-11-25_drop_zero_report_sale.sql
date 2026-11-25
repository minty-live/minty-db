-- 2026-11-25: a DATA clean-up, not a schema change (the user: "write only non-zero report_sale rows").
-- Run by hand on each database:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-25_drop_zero_report_sale.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-25_drop_zero_report_sale.sql --apply
--
-- The rule (minty-petty-cash-api, 2026-11-25): a Sales save writes a report_sale row only for a
-- method with an amount; a blank or 0 writes none, and clearing an amount deletes its row. Flask
-- and the older API wrote a 0 row for every method shown, so a third of the rows say nothing.
-- Every reader takes no row as 0 (the Sales page, the Daily Report and its share link, the Xero
-- sales invoice, the Petty Cash Report CSV, the deposit correction), so no report reads differently.
-- With them gone, a company's own method that only ever held zeros is deleted completely when the
-- company deletes it, instead of being switched off.
-- Run it AFTER the API that stops writing them is live, or an open draft saved by the old code adds
-- them again (harmless; run it again). No table references report_sale, and it has no trigger.
-- One transaction, rolled back unless --apply. Re-runnable: a second run deletes nothing. The
-- SELECTs are the report.

-- ---- before ---------------------------------------------------------------------------------

SELECT 'report_sale rows' AS check, count(*) AS rows, count(*) FILTER (WHERE amount = 0) AS zero_rows
  FROM report_sale;

SELECT 'company-own methods held only by zero rows' AS check, count(DISTINCT s.id) AS methods
  FROM sale_info s
 WHERE s.entity_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM report_sale r WHERE r.sale_id = s.id)
   AND NOT EXISTS (SELECT 1 FROM report_sale r WHERE r.sale_id = s.id AND r.amount <> 0);

-- ---- the clean-up ---------------------------------------------------------------------------

DELETE FROM report_sale WHERE amount = 0;

-- ---- after ----------------------------------------------------------------------------------

SELECT 'report_sale rows after' AS check, count(*) AS rows, count(*) FILTER (WHERE amount = 0) AS zero_rows
  FROM report_sale;
