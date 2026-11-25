-- 2026-11-25: a DATA fix, not a schema change - the notes and coins of USD, SGD and KRW.
-- Run by hand on each database (Supabase only on the owner's yes):
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-25_cash_denominations_usd_sgd_krw.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-25_cash_denominations_usd_sgd_krw.sql --apply
--
-- cash_info held rows for HKD only, while HKD, SGD, USD and KRW are the four active currencies
-- (2026-11-04). A company on any of the other three got an empty Cash Count calculator and
-- petty-cash-api logged "No active denominations" on every Cash Count page (Company of Friends, USD).
--
-- The rows follow HKD's: notes then coins, display_order from 1, cash_name the plain figure with no
-- symbol (the calculator shows "USD 0.50", "KRW 50,000"; lib/cash.ts denominationLabel), the
-- description "<CODE> <figure> note|coin". Only denominations in everyday circulation: no USD $2
-- note, 50c or $1 coin, no SGD $1,000 / $10,000 note (withdrawn from issue), no KRW 1/5 won.
-- cash_info's key is (currency_id, cash_value), so a value is either a note or a coin (USD $1 = note).
-- A company switches any of them off in its own entity_cash_setting.
--
-- Currencies are found by code (ids differ per database); a missing currency inserts nothing for it.
-- ON CONFLICT DO NOTHING: an existing row is never changed, so a re-run inserts nothing.
-- One transaction, rolled back unless --apply. The SELECTs are the report.

-- ---- before ---------------------------------------------------------------------------------

SELECT 'denominations per currency' AS check, cu.currency_code, count(ci.id) AS rows
  FROM currency_info cu
  LEFT JOIN cash_info ci ON ci.currency_id = cu.id
 WHERE cu.currency_code IN ('HKD', 'USD', 'SGD', 'KRW')
 GROUP BY cu.currency_code ORDER BY cu.currency_code;

-- ---- the rows -------------------------------------------------------------------------------

INSERT INTO cash_info (currency_id, type, cash_value, cash_name, description, is_active, display_order)
SELECT cu.id, v.type::cash_type, v.cash_value, v.cash_name,
       cu.currency_code || ' ' || v.cash_name || ' ' || v.type, TRUE, v.display_order
  FROM (VALUES
        ('USD', 'note',   100.00, '100',     1),
        ('USD', 'note',    50.00, '50',      2),
        ('USD', 'note',    20.00, '20',      3),
        ('USD', 'note',    10.00, '10',      4),
        ('USD', 'note',     5.00, '5',       5),
        ('USD', 'note',     1.00, '1',       6),
        ('USD', 'coin',     0.25, '0.25',    7),
        ('USD', 'coin',     0.10, '0.10',    8),
        ('USD', 'coin',     0.05, '0.05',    9),
        ('USD', 'coin',     0.01, '0.01',   10),

        ('SGD', 'note',   100.00, '100',     1),
        ('SGD', 'note',    50.00, '50',      2),
        ('SGD', 'note',    10.00, '10',      3),
        ('SGD', 'note',     5.00, '5',       4),
        ('SGD', 'note',     2.00, '2',       5),
        ('SGD', 'coin',     1.00, '1',       6),
        ('SGD', 'coin',     0.50, '0.50',    7),
        ('SGD', 'coin',     0.20, '0.20',    8),
        ('SGD', 'coin',     0.10, '0.10',    9),
        ('SGD', 'coin',     0.05, '0.05',   10),

        ('KRW', 'note', 50000.00, '50,000',  1),
        ('KRW', 'note', 10000.00, '10,000',  2),
        ('KRW', 'note',  5000.00, '5,000',   3),
        ('KRW', 'note',  1000.00, '1,000',   4),
        ('KRW', 'coin',   500.00, '500',     5),
        ('KRW', 'coin',   100.00, '100',     6),
        ('KRW', 'coin',    50.00, '50',      7),
        ('KRW', 'coin',    10.00, '10',      8)
       ) AS v(code, type, cash_value, cash_name, display_order)
  JOIN currency_info cu ON cu.currency_code = v.code
ON CONFLICT (currency_id, cash_value) DO NOTHING;

-- ---- after ----------------------------------------------------------------------------------

SELECT 'denominations per currency after' AS check, cu.currency_code, count(ci.id) AS rows,
       count(ci.id) FILTER (WHERE ci.is_active) AS active
  FROM currency_info cu
  LEFT JOIN cash_info ci ON ci.currency_id = cu.id
 WHERE cu.currency_code IN ('HKD', 'USD', 'SGD', 'KRW')
 GROUP BY cu.currency_code ORDER BY cu.currency_code;

SELECT 'live companies still with an empty calculator' AS check, cu.currency_code, count(*) AS companies
  FROM entities e
  LEFT JOIN country_info co ON co.country_code = e.country_code
  JOIN currency_info cu ON cu.id = COALESCE(e.currency_id, co.currency_id)
 WHERE e.archived_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM cash_info ci WHERE ci.currency_id = cu.id AND ci.is_active)
 GROUP BY cu.currency_code ORDER BY cu.currency_code;
