-- 01_clean.sql
-- Builds an analysis-ready table from the raw upload.
-- Sandbox-safe: uses CREATE TABLE AS SELECT (DDL), no INSERT/UPDATE/DELETE (DML is blocked in the sandbox).
-- Replace `churn_project` with your dataset name if different.

CREATE OR REPLACE TABLE `churn_project.customers_clean` AS
SELECT
  customerID                                   AS customer_id,
  gender,
  CAST(SeniorCitizen AS INT64)                 AS senior_citizen,
  Partner                                      AS partner,
  Dependents                                   AS dependents,
  CAST(tenure AS INT64)                        AS tenure_months,
  PhoneService                                 AS phone_service,
  MultipleLines                                AS multiple_lines,
  InternetService                              AS internet_service,
  OnlineSecurity                               AS online_security,
  OnlineBackup                                 AS online_backup,
  DeviceProtection                             AS device_protection,
  TechSupport                                  AS tech_support,
  StreamingTV                                  AS streaming_tv,
  StreamingMovies                              AS streaming_movies,
  Contract                                     AS contract,
  PaperlessBilling                             AS paperless_billing,
  PaymentMethod                                AS payment_method,
  CAST(MonthlyCharges AS FLOAT64)              AS monthly_charges,
  -- 11 brand-new customers have a blank TotalCharges; they haven't been billed yet, so 0 is correct
  COALESCE(SAFE_CAST(NULLIF(TRIM(CAST(TotalCharges AS STRING)), '') AS FLOAT64), 0) AS total_charges,
  -- auto-detect may load Churn as BOOL (true/false) or as text (Yes/No); this handles both
  IF(CAST(Churn AS STRING) IN ('Yes', 'true'), 1, 0) AS churned,
  CASE
    WHEN CAST(tenure AS INT64) <= 12 THEN '0-12'
    WHEN CAST(tenure AS INT64) <= 24 THEN '13-24'
    WHEN CAST(tenure AS INT64) <= 48 THEN '25-48'
    ELSE '49-72'
  END                                          AS tenure_band
FROM `churn_project.telco_raw`;

-- Sanity check: expect 7,043 rows, 1,869 churners (26.5%)
SELECT COUNT(*) AS customers, SUM(churned) AS churners, ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM `churn_project.customers_clean`;
