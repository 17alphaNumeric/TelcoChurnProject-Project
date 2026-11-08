-- 06_dashboard_tables.sql
-- Small, pre-aggregated tables that feed the Data Studio dashboard.

-- Key churn factors (association, not causation)
CREATE OR REPLACE TABLE `churn_project.dash_key_factors` AS
SELECT 'Fiber optic' AS factor, 1 AS sort_order, AVG(churned) AS churn_rate, COUNT(*) AS customers
FROM `churn_project.customers_clean` WHERE internet_service = 'Fiber optic'
UNION ALL SELECT 'Electronic check', 2, AVG(churned), COUNT(*)
FROM `churn_project.customers_clean` WHERE payment_method = 'Electronic check'
UNION ALL SELECT 'No tech support', 3, AVG(churned), COUNT(*)
FROM `churn_project.customers_clean` WHERE tech_support = 'No'
UNION ALL SELECT 'With tech support', 4, AVG(churned), COUNT(*)
FROM `churn_project.customers_clean` WHERE tech_support = 'Yes';

-- Calibration: predicted vs actual churn by holdout risk decile (1 = highest risk)
CREATE OR REPLACE TABLE `churn_project.dash_calibration` AS
SELECT decile, AVG(churn_prob) AS predicted, AVG(churned) AS actual, COUNT(*) AS customers
FROM (
  SELECT NTILE(10) OVER (ORDER BY churn_prob DESC) AS decile, churn_prob, churned
  FROM `churn_project.holdout_preds`
)
GROUP BY decile;

-- Risk tiers on the holdout, with 95% Wilson confidence intervals on the actual churn rate
CREATE OR REPLACE TABLE `churn_project.dash_tiers` AS
SELECT
  tier, sort_order, n AS holdout_customers, avg_predicted, p AS actual_churn,
  (p + 1.96*1.96/(2*n) - 1.96*SQRT(p*(1-p)/n + 1.96*1.96/(4*n*n))) / (1 + 1.96*1.96/n) AS ci_low,
  (p + 1.96*1.96/(2*n) + 1.96*SQRT(p*(1-p)/n + 1.96*1.96/(4*n*n))) / (1 + 1.96*1.96/n) AS ci_high,
  active_customers, annualized_exposure
FROM (
  SELECT
    CASE WHEN churn_prob >= 0.5 THEN 'High (50%+)' WHEN churn_prob >= 0.25 THEN 'Medium (25-50%)' ELSE 'Low (<25%)' END AS tier,
    CASE WHEN churn_prob >= 0.5 THEN 1 WHEN churn_prob >= 0.25 THEN 2 ELSE 3 END AS sort_order,
    COUNT(*) AS n,
    AVG(churn_prob) AS avg_predicted,
    AVG(churned) AS p,
    COUNTIF(churned = 0) AS active_customers,
    SUM(IF(churned = 0, churn_prob * monthly_charges * 12, 0)) AS annualized_exposure
  FROM `churn_project.holdout_preds`
  GROUP BY tier, sort_order
);

SELECT * FROM `churn_project.dash_tiers` ORDER BY sort_order;
