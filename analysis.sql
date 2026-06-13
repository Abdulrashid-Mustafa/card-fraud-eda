-- ============================================================================
-- analysis.sql  —  Aggregation queries (run after cleaning.sql)
-- Platform: Google BigQuery (Standard SQL)
-- Each query exports to a CSV in /data used by analysis.R and the dashboard.
-- ============================================================================

-- 1) Fraud by product  ->  data/fraud_by_product.csv
--    Uses window functions for share-of-total and a risk rank.
SELECT
  ProductCD,
  COUNT(*) AS txns,
  SUM(isFraud) AS frauds,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(SUM(isFraud) / SUM(SUM(isFraud)) OVER () * 100, 1) AS share_of_all_fraud_pct,
  RANK() OVER (ORDER BY AVG(isFraud) DESC) AS risk_rank
FROM `fraud.clean`
GROUP BY ProductCD
ORDER BY fraud_rate_pct DESC;

-- 2) Fraud by card network + type  ->  data/fraud_by_card.csv
SELECT
  card_network, card_type,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY card_network, card_type
ORDER BY fraud_rate_pct DESC;

-- 3) Fraud by hour of day  ->  data/by_hour.csv
SELECT
  hour_of_day,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- 4) Fraud by amount bucket  ->  data/fraud_by_amount.csv
SELECT
  amt_bucket,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  ROUND(AVG(TransactionAmt), 2) AS avg_amt
FROM `fraud.clean`
GROUP BY amt_bucket
ORDER BY amt_bucket;

-- 5) Fraud by email domain (>= 500 txns)  ->  data/fraud_by_email.csv
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

-- 6) Fraud by device type  ->  data/fraud_by_device.csv
SELECT
  COALESCE(DeviceType, 'unknown') AS device_type,
  COUNT(*) AS txns,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY device_type
ORDER BY fraud_rate_pct DESC;

-- 7) Hour x weekday-proxy heatmap  ->  data/heatmap.csv
SELECT
  hour_of_day,
  MOD(day_index, 7) AS weekday_proxy,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM `fraud.clean`
GROUP BY hour_of_day, weekday_proxy
ORDER BY weekday_proxy, hour_of_day;

-- 8) Product x card type  ->  data/by_product_card.csv
SELECT
  card_type, ProductCD,
  ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct,
  COUNT(*) AS txns
FROM `fraud.clean`
WHERE card_type IS NOT NULL
GROUP BY card_type, ProductCD;

-- 9) Amount sample for the histogram (15% random sample)  ->  data/amount_sample.csv
SELECT isFraud, TransactionAmt
FROM `fraud.clean`
WHERE TransactionAmt IS NOT NULL AND RAND() < 0.15;
