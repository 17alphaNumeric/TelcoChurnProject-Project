# Telecom Customer Churn Analysis — BigQuery, BigQuery ML & Data Studio

Understand where telecom churn is concentrated, validate a churn model on data it has never seen, and turn its output into a prioritized, honestly sized retention list. Built entirely in SQL in the free BigQuery sandbox, with a Data Studio (formerly Looker Studio) dashboard.

**Tools:** Google BigQuery (sandbox), BigQuery ML, SQL, Data Studio
**Data:** IBM Telco Customer Churn — 7,043 customers, 21 attributes (contract, tenure, services, billing, churn flag). A single snapshot, not a time series.

---

## Business question
A wireless/broadband provider loses roughly 1 in 4 customers. Where is churn concentrated, how large is the revenue associated with it, and which active customers should a retention team prioritize, by what rule?

## 1. Churn drivers (descriptive)

| Metric | Value |
|---|---|
| Customers / churned | 7,043 / 1,869 |
| Churn rate | **26.5%** |
| Monthly charges associated with churned customers | **~$139K of $456K (30.5%)** |

The ~$139K is the sum of monthly charges on records flagged as churned in this snapshot. It is not a verified loss in any particular month.

- **Contract:** month-to-month **42.7%** churn (n = 3,875) vs one-year 11.3% (n = 1,473) and two-year **2.8%** (n = 1,695).
- **Lifecycle:** first-year customers churn at **47.4%** (n = 2,186), falling to 9.5% after four years (n = 2,239).
- **Internet service:** fiber **41.9%** (avg bill $91.50, n = 3,096) vs DSL 19.0% (n = 2,421).
- **Payment:** electronic-check payers **45.3%** (n = 2,365) vs 15–19% for other methods.
- **Support:** internet customers without tech support churn at 41.6% (n = 3,473) vs 15.2% with it (n = 2,044).
- **Highest-churn segment:** new (≤ 12 months), month-to-month, fiber customers: **916 customers, 70.2% churn**.

These are associations in one snapshot, not proof that a product, payment method or service *causes* churn.

## 2. Predictive model

**Setup (v2):**
- Deterministic 80/20 split on a hash of `customer_id`: 5,641 training customers (26.0% churn) and 1,402 holdout customers (28.8% churn).
- BigQuery ML logistic regression trained on the training split only.
- No class weighting, so the outputs can be read as probabilities.

**Holdout performance.** All figures are on customers the model never saw.

| Metric | Value |
|---|---|
| ROC AUC | **0.825** |
| Precision / recall at 0.5 threshold | 0.669 / 0.406 |
| Accuracy | 0.771 |
| Log loss / Brier score | 0.461 / 0.153 |
| Top-decile lift | **2.46×** (70.9% actual churn vs 28.8% base) |

Recall at the default 0.5 threshold is modest. In practice the threshold is a budget decision: `ML.ROC_CURVE` in `04_evaluate.sql` shows the precision/recall trade-off at every cut-off.

**Calibration (holdout deciles):** do predicted probabilities match what actually happened?

| Decile | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Avg predicted | .683 | .534 | .407 | .304 | .207 | .132 | .089 | .056 | .038 | .024 |
| Actual churn | .709 | .603 | .450 | .400 | .264 | .221 | .164 | .036 | .021 | .007 |

Predictions track reality closely at the top and bottom. In the middle deciles the model under-predicts slightly: averaged over the whole holdout, it predicts 24.8% churn against 28.8% actual. Dollar estimates built on these probabilities are therefore conservative, not inflated.

### What changed from v1, and why
The first version used `auto_class_weights=TRUE` and scored all 5,174 active customers. That raised two problems:
1. **Class weighting distorts the probabilities.** It boosted recall (0.81), but it pushed the probabilities upward, so "probability × bill" overstated the exposure.
2. **Training customers were scored too.** About 80% of the scored customers had been in the training data, so those scores were not out-of-sample.

v2 fixes both problems. v1's headline figures ($354K "high-risk revenue", $1.07M total) are retired and should not be reused.

## 3. Retention prioritization

The 998 holdout customers who were still active in the snapshot are scored and tiered by calibrated churn probability. The tiers are validated against the full holdout, churners included:

| Tier | Holdout customers | Avg predicted | Actual churn | Active customers | Annualized exposure estimate (active) |
|---|---|---|---|---|---|
| High (≥ 50%) | 245 | 0.628 | **0.669** | 81 | $47,511 |
| Medium (25–50%) | 322 | 0.368 | 0.438 | 181 | $54,723 |
| Low (< 25%) | 835 | 0.090 | 0.119 | 736 | $47,660 |

