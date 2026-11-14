-- ============================================================================
-- analysis.sql : Card Transaction Fraud Detection (EDA), aggregation queries, version 2
-- Platform : Google BigQuery (Standard SQL)
-- Reads    : `fraud.clean` (built by cleaning.sql) and, for query 0 only,
--            the raw tables `fraud.transactions` and `fraud.identity`
-- Output   : run each query on its own and save the result as the CSV named
--            in its header, in the repository root (next to analysis.R)
--
-- Changes from v1
--   * Query 1 now exports lift_vs_overall (product rate divided by overall rate)
--   * Query 3 now exports frauds as well, so totals can be weighted
--   * Query 7 now exports txns and frauds for every heatmap cell
--   * Query 8 keeps credit and debit only (removes empty chart panels)
--   * Query 9 replaces the 15% row level sample with histogram bins
--     computed in SQL (reproducible, and no raw rows are published)
--   * Queries 0 and 10 to 14 are new
--
-- Note on time: TransactionDT is an offset in seconds from an undisclosed
-- reference point, so hour_of_day and day_index are relative values,
-- not local clock time and not real weekdays.
-- ============================================================================


-- 0) Data validation  ->  validation_checks.csv
--    Confirms the LEFT JOIN kept exactly one row per transaction and
--    documents missing values in the fields used by the analysis.
WITH raw_txn AS (
  SELECT
    COUNT(*)                      AS transaction_rows,
    COUNT(DISTINCT TransactionID) AS transaction_ids
  FROM `fraud.transactions`
),
raw_identity AS (
  SELECT
    COUNT(*)                      AS identity_rows,
    COUNT(DISTINCT TransactionID) AS identity_ids
  FROM `fraud.identity`
),
clean_checks AS (
  SELECT
    COUNT(*)                        AS clean_rows,
    COUNT(DISTINCT TransactionID)   AS clean_ids,
    COUNTIF(TransactionAmt IS NULL) AS null_amount,
    COUNTIF(card_type IS NULL)      AS null_card_type,
    COUNTIF(email_domain IS NULL)   AS null_email_domain,
    COUNTIF(DeviceType IS NULL)     AS null_device_type,
    COUNT(DISTINCT day_index)       AS distinct_days,
    MIN(TransactionAmt)             AS min_amount,
    MAX(TransactionAmt)             AS max_amount
  FROM `fraud.clean`
)
SELECT *
FROM raw_txn
CROSS JOIN raw_identity
CROSS JOIN clean_checks;


-- 1) Fraud by product  ->  fraud_by_product.csv   (now includes lift_vs_overall)
--    lift_vs_overall = product fraud rate divided by the overall fraud rate
SELECT
  ProductCD,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(SUM(isFraud) / SUM(SUM(isFraud)) OVER () * 100, 1) AS share_of_all_fraud_pct,
  ROUND(AVG(isFraud) / (SUM(SUM(isFraud)) OVER () / SUM(COUNT(*)) OVER ()), 2) AS lift_vs_overall,
  RANK() OVER (ORDER BY AVG(isFraud) DESC) AS risk_rank
FROM `fraud.clean`
GROUP BY ProductCD
ORDER BY fraud_rate_pct DESC;


-- 2) Fraud by card network and type  ->  fraud_by_card.csv   (unchanged)
SELECT
  card_network, card_type,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY card_network, card_type
ORDER BY fraud_rate_pct DESC;


-- 3) Fraud by relative hour  ->  by_hour.csv   (now includes frauds)
SELECT
  hour_of_day,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- 4) Fraud by amount band  ->  fraud_by_amount.csv   (unchanged)
SELECT
  amt_bucket,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(AVG(TransactionAmt), 2) AS avg_amt
FROM `fraud.clean`
GROUP BY amt_bucket
ORDER BY amt_bucket;


-- 5) Fraud by email domain, 500 or more txns  ->  fraud_by_email.csv   (unchanged)
SELECT
  email_domain,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
