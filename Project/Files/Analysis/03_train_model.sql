-- 03_train_model.sql
-- Train a churn classifier with BigQuery ML (available in the free sandbox).
--
-- Design choices (v2):
--   * Deterministic 80/20 train/holdout split on a hash of customer_id, so the split is reproducible
--     and the holdout is never seen during training.
--   * NO class weighting. auto_class_weights=TRUE (used in v1) rebalances churners vs. non-churners,
--     which improves recall at a 0.5 threshold but shifts predicted probabilities upward, so they can
--     no longer be read as churn probabilities. Dollar-based estimates need calibrated probabilities.
--   * Logistic regression: fast, cheap, and its weights are explainable to a business audience.

-- 1) Reproducible split
CREATE OR REPLACE TABLE `churn_project.customers_split` AS
SELECT
  *,
  IF(MOD(ABS(FARM_FINGERPRINT(customer_id)), 10) < 8, 'train', 'holdout') AS split
FROM `churn_project.customers_clean`;

-- 2) Train on the training split only
CREATE OR REPLACE MODEL `churn_project.churn_logreg_v2`
OPTIONS (
  model_type            = 'LOGISTIC_REG',
  input_label_cols      = ['churned'],
  data_split_method     = 'NO_SPLIT',   -- we control the split ourselves
  enable_global_explain = TRUE
) AS
SELECT * EXCEPT (customer_id, tenure_band, split)
FROM `churn_project.customers_split`
WHERE split = 'train';

-- 3) Check the split sizes and churn balance
SELECT split, COUNT(*) AS customers, SUM(churned) AS churners, ROUND(AVG(churned) * 100, 1) AS churn_pct
FROM `churn_project.customers_split`
GROUP BY split;