**Annualized exposure estimate = churn probability × monthly charges × 12.** It assumes charges stay flat and that a churner is lost for a full year. It is a sizing and ranking proxy, not a validated 12-month revenue-loss forecast. The figures cover the 998 holdout actives only and are not extrapolated to the full base.

For deployment, the model would be retrained on all available history and used to score a new, later population.

## 4. Recommendations
1. **Contract migration offer** for month-to-month customers early in tenure, testing a discount or credit for moving to 12/24-month terms.
2. **Fiber onboarding** in the first 90 days: proactive check-ins, plus bundled tech support and online security.
3. **AutoPay incentive** to move electronic-check payers onto automatic payment.
4. **Work the High tier first**, sorted by exposure estimate, and set the cut-off from the ROC curve and the retention budget.

## 5. Proposed campaign measurement (hypothetical, with no results claimed)
How a retention offer to the High tier would be measured before scaling:
- **Eligibility:** active customers with predicted churn ≥ 50%.
- **Design:** randomly assign eligible customers to treatment (receives the offer) or control (no offer), stratified by contract type.
- **Primary outcome:** churn rate in each group over a fixed follow-up window, e.g. 90 days.
- **Metrics:**
  - Incremental retention = control churn − treatment churn.
  - Campaign spend = offers redeemed × offer cost.
  - **Cost of Retention (COR)** = campaign spend ÷ incrementally retained customers.
  - Net value = (incrementally retained customers × contribution margin × months retained) − campaign spend.
- **Decision rule:** scale only if net value is positive and the churn difference is statistically significant. Otherwise adjust the offer or targeting threshold.

### Sizing the test
Inputs come from BigQuery (`churn_scores_v2`) plus explicit assumptions. Every figure is reproducible with `python3 analysis/ab_test_design.py`.

