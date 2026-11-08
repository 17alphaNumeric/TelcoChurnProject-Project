-- 02_churn_drivers.sql
-- Descriptive analysis: where is churn concentrated, and what does it cost?

-- 1) Headline KPIs: churn rate and monthly charges associated with churned customers
--    (a snapshot figure, not a verified loss in any particular month)
SELECT
  COUNT(*)                                                    AS customers,
  ROUND(AVG(churned) * 100, 1)                                AS churn_pct,
  ROUND(SUM(monthly_charges), 0)                              AS total_monthly_charges,
  ROUND(SUM(IF(churned = 1, monthly_charges, 0)), 0)          AS churned_monthly_charges,
  ROUND(SUM(IF(churned = 1, monthly_charges, 0)) / SUM(monthly_charges) * 100, 1) AS pct_charges_churned
FROM `churn_project.customers_clean`;

-- 2) Churn by any single dimension. Swap `contract` for:
--    tenure_band, internet_service, payment_method, tech_support, online_security, paperless_billing
SELECT
  contract,
  COUNT(*)                         AS customers,
  ROUND(AVG(churned) * 100, 1)     AS churn_pct,
  ROUND(AVG(monthly_charges), 2)   AS avg_monthly_bill,
  ROUND(SUM(IF(churned = 1, monthly_charges, 0)), 0) AS churned_monthly_charges
FROM `churn_project.customers_clean`
GROUP BY contract
ORDER BY churn_pct DESC;

-- 3) Churn by tenure band x contract (shows the "first-year cliff")
SELECT
  tenure_band,
  contract,
  COUNT(*)                     AS customers,
  ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM `churn_project.customers_clean`
GROUP BY tenure_band, contract
ORDER BY tenure_band, churn_pct DESC;

-- 4) Highest-risk segment: new, month-to-month, fiber customers
SELECT
  COUNT(*)                     AS customers,
  ROUND(AVG(churned) * 100, 1) AS churn_pct,
  ROUND(SUM(IF(churned = 1, monthly_charges, 0)), 0) AS churned_monthly_charges
FROM `churn_project.customers_clean`
WHERE contract = 'Month-to-month'
  AND internet_service = 'Fiber optic'
  AND tenure_months <= 12;

-- 5) Does add-on support reduce churn among fiber customers?
SELECT
  tech_support,
  online_security,
  COUNT(*)                     AS customers,
  ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM `churn_project.customers_clean`
WHERE internet_service = 'Fiber optic'
GROUP BY tech_support, online_security
ORDER BY churn_pct DESC;