WHERE email_domain IS NOT NULL
GROUP BY email_domain
HAVING COUNT(*) >= 500
ORDER BY fraud_rate_pct DESC
LIMIT 15;


-- 6) Fraud by device type  ->  fraud_by_device.csv   (unchanged)
--    'unknown' = no identity record, or identity record without DeviceType
SELECT
  COALESCE(DeviceType, 'unknown') AS device_type,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY device_type
ORDER BY fraud_rate_pct DESC;


-- 7) Relative hour by 7 day cycle heatmap  ->  heatmap.csv   (now includes txns, frauds)
SELECT
  hour_of_day,
  MOD(day_index, 7) AS weekday_proxy,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY hour_of_day, weekday_proxy
ORDER BY weekday_proxy, hour_of_day;


-- 8) Product by card type, credit and debit only  ->  by_product_card.csv
--    The other card types hold 45 transactions in total and produced empty panels.
SELECT
  card_type, ProductCD,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
WHERE card_type IN ('credit', 'debit')
GROUP BY card_type, ProductCD
ORDER BY card_type, fraud_rate_pct DESC;


-- 9) Optional: amount histogram bins on a log10 scale  ->  amount_hist_bins.csv
--    Only needed if a distribution chart is added back; analysis.R does not
--    use it. Replaces amount_sample.csv. Bin width is 0.05 in log10 units
--    (20 bins per tenfold change in amount). Fully reproducible.
SELECT
  isFraud,
  ROUND(FLOOR(LOG10(TransactionAmt) * 20) / 20, 2) AS log10_bin_start,
  COUNT(*) AS txns
FROM `fraud.clean`
WHERE TransactionAmt > 0
GROUP BY isFraud, log10_bin_start
ORDER BY isFraud, log10_bin_start;


-- 10) Overall KPIs  ->  overall_kpis.csv
--     Weighted overall rate and the exact fraud amount (for README and dashboard).
SELECT
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(SUM(isFraud) / COUNT(*) * 100, 2) AS fraud_rate_pct,
  ROUND(SUM(TransactionAmt), 2) AS total_amount_usd,
  ROUND(SUM(IF(isFraud = 1, TransactionAmt, 0)), 2) AS fraud_amount_usd,
  ROUND(SUM(IF(isFraud = 1, TransactionAmt, 0)) / SUM(TransactionAmt) * 100, 2) AS fraud_amount_pct
FROM `fraud.clean`;


-- 11) Amount bands with dollar exposure  ->  fraud_by_amount_usd.csv
--     Count based rates can hide where the money is lost.
SELECT
  amt_bucket,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(SUM(isFraud) / SUM(SUM(isFraud)) OVER () * 100, 1) AS share_of_fraud_cases_pct,
  ROUND(SUM(IF(isFraud = 1, TransactionAmt, 0)), 2) AS fraud_amount_usd,
  ROUND(SUM(IF(isFraud = 1, TransactionAmt, 0))
        / SUM(SUM(IF(isFraud = 1, TransactionAmt, 0))) OVER () * 100, 1) AS share_of_fraud_usd_pct,
  ROUND(AVG(IF(isFraud = 1, TransactionAmt, NULL)), 2) AS avg_fraud_amount_usd
FROM `fraud.clean`
GROUP BY amt_bucket
ORDER BY amt_bucket;


