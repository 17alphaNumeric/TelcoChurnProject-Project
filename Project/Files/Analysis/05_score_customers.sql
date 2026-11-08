-- 05_score_customers.sql
-- Turn holdout predictions into a prioritized retention list.
--
-- Scope: only HOLDOUT customers are scored here, so every score is out-of-sample.
-- For a real deployment you would retrain on all available history and score a new, later population.
--
-- annualized_exposure_estimate = churn probability x monthly charges x 12.
-- It is a ranking/sizing proxy built on stated assumptions (charges stay flat, a churner is lost for a full year),
-- not a validated 12-month revenue-loss forecast.

CREATE OR REPLACE TABLE `churn_project.churn_scores_v2` AS
SELECT
  customer_id,
  contract,
  tenure_months,
  internet_service,
  payment_method,
  monthly_charges,
  churn_prob                                   AS churn_probability,
  ROUND(churn_prob * monthly_charges * 12, 2)  AS annualized_exposure_estimate,
  CASE
    WHEN churn_prob >= 0.50 THEN 'High'
    WHEN churn_prob >= 0.25 THEN 'Medium'
    ELSE 'Low'
  END                                          AS risk_tier
FROM `churn_project.holdout_preds`
WHERE churned = 0;   -- customers still active in the snapshot

-- Validate the tiers: on the full holdout (churners included), does each tier's actual churn rate match its prediction?
SELECT
  tier,
  COUNT(*)                                     AS holdout_customers,
  ROUND(AVG(churn_prob), 3)                    AS avg_predicted,
  ROUND(AVG(churned), 3)                       AS actual_churn_rate,
  COUNTIF(churned = 0)                         AS active_customers,
  ROUND(SUM(IF(churned = 0, churn_prob * monthly_charges * 12, 0)), 0) AS active_annualized_exposure
FROM (
  SELECT *,
    CASE WHEN churn_prob >= 0.50 THEN 'High' WHEN churn_prob >= 0.25 THEN 'Medium' ELSE 'Low' END AS tier
  FROM `churn_project.holdout_preds`
)
GROUP BY tier
ORDER BY avg_predicted DESC;

-- Retention priority list
SELECT *
FROM `churn_project.churn_scores_v2`
ORDER BY annualized_exposure_estimate DESC
LIMIT 100;
