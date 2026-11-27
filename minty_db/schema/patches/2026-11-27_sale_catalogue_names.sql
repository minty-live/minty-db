-- 2026-11-27: Minty's sales-method catalogue (sale_info rows with entity_id NULL), the user's calls:
--   1. "Payme" takes the brand's spelling "PayMe", "Food Panda" takes "Foodpanda";
--   2. "Deliveroo" (switched off, on no report) is deleted, and any company's link to it with it;
--   3. "Bank Transfer" (electronic, bank_transfer_sales) is added: Auto Fill offers it to a retail
--      shop, a service or a general business, and links Minty's row by name instead of making a
--      company's own copy. No company had one;
--   4. a company's own row whose name is a Minty name with case, spaces and punctuation ignored
--      ("Pay me", "WeChatPay") merges into Minty's row: its links move (one per company, on if
--      either was) and its report rows move (one per report, summed). Renaming it in place would
--      give the company two methods of one name.
-- value_name of Minty's rows is unchanged, so every amount stays where it is. Nothing reaches Xero:
-- a publish sends Cash / Electronic / Delivery totals, never a method's name.
-- Data only, no version bump. Re-runnable (a second run changes nothing).
-- Minty's docs/schema/05_sale_catalogue_names.sql runs the same in rehearse.py - KEEP THE TWO IN STEP.
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_sale_catalogue_names.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-27_sale_catalogue_names.sql --apply
--
-- The way back: the two renames swapped, Deliveroo re-inserted (type delivery, value_name
-- deliveroo_sales, display_order 4, enabled false), Bank Transfer deleted while no company links
-- it. A merge (4) is not undone.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM sale_info s
              WHERE s.entity_id IS NULL AND s.value_name = 'deliveroo_sales'
                AND EXISTS (SELECT 1 FROM report_sale r WHERE r.sale_id = s.id)) THEN
    RAISE EXCEPTION 'Minty''s Deliveroo row is in use: a report holds an amount for it';
  END IF;
END $$;

-- 1. the brands' spellings
UPDATE sale_info SET sale_name = 'PayMe'
 WHERE entity_id IS NULL AND value_name = 'payme_sales' AND sale_name = 'Payme';
UPDATE sale_info SET sale_name = 'Foodpanda'
 WHERE entity_id IS NULL AND value_name = 'foodpanda_sales' AND sale_name = 'Food Panda';

-- 2. Deliveroo: a company that switched it on loses it from its list (the user, 2026-11-27: one
--    company on production, no amounts)
DELETE FROM entity_sale_setting e USING sale_info s
 WHERE e.sale_id = s.id AND s.entity_id IS NULL AND s.value_name = 'deliveroo_sales';
DELETE FROM sale_info WHERE entity_id IS NULL AND value_name = 'deliveroo_sales';

-- 3. Bank Transfer
INSERT INTO sale_info (type, sale_name, value_name, display_order, enabled)
SELECT 'electronic', 'Bank Transfer', 'bank_transfer_sales', 8, TRUE
 WHERE NOT EXISTS (SELECT 1 FROM sale_info WHERE entity_id IS NULL AND lower(sale_name) = 'bank transfer');

-- 4. a company's own spelling of a Minty name merges into Minty's row
DROP TABLE IF EXISTS name_twin, rs_merge;
CREATE TEMP TABLE name_twin ON COMMIT DROP AS
SELECT o.id AS own_id, o.entity_id, m.id AS minty_id
  FROM sale_info o
  JOIN sale_info m ON m.entity_id IS NULL
   AND lower(regexp_replace(m.sale_name, '[^[:alnum:]]', '', 'g'))
     = lower(regexp_replace(o.sale_name, '[^[:alnum:]]', '', 'g'))
 WHERE o.entity_id IS NOT NULL;

-- report rows: one per report and method, summed
CREATE TEMP TABLE rs_merge ON COMMIT DROP AS
SELECT r.report_id, t.minty_id, sum(r.amount) AS amount
  FROM report_sale r
  JOIN name_twin t ON r.sale_id IN (t.own_id, t.minty_id)
  JOIN report rep ON rep.id = r.report_id AND rep.entity_id = t.entity_id
 GROUP BY r.report_id, t.minty_id
HAVING bool_or(r.sale_id = t.own_id);
DELETE FROM report_sale r USING rs_merge m
 WHERE r.report_id = m.report_id AND r.sale_id = m.minty_id;
UPDATE report_sale r SET sale_id = t.minty_id, amount = m.amount
  FROM name_twin t, rs_merge m
 WHERE r.sale_id = t.own_id AND m.report_id = r.report_id AND m.minty_id = t.minty_id;

-- links: one per company, on if either was
UPDATE entity_sale_setting e SET is_active = true
  FROM name_twin t
 WHERE e.entity_id = t.entity_id AND e.sale_id = t.minty_id
   AND EXISTS (SELECT 1 FROM entity_sale_setting x
                WHERE x.entity_id = t.entity_id AND x.sale_id = t.own_id AND x.is_active);
DELETE FROM entity_sale_setting e USING name_twin t
 WHERE e.entity_id = t.entity_id AND e.sale_id = t.own_id
   AND EXISTS (SELECT 1 FROM entity_sale_setting x WHERE x.entity_id = t.entity_id AND x.sale_id = t.minty_id);
UPDATE entity_sale_setting e SET sale_id = t.minty_id
  FROM name_twin t
 WHERE e.entity_id = t.entity_id AND e.sale_id = t.own_id;

DELETE FROM sale_info s USING name_twin t WHERE s.id = t.own_id;

DO $$
DECLARE merged INT;
BEGIN
  SELECT count(*) INTO merged FROM name_twin;
  RAISE NOTICE 'S2  sale catalogue: PayMe, Foodpanda, Bank Transfer; Deliveroo gone; % company spelling(s) merged', merged;
END $$;