-- 12) Relative hour windows  ->  hour_windows.csv
--     Exact volume share, fraud share and lift for the windows in Recommendation 2.
WITH windows AS (
  SELECT 'offset hours 7 to 8' AS hour_window, 7 AS hour_from, 8 AS hour_to
  UNION ALL
  SELECT 'offset hours 5 to 9', 5, 9
),
totals AS (
  SELECT COUNT(*) AS all_txns, SUM(isFraud) AS all_frauds
  FROM `fraud.clean`
)
SELECT
  w.hour_window,
  COUNT(*) AS txns,
  SUM(c.isFraud) AS frauds,
  ROUND(AVG(c.isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(COUNT(*) / ANY_VALUE(t.all_txns) * 100, 2) AS share_of_volume_pct,
  ROUND(SUM(c.isFraud) / ANY_VALUE(t.all_frauds) * 100, 2) AS share_of_fraud_pct,
  ROUND(AVG(c.isFraud) / (ANY_VALUE(t.all_frauds) / ANY_VALUE(t.all_txns)), 2) AS lift_vs_overall,
  ROUND(COUNT(*) / COUNT(DISTINCT c.day_index), 1) AS avg_txns_per_day
FROM `fraud.clean` AS c
CROSS JOIN windows AS w
CROSS JOIN totals AS t
WHERE c.hour_of_day BETWEEN w.hour_from AND w.hour_to
GROUP BY w.hour_window
ORDER BY w.hour_window;


-- 13) Rule scorecard: precision versus recall  ->  rule_scorecard.csv
--     For each candidate rule: how many transactions it would flag (alerts,
--     the customer friction side), how many of those are fraud (precision),
--     and what share of all fraud cases and fraud dollars it catches (recall).
WITH flags AS (
  SELECT
    isFraud,
    TransactionAmt,
    IFNULL(ProductCD = 'C', FALSE)                             AS r_product_c,
    IFNULL(ProductCD = 'C' AND card_type = 'credit', FALSE)    AS r_product_c_credit,
    IFNULL(DeviceType = 'mobile', FALSE)                       AS r_mobile,
    IFNULL(email_domain IN ('mail.com', 'outlook.com'), FALSE) AS r_risky_email,
    IFNULL(amt_bucket = '04: 250-1000', FALSE)                 AS r_amount_250_1000,
    IFNULL(hour_of_day BETWEEN 5 AND 9, FALSE)                 AS r_offset_hours_5_9
  FROM `fraud.clean`
),
rules AS (
  SELECT
    f.isFraud,
    f.TransactionAmt,
    r.rule_name,
    r.hit
  FROM flags AS f,
  UNNEST(ARRAY<STRUCT<rule_name STRING, hit BOOL>>[
    ('Product C', f.r_product_c),
    ('Product C on credit card', f.r_product_c_credit),
    ('Mobile device', f.r_mobile),
    ('Email mail.com or outlook.com', f.r_risky_email),
    ('Amount 250 to 1000 USD', f.r_amount_250_1000),
    ('Offset hours 5 to 9', f.r_offset_hours_5_9),
    ('Two or more of: Product C, mobile, risky email',
      CAST(f.r_product_c AS INT64) + CAST(f.r_mobile AS INT64)
        + CAST(f.r_risky_email AS INT64) >= 2)
  ]) AS r
)
SELECT
  rule_name,
  COUNTIF(hit) AS alerts,
  ROUND(COUNTIF(hit) / COUNT(*) * 100, 2) AS alert_rate_pct,
  COUNTIF(hit AND isFraud = 1) AS frauds_caught,
  ROUND(SAFE_DIVIDE(COUNTIF(hit AND isFraud = 1), COUNTIF(hit)) * 100, 2) AS precision_pct,
  ROUND(COUNTIF(hit AND isFraud = 1) / SUM(isFraud) * 100, 2) AS recall_pct,
  ROUND(SUM(IF(hit AND isFraud = 1, TransactionAmt, 0))
        / SUM(IF(isFraud = 1, TransactionAmt, 0)) * 100, 2) AS recall_usd_pct
FROM rules
GROUP BY rule_name
ORDER BY precision_pct DESC;


-- 14) Product by device type  ->  product_by_device.csv
--     Checks whether the device signal adds information beyond product type
--     (identity data, including DeviceType, may not be collected evenly across products).
SELECT
  ProductCD,
  COALESCE(DeviceType, 'unknown') AS device_type,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY ProductCD, device_type
ORDER BY ProductCD, device_type;
