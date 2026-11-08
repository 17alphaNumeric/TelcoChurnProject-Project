-- 04_evaluate.sql
-- Evaluate the v2 model ONLY on the holdout split it never saw during training,
-- and check whether its outputs behave like real probabilities (calibration).

-- 1) Holdout metrics (precision/recall/accuracy/F1 are at the default 0.5 threshold; ROC AUC and log loss are threshold-free)
SELECT
  ROUND(roc_auc, 3)   AS roc_auc,
  ROUND(precision, 3) AS precision_at_0_5,
  ROUND(recall, 3)    AS recall_at_0_5,
  ROUND(accuracy, 3)  AS accuracy,
  ROUND(f1_score, 3)  AS f1,
  ROUND(log_loss, 3)  AS log_loss
FROM ML.EVALUATE(MODEL `churn_project.churn_logreg_v2`,
                 (SELECT * FROM `churn_project.customers_split` WHERE split = 'holdout'));

-- 2) Store holdout predictions for calibration and tiering
CREATE OR REPLACE TABLE `churn_project.holdout_preds` AS
SELECT
  customer_id, contract, tenure_months, internet_service, payment_method, monthly_charges, churned,
  (SELECT prob FROM UNNEST(predicted_churned_probs) WHERE label = 1) AS churn_prob
FROM ML.PREDICT(MODEL `churn_project.churn_logreg_v2`,
                (SELECT * FROM `churn_project.customers_split` WHERE split = 'holdout'));

-- 3) Calibration + lift by decile: does a predicted 40% actually churn ~40% of the time?
--    Row 99 = whole holdout; its "lift" column holds the Brier score (mean squared error of the probabilities).
SELECT
  decile,
  COUNT(*)                         AS customers,
  ROUND(AVG(churn_prob), 3)        AS avg_predicted,
  ROUND(AVG(churned), 3)           AS actual_rate,
  ROUND(AVG(churned) / (SELECT AVG(churned) FROM `churn_project.holdout_preds`), 2) AS lift
FROM (
  SELECT NTILE(10) OVER (ORDER BY churn_prob DESC) AS decile, churn_prob, churned
  FROM `churn_project.holdout_preds`
)
GROUP BY decile
UNION ALL
SELECT 99, COUNT(*), ROUND(AVG(churn_prob), 3), ROUND(AVG(churned), 3),
       ROUND(AVG(POW(churn_prob - churned, 2)), 4)
FROM `churn_project.holdout_preds`
ORDER BY decile;

-- 4) Precision/recall trade-off across thresholds, on the holdout
SELECT threshold, precision, recall, false_positive_rate
FROM ML.ROC_CURVE(MODEL `churn_project.churn_logreg_v2`,
                  (SELECT * FROM `churn_project.customers_split` WHERE split = 'holdout'))
ORDER BY threshold;

-- 5) Global feature importance
SELECT * FROM ML.GLOBAL_EXPLAIN(MODEL `churn_project.churn_logreg_v2`)
ORDER BY attribution DESC;