- **Baseline:** High-tier active customers average a **61.8%** predicted churn probability and **$78.75** in monthly charges.
- **Test:** two-sided two-proportion z-test, α = 0.05, power = 80%, equal allocation. This was cross-checked with the arcsine (Cohen's h) method.

| Population | Baseline churn | Effect to detect | n per arm | Total needed | Est. eligible pool* | Feasible? |
|---|---|---|---|---|---|---|
| High tier | 61.8% | −10 pts | 385 | 770 | ~407 | **No** |
| High tier | 61.8% | −15 pts | 172 | 344 | ~407 | Yes, barely |
| High + Medium | 44.0% | −10 pts | 373 | 746 | ~1,316 | Yes |
| High tier | 61.8% | −5 pts | 1,515 | 3,030 | ~407 | No |

*The holdout had 81 High-tier active customers out of 1,402 (5.8%). Scaled to the 7,043-customer base, that is roughly 407 customers. This assumes the holdout is representative.*

**Finding:** the High tier alone is too small to detect a realistic 10-point effect. To run this test, the team would need to do one of these:
1. **Widen eligibility** to High + Medium. The pool becomes about 1,316, but the baseline drops to 44% and the offer reaches lower-risk customers.
2. **Recruit over several monthly cohorts** until each arm reaches 385.
3. **Accept that only a large effect (≥ 15 points) can be detected.**

This is a pre-launch insight: it tells the business to reshape the test before spending money on it.

### Break-even Cost of Retention (scenario, not a result)
Three quantities have to stay separate:
- **Offer cost:** what is spent per treated customer.
- **Campaign effectiveness:** the absolute drop in churn the offer causes.
- **Value of a save:** monthly charges × contribution margin × months retained. Charges are revenue, not profit.

The formulas:
- Break-even offer cost per treated customer = effectiveness × value of a save.
- COR = offer cost ÷ effectiveness.

High tier, 12-month horizon:

| Contribution margin | Value of one save | Break-even at −5 pts | at −10 pts | at −15 pts |
|---|---|---|---|---|
| 30% | $283.50 | $14.18 | $28.35 | $42.52 |
| 50% | $472.50 | $23.62 | $47.25 | $70.88 |

Example: a $40 offer that cuts churn by 10 points costs **$400 per incremental save**. It only pays off if a save is worth more than $400 in contribution, which needs a margin above roughly 42% on a 12-month horizon.

Margins, effectiveness and horizon are **assumptions**. Only a controlled pilot can measure effectiveness, and finance would supply the real margin.

All campaign figures stay hypothetical until a real pilot runs.

## 6. Limitations
- Single cross-sectional snapshot: no churn trend over time and no causal evidence.
- "Active" customers are those not flagged as churned in the snapshot. Their future behavior is not observed.
- The holdout is small (1,402), so tier-level rates carry real sampling error.
- No campaign has been run, so no ROI is claimed.

---

## How to run it (free, no credit card)
1. Enable the **BigQuery sandbox** and create a project.
2. Create a dataset named `churn_project`.
3. Upload `Telco-Customer-Churn.csv` as table `telco_raw`, with schema set to **auto-detect**.
4. Run the scripts in order:

| File | What it does |
|---|---|
| `sql/01_clean.sql` | Type casting, null handling, churn flag, tenure bands |
| `sql/02_churn_drivers.sql` | KPIs, churn by segment, contract × tenure, high-churn segment |
| `sql/03_train_model.sql` | Reproducible train/holdout split; trains the v2 model on training data only |
| `sql/04_evaluate.sql` | Holdout metrics, calibration deciles, lift, ROC curve, feature importance |
| `sql/05_score_customers.sql` | Scores holdout actives, validates tiers, builds the priority list |
| `sql/06_dashboard_tables.sql` | Small pre-aggregated tables for the dashboard: key factors, calibration deciles, tiers with 95% Wilson CIs |

## Dashboard (Data Studio, two pages)
**Page 1, Overview & Drivers:** filters for contract, tenure, internet service and payment method; KPI cards (7,043 customers, 1,869 churned, 26.5% churn rate, $139K monthly charges from churned customers); churn by contract; a tenure × contract heatmap (51% churn for month-to-month customers in their first year vs. 0% for two-year contracts); churn by key factor.

![Overview & Drivers](screenshots/02_dashboard_p1_overview_drivers.png)

**Page 2, Model & Retention:** holdout model metrics (AUC 0.825, 95% CI 0.798–0.852; precision 0.669, recall 0.406 at 0.5; lift 2.46×; Brier 0.153); a calibration chart of predicted vs. actual churn by decile; the risk-tier table with 95% Wilson confidence intervals and annualized exposure; and the A/B sizing and break-even summary with a recommended action.

![Model & Retention](screenshots/03_dashboard_p2_model_retention.png)

The dashboard reads from static BigQuery tables. It refreshes only when the SQL is re-run, and Data Studio caches results for about 12 hours.

**Sandbox notes:** the scripts use only `CREATE OR REPLACE TABLE/MODEL ... AS SELECT`, because the sandbox blocks DML. Sandbox tables expire after 60 days, so screenshots of the results are in `screenshots/`.

## Project contents
```
telco-churn-bigquery/
├── README.md
├── Telco-Customer-Churn.csv              # source data (IBM sample dataset)
├── sql/
│   ├── 01_clean.sql
│   ├── 02_churn_drivers.sql
│   ├── 03_train_model.sql                # v2: train/holdout split, no class weights
│   ├── 04_evaluate.sql                   # holdout metrics + calibration
│   ├── 05_score_customers.sql            # validated tiers + priority list
│   └── 06_dashboard_tables.sql           # dashboard tables incl. Wilson CIs
├── analysis/
│   └── ab_test_design.py                 # A/B sample sizing + break-even COR
└── screenshots/
    ├── 01_churn_drivers.jpg
    ├── 02_dashboard_p1_overview_drivers.png
    ├── 03_dashboard_p2_model_retention.png
    └── v1_*.jpg                          # retired v1 results, kept for the before/after story
```

## Interview narrative
> "I analyzed telecom churn in BigQuery, looking at lifecycle and contract drivers, then built a churn classifier with BigQuery ML. My first version used class weighting, which boosted recall but inflated the probabilities, and it scored customers the model had trained on. So I rebuilt it with a proper train/holdout split, checked calibration by decile, and recomputed the revenue exposure. That brought the dollar estimates down to defensible numbers. I then turned the validated risk tiers into a prioritized retention list and designed an A/B test to measure Cost of Retention. The power analysis showed the High-risk tier alone was too small to detect a 10-point effect, so I recommended widening eligibility or recruiting over multiple cohorts before launch. For break-even, I separated offer cost, campaign effectiveness and contribution margin, rather than treating revenue as profit."

## Résumé bullets
> - Analyzed churn for 7,043 telecom customers in BigQuery SQL; identified a 916-customer early-tenure, month-to-month fiber segment with 70% churn and quantified ~$139K in monthly charges associated with churned customers.
> - Built and validated a BigQuery ML churn model on a held-out split (AUC 0.83, 2.5× top-decile lift). Diagnosed and corrected probability inflation from class weighting, and calibrated risk tiers to within 3–7 points of actual churn.
> - Designed and sized a treatment/control retention test (α = 0.05, 80% power). Showed that the High-risk segment alone was underpowered for a 10-point effect, and built a break-even Cost of Retention model based on contribution margin. Presented the findings in a Data Studio executive dashboard.
