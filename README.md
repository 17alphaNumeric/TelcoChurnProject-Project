# Telecom Customer Churn Analysis
### BigQuery SQL · BigQuery ML · Python · Data Studio

I built this project to answer a question every subscription business faces: **which customers are about to leave, why, and what is it worth spending to keep them?** I worked end to end in Google BigQuery's free sandbox, from raw CSV to a tested prediction model, a sized retention experiment and an interactive dashboard.

### 🔗 [**View the live dashboard**](https://datastudio.google.com/reporting/c6506235-e6f3-4335-9e41-5a1d25e99793) (no sign-in needed, view-only)

[![Dashboard preview](Project/Files/Screenshots/02_dashboard_p1_overview_drivers.png)](https://datastudio.google.com/reporting/c6506235-e6f3-4335-9e41-5a1d25e99793)

📘 **Reviewing this project?** The [Reviewer User Manual](Project/Files/Telco_Churn_Reviewer_User_Manual.pdf) gives a 5-minute guided tour. The [Build Manual](Project/Files/Telco_Churn_Project_Build_Manual.pdf) walks through rebuilding everything step by step.

---

## Contents
1. [Key results at a glance](#key-results-at-a-glance)
2. [The business problem](#the-business-problem)
3. [Data](#data)
4. [How I approached it](#how-i-approached-it)
5. [What drives churn](#1-what-drives-churn)
6. [The prediction model](#2-the-prediction-model)
7. [Turning predictions into action](#3-turning-predictions-into-action)
8. [Designing the retention experiment](#4-designing-the-retention-experiment)
9. [Recommendations](#5-recommendations)
10. [Dashboard](#dashboard)
11. [Limitations](#limitations)
12. [How to reproduce it](#how-to-reproduce-it)
13. [Repository structure](#repository-structure)

---

## Key results at a glance

| | |
|---|---|
| **Churn rate** | 26.5% (1,869 of 7,043 customers) |
| **Revenue tied to churned customers** | ~$139K of $456K in monthly charges (30.5%) |
| **Biggest risk factor** | Month-to-month contracts churn at 42.7% vs. 2.8% on two-year contracts (~15×) |
| **Highest-risk segment** | New, month-to-month, fiber customers: 916 customers, **70.2% churn** |
| **Model quality (unseen data)** | AUC **0.825** (95% CI 0.798–0.852), top-decile lift **2.46×** |
| **Tier reliability** | Actual churn within 3–7 points of predicted in every risk tier |
| **Experiment finding** | The High-risk tier alone is too small for a reliable A/B test, so I redesigned the test before any money is spent |

---

## The business problem
A wireless and broadband provider is losing roughly 1 in 4 customers. I set out to answer four questions:
1. **Where** is churn concentrated?
2. **How much** revenue is associated with it?
3. **Which** active customers should a retention team contact first, and by what rule?
4. **How** would we prove a retention offer actually works, and what can we afford to spend on it?

## Data
- **Source:** IBM Telco Customer Churn sample dataset ([`Telco-Customer-Churn.csv`](Project/Files/Telco-Customer-Churn.csv))
- **Size:** 7,043 customers, 21 attributes: contract, tenure, services, billing, payment method and a churn flag
- **Nature:** a single snapshot in time, not a time series

## How I approached it

```
Raw CSV → Clean (SQL) → Explore drivers (SQL) → 80/20 split → Train model (BigQuery ML)
        → Test on holdout → Score & tier customers → Size A/B test (Python) → Dashboard
```

| Step | What I did | Script |
|---|---|---|
| Clean | Fixed data types, filled 11 blank `TotalCharges` with 0 (brand-new customers), created a 1/0 churn flag and tenure bands | `01_clean.sql` |
| Explore | Measured churn by contract, tenure, internet type, payment method and support | `02_churn_drivers.sql` |
| Model | Split customers 80/20 with a reproducible hash, then trained a logistic regression on the 80% only | `03_train_model.sql` |
| Evaluate | Scored the 20% holdout and checked accuracy, calibration and lift | `04_evaluate.sql` |
| Prioritize | Grouped active holdout customers into High / Medium / Low risk tiers and checked each tier against reality | `05_score_customers.sql` |
| Experiment | Calculated the sample size for a retention A/B test and the break-even offer cost | `ab_test_design.py` |
| Present | Built summary tables (including confidence intervals) and a two-page dashboard | `06_dashboard_tables.sql` |

---

## 1. What drives churn

| Factor | Churn rate | Customers |
|---|---|---|
| Month-to-month contract | **42.7%** | 3,875 |
| One-year contract | 11.3% | 1,473 |
| Two-year contract | **2.8%** | 1,695 |
| First year with the company | **47.4%** | 2,186 |
| More than four years | 9.5% | 2,239 |
| Fiber optic internet (avg bill $91.50) | **41.9%** | 3,096 |
| DSL internet | 19.0% | 2,421 |
| Pays by electronic check | **45.3%** | 2,365 |
| Other payment methods | 15–19% | — |
| Internet customers **without** tech support | 41.6% | 3,473 |
| Internet customers **with** tech support | 15.2% | 2,044 |

**What stood out:** risk stacks up. New, month-to-month, fiber customers churn at **70.2%** (916 customers), almost three times the company average.

The ~$139K figure is the total monthly charges of customers marked as churned in this snapshot, not a verified loss in a specific month. All of these are **associations**, not proof that a product or payment method *causes* churn.

---

## 2. The prediction model

### Setup
- **Fair test:** I split customers 80/20 using a hash of `customer_id`, giving 5,641 for training (26.0% churn) and 1,402 held out (28.8% churn). The split is identical every time the script runs.
- **Model:** BigQuery ML logistic regression, trained only on the 80%.
- **No class weighting,** so the outputs are honest probabilities that can safely be turned into dollar estimates.

### Performance on customers the model never saw

| Metric | Value | In plain English |
|---|---|---|
| ROC AUC | **0.825** | Ranks leavers above stayers well (0.5 = coin flip, 1.0 = perfect) |
| Precision at 0.5 | 0.669 | 67% of flagged customers really left |
| Recall at 0.5 | 0.406 | Catches 41% of leavers at this cut-off |
| Accuracy | 0.771 | 77% of predictions correct |
| Log loss / Brier score | 0.461 / 0.153 | Low probability error |
| Top-decile lift | **2.46×** | The riskiest 10% churn at 70.9% vs. 28.8% average |

Recall at the 0.5 cut-off is modest by design. Choosing the cut-off is really a budget decision, so I used `ML.ROC_CURVE` to show the precision/recall trade-off at every threshold.

### Can the probabilities be trusted? (calibration)

| Risk decile | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Predicted | .683 | .534 | .407 | .304 | .207 | .132 | .089 | .056 | .038 | .024 |
| Actual | .709 | .603 | .450 | .400 | .264 | .221 | .164 | .036 | .021 | .007 |

Predictions track reality closely at the top and bottom. In the middle the model slightly under-predicts (24.8% predicted vs. 28.8% actual overall), so any dollar figures built on it are **conservative, not inflated**.

### What I fixed along the way (v1 → v2)
My first version used `auto_class_weights=TRUE` and scored all 5,174 active customers. Reviewing it, I found two problems:
1. **Class weighting inflated the probabilities.** Recall looked great (0.81), but "probability × bill" overstated the money at risk.
2. **I was scoring customers the model had trained on.** About 80% of the scores weren't a fair test.

I rebuilt the model to fix both. I retired v1's headline figures ($354K "high-risk revenue", $1.07M total) and kept its screenshots (`v1_*.jpg`) only to document the before-and-after.

---

## 3. Turning predictions into action

I scored the 998 holdout customers who were still active and grouped them into risk tiers. To check that the tiers are reliable, I compared each tier's prediction with what actually happened across the full holdout:

| Tier | Holdout customers | Predicted churn | Actual churn | 95% CI (actual) | Still active | Annual exposure (est.) |
|---|---|---|---|---|---|---|
| **High** (≥ 50%) | 245 | 62.8% | **66.9%** | 60.8–72.5% | 81 | $47,511 |
| **Medium** (25–50%) | 322 | 36.8% | 43.8% | 38.5–49.2% | 181 | $54,723 |
| **Low** (< 25%) | 835 | 9.0% | 11.9% | 9.8–14.2% | 736 | $47,660 |

**Annual exposure = churn probability × monthly charges × 12.** It assumes flat charges and a full year lost per churner, so it's a way to rank and size customers, not a revenue forecast. It covers the 998 holdout actives only. In production I would retrain on all history and score a new, later population.

---

## 4. Designing the retention experiment

Before recommending a retention offer, I wanted to know how to **prove** it works. My test plan:
- **Who:** active customers with predicted churn ≥ 50%.
- **How:** randomly split them into treatment (gets the offer) and control (no offer), balanced by contract type.
- **Measure:** churn in each group over a fixed window, e.g. 90 days.
- **Scale it only if** the difference is statistically significant **and** the net value is positive.

### How many customers does the test need?
I used a two-sided, two-proportion z-test (α = 0.05, 80% power) and cross-checked it with Cohen's h. Inputs: High-tier customers average **61.8%** predicted churn and **$78.75** a month.

| Who is tested | Baseline churn | Drop to detect | Per group | Total | Available* | Feasible? |
|---|---|---|---|---|---|---|
| High tier | 61.8% | −10 pts | 385 | 770 | ~407 | ❌ No |
| High tier | 61.8% | −15 pts | 172 | 344 | ~407 | ⚠️ Barely |
| High tier | 61.8% | −5 pts | 1,515 | 3,030 | ~407 | ❌ No |
| **High + Medium** | 44.0% | −10 pts | 373 | 746 | ~1,316 | ✅ **Yes** |

<sub>*81 of the 1,402 holdout customers (5.8%) were active and High-tier; scaled to the full 7,043-customer base, that is about 407. This assumes the holdout is representative.</sub>

**Key finding:** the High tier alone is **too small** to reliably detect a realistic 10-point improvement. Before spending any money, I'd recommend one of three options:
1. **Widen eligibility** to High + Medium (about 1,316 customers, though the baseline drops to 44%).
2. **Recruit over several monthly cohorts** until each group reaches 385.
3. **Accept** that only a large effect (≥ 15 points) can be detected.

### What can we afford to spend? (break-even)
I kept three things separate, because charges are revenue, not profit:
- **Offer cost:** spend per customer reached
- **Effectiveness:** how much the offer actually lowers churn
- **Value of a save:** monthly charges × contribution margin × months retained

The formulas:
- Break-even cost per customer = effectiveness × value of a save
- Cost of Retention (COR) = offer cost ÷ effectiveness

High tier, 12-month horizon:

| Contribution margin | Value of one save | Break-even at −5 pts | at −10 pts | at −15 pts |
|---|---|---|---|---|
| 30% | $283.50 | $14.18 | **$28.35** | $42.52 |
| 50% | $472.50 | $23.62 | **$47.25** | $70.88 |

**Example:** a $40 offer that cuts churn by 10 points costs **$400 per extra customer kept**. That only pays off if the margin is above about 42%.

Margins, effectiveness and the horizon are **assumptions**. Only a real pilot can measure effectiveness, and finance would supply the actual margin. No campaign results are claimed.

---

## 5. Recommendations
1. **Contract upgrade offer:** target new month-to-month customers with a discount or credit to move to a 12- or 24-month plan.
2. **Fiber onboarding program:** proactive check-ins in the first 90 days, bundled with tech support and online security.
3. **AutoPay incentive:** move electronic-check payers to automatic payment.
4. **Work the High tier first:** sort by exposure, and set the cut-off from the ROC curve and the retention budget.
5. **Test before scaling:** run the A/B test on High + Medium (or across monthly cohorts) so it is properly powered.

---

## Dashboard
👉 **[Open the live dashboard](https://datastudio.google.com/reporting/c6506235-e6f3-4335-9e41-5a1d25e99793)**

**Page 1: Overview & Drivers**
- Filters: contract, tenure, internet service and payment method
- KPI cards: customers, churned customers, churn rate, churned monthly charges
- Charts: churn by contract, a tenure × contract heatmap, churn by key factor

![Overview & Drivers](Project/Files/Screenshots/02_dashboard_p1_overview_drivers.png)

**Page 2: Model & Retention**
- Holdout model metrics
- A predicted-vs-actual calibration chart
- The risk-tier table with 95% confidence intervals
- The A/B test design and recommended action

![Model & Retention](Project/Files/Screenshots/03_dashboard_p2_model_retention.png)

The dashboard reads from static BigQuery tables, so it changes only when the SQL is re-run (Data Studio also caches for about 12 hours). Free-sandbox tables expire after 60 days, so the screenshots above are the permanent record of the results.

---

## Limitations
- **Single snapshot:** no trend over time, and no proof of cause and effect.
- **"Active" customers** are those not flagged as churned in the snapshot; their future behavior isn't observed.
- **Small holdout** (1,402 customers), so tier-level rates carry real sampling error, which is why I report confidence intervals.
- **No campaign has been run,** so no ROI is claimed; the experiment is designed and sized only.

---

## How to reproduce it
Everything runs free in the BigQuery sandbox, with no credit card needed. The [Build Manual](Project/Files/Telco_Churn_Project_Build_Manual.pdf) has screenshots for every step.

1. Enable the **BigQuery sandbox** and create a project.
2. Create a dataset named `churn_project`.
3. Upload `Project/Files/Telco-Customer-Churn.csv` as table `telco_raw`, with **auto-detect** schema.
4. Run the SQL scripts in `Project/Files/Analysis/` in order, `01` to `06`.
5. Run `python3 Project/Files/ab_test/ab_test_design.py`. It uses only the Python standard library.
6. Connect Data Studio to the `churn_project` tables.

The sandbox blocks `INSERT`/`UPDATE`/`DELETE`, so every script uses `CREATE OR REPLACE TABLE … AS SELECT`. Because the split is hash-based, rerunning gives exactly the same numbers.

---

## Repository structure
```
TelcoChurnProject-Project/
├── README.md
└── Project/Files/
    ├── Telco-Customer-Churn.csv                  # source data (IBM sample)
    ├── Telco_Churn_Reviewer_User_Manual.pdf      # how to view and check the project
    ├── Telco_Churn_Project_Build_Manual.pdf      # step-by-step rebuild guide
    ├── Analysis/                                 # SQL, run in order
    │   ├── 01_clean.sql                          # cleaning, churn flag, tenure bands
    │   ├── 02_churn_drivers.sql                  # churn by segment
    │   ├── 03_train_model.sql                    # 80/20 split + logistic regression
    │   ├── 04_evaluate.sql                       # holdout metrics, calibration, lift
    │   ├── 05_score_customers.sql                # risk tiers + priority list
    │   └── 06_dashboard_tables.sql               # dashboard tables with 95% CIs
    ├── ab_test/
    │   └── ab_test_design.py                     # A/B sample size + break-even cost
    └── Screenshots/
        ├── 01_churn_drivers.jpg
        ├── 02_dashboard_p1_overview_drivers.png
        ├── 03_dashboard_p2_model_retention.png
        └── v1_*.jpg                              # retired v1 results (before/after)
```

---

**Tools:** Google BigQuery · BigQuery ML · SQL · Python · Data Studio (Looker Studio)
**Author:** Ashfiruna Zaman
