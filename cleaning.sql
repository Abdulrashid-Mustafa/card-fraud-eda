-- ============================================================================
-- cleaning.sql  —  Card Transaction Fraud Detection (EDA)
-- Platform: Google BigQuery (Standard SQL)
-- Purpose : Join the transaction + identity tables and derive the analysis
--           fields (hour-of-day, day index, amount buckets) into one clean
--           table that every downstream aggregation reads from.
-- ============================================================================

CREATE OR REPLACE TABLE `fraud.clean` AS
SELECT
  t.TransactionID,
  t.isFraud,
  t.TransactionAmt,
  t.ProductCD,
  t.card4 AS card_network,
  t.card6 AS card_type,
  t.P_emaildomain AS email_domain,
  i.DeviceType,

  -- Derive hour of day (0–23) from the TransactionDT seconds offset
  DIV(MOD(CAST(t.TransactionDT AS INT64), 86400), 3600) AS hour_of_day,

  -- Derive a relative day index (used to build a weekday proxy: MOD(day_index, 7))
  DIV(CAST(t.TransactionDT AS INT64), 86400) AS day_index,

  -- Bucket the transaction amount into interpretable bands
  CASE
    WHEN t.TransactionAmt < 50   THEN '01: <50'
    WHEN t.TransactionAmt < 100  THEN '02: 50-100'
    WHEN t.TransactionAmt < 250  THEN '03: 100-250'
    WHEN t.TransactionAmt < 1000 THEN '04: 250-1000'
    ELSE '05: 1000+'
  END AS amt_bucket

FROM `fraud.transactions` t
LEFT JOIN `fraud.identity` i
  ON t.TransactionID = i.TransactionID;
