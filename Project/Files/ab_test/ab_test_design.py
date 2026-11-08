"""
Retention A/B test sizing and break-even Cost of Retention (COR).

All inputs are either BigQuery outputs (marked SOURCE) or explicit business
assumptions (marked ASSUMPTION). Nothing here is a campaign result.

Run: python3 analysis/ab_test_design.py
"""
from math import sqrt, ceil
from statistics import NormalDist

z = NormalDist().inv_cdf

# ---------------------------------------------------------------- inputs
# SOURCE: churn_scores_v2 (holdout active customers), BigQuery
HIGH_ACTIVE_HOLDOUT = 81          # High-tier (p >= 0.50) active customers in the holdout
MED_ACTIVE_HOLDOUT = 181          # Medium-tier (0.25 <= p < 0.50) active customers
HOLDOUT_SIZE = 1402
TOTAL_BASE = 7043
HIGH_AVG_PROB = 0.6176            # mean predicted churn probability, High-tier actives
MED_AVG_PROB = 0.3598
HIGH_AVG_MONTHLY = 78.75          # mean monthly charges, High-tier actives ($)

# ASSUMPTIONS (change these; they drive every result below)
ALPHA = 0.05                      # two-sided significance level
POWER = 0.80
VALUE_HORIZON_MONTHS = 12         # months of charges a "save" is worth
MARGINS = [0.30, 0.50]            # contribution margin on charges (not revenue)
ABS_REDUCTIONS = [0.05, 0.10, 0.15]  # campaign effect: absolute drop in churn rate


def n_per_group(p_control: float, p_treat: float, alpha=ALPHA, power=POWER) -> int:
    """Two-proportion z-test (normal approximation), equal allocation, two-sided."""
    p_bar = (p_control + p_treat) / 2
    num = (z(1 - alpha / 2) * sqrt(2 * p_bar * (1 - p_bar))
           + z(power) * sqrt(p_control * (1 - p_control) + p_treat * (1 - p_treat))) ** 2
    return ceil(num / (p_control - p_treat) ** 2)


def main():
    scale = TOTAL_BASE / HOLDOUT_SIZE
    high_pool = HIGH_ACTIVE_HOLDOUT * scale
    hm_pool = (HIGH_ACTIVE_HOLDOUT + MED_ACTIVE_HOLDOUT) * scale
    hm_prob = ((HIGH_ACTIVE_HOLDOUT * HIGH_AVG_PROB + MED_ACTIVE_HOLDOUT * MED_AVG_PROB)
               / (HIGH_ACTIVE_HOLDOUT + MED_ACTIVE_HOLDOUT))

    print("== Eligible population (holdout share scaled to the full base; an estimate) ==")
    print(f"High tier:          {HIGH_ACTIVE_HOLDOUT} in holdout -> ~{high_pool:.0f} across {TOTAL_BASE:,} customers")
    print(f"High + Medium tier: {HIGH_ACTIVE_HOLDOUT + MED_ACTIVE_HOLDOUT} in holdout -> ~{hm_pool:.0f}  (avg p = {hm_prob:.3f})")

    print(f"\n== Sample size per arm (alpha={ALPHA}, two-sided; power={POWER}) ==")
    print(f"{'Population':<16}{'Baseline':>9}{'Effect':>8}{'n/arm':>8}{'Total':>8}{'Pool':>7}  Feasible?")
    rows = []
    for label, p0, pool in [("High", HIGH_AVG_PROB, high_pool), ("High+Medium", hm_prob, hm_pool)]:
        for d in ABS_REDUCTIONS:
            n = n_per_group(p0, p0 - d)
            ok = "yes" if 2 * n <= pool else "no"
            rows.append((label, p0, d, n, 2 * n, pool, ok))
            print(f"{label:<16}{p0:>9.1%}{-d:>8.0%}{n:>8}{2*n:>8}{pool:>7.0f}  {ok}")

    print("\n== Break-even cost per treated customer (High tier) ==")
    print("Value of one save = monthly charges x margin x horizon")
    print("Break-even cost per treated customer = absolute churn reduction x value of one save")
    print(f"{'Margin':>7}{'Value/save':>12}" + "".join(f"{f'-{d:.0%} effect':>14}" for d in ABS_REDUCTIONS))
    for m in MARGINS:
        v = HIGH_AVG_MONTHLY * m * VALUE_HORIZON_MONTHS
        print(f"{m:>7.0%}{v:>12.2f}" + "".join(f"{d * v:>14.2f}" for d in ABS_REDUCTIONS))

    print("\nCOR (cost per incremental save) = offer cost per treated customer / absolute churn reduction")
    for cost in [20, 40]:
        print("  $%d offer: " % cost + ", ".join(f"-{d:.0%} -> ${cost / d:,.0f}/save" for d in ABS_REDUCTIONS))
    return rows


if __name__ == "__main__":
    main()
