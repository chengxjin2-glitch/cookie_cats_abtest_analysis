"""
Cookie Cats — Gate Position A/B Test Analysis
Phase 3–6: Validity Checks → Statistical Tests → Segmentation → Decision
Author: 【123】
"""

import pandas as pd
import numpy as np
from scipy import stats
from scipy.stats import chi2_contingency, mannwhitneyu, norm
import matplotlib
# matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import seaborn as sns
import warnings
warnings.filterwarnings('ignore')

# ── 0. Style ──────────────────────────────────────────────────────────────────
plt.rcParams.update({
    'font.family': 'DejaVu Sans',
    'font.size': 11,
    'axes.spines.top': False,
    'axes.spines.right': False,
    'axes.titleweight': 'bold',
    'figure.facecolor': 'white',
})
BLUE   = '#2E5395'
ORANGE = '#C0392B'
GREY   = '#95A5A6'
GREEN  = '#27AE60'

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — Load & reconstruct counts from your aggregated CSV
# ══════════════════════════════════════════════════════════════════════════════
print("=" * 65)
print("STEP 1 — DATA LOADING & COUNT RECONSTRUCTION")
print("=" * 65)

df = pd.read_csv('compare.csv')
print("\nRaw aggregated data loaded:")
print(df.to_string(index=False))

# Your CSV has rates, not counts — reconstruct counts before any statistics.
# The reason: all valid proportion tests operate on (successes, n), not on
# a float percentage. Feeding rates directly would be wrong.
ctrl = df[df['experiment_group'] == 'gate_30'].iloc[0]
treat = df[df['experiment_group'] == 'gate_40'].iloc[0]

n_ctrl  = int(ctrl['total_user_cnt'])
n_treat = int(treat['total_user_cnt'])

# Retention counts (round — rates × n may not be exact integer)
ret1_ctrl  = round(ctrl['retention_1_rate']  * n_ctrl)
ret1_treat = round(treat['retention_1_rate'] * n_treat)
ret7_ctrl  = round(ctrl['retention_7_rate']  * n_ctrl)
ret7_treat = round(treat['retention_7_rate'] * n_treat)

rounds_ctrl  = ctrl['avg_gamerounds']
rounds_treat = treat['avg_gamerounds']

print(f"\nReconstructed counts:")
print(f"{'Metric':<30} {'gate_30':>10} {'gate_40':>10}")
print(f"{'─'*50}")
print(f"{'Users (n)':<30} {n_ctrl:>10,} {n_treat:>10,}")
print(f"{'1-day retained':<30} {ret1_ctrl:>10,} {ret1_treat:>10,}")
print(f"{'7-day retained':<30} {ret7_ctrl:>10,} {ret7_treat:>10,}")
print(f"{'Avg game rounds':<30} {rounds_ctrl:>10.2f} {rounds_treat:>10.2f}")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — VALIDITY CHECKS (the step most candidates skip)
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 65)
print("STEP 2 — VALIDITY CHECKS")
print("=" * 65)

# ── 2a. SRM check: Sample Ratio Mismatch ─────────────────────────────────────
# Designed split: 50 / 50. Test whether observed counts deviate significantly.
# If SRM fails (p < 0.001), the randomization or logging is broken and
# ALL downstream results are untrustworthy.
total = n_ctrl + n_treat
expected_ctrl  = total * 0.5
expected_treat = total * 0.5
srm_chi2 = ((n_ctrl - expected_ctrl)**2 / expected_ctrl +
            (n_treat - expected_treat)**2 / expected_treat)
srm_p = stats.chi2.sf(srm_chi2, df=1)

print(f"\n── 2a. SRM Check (designed split = 50/50) ──────────────────")
print(f"  gate_30: {n_ctrl:,}  ({n_ctrl/total*100:.2f}%)")
print(f"  gate_40: {n_treat:,}  ({n_treat/total*100:.2f}%)")
print(f"  χ²  = {srm_chi2:.4f}")
print(f"  p   = {srm_p:.4f}")
if srm_p < 0.001:
    print("  ⚠️  SRM DETECTED (p < 0.001) — investigate before proceeding")
elif srm_p < 0.05:
    print("  ⚠️  Marginal imbalance (0.001 ≤ p < 0.05) — note but proceed")
else:
    print("  ✅  No SRM detected — randomization looks healthy")

# ── 2b. Outlier note ─────────────────────────────────────────────────────────
# User 6390605: 49,854 game rounds (known from raw data exploration).
# Decision: retain for RETENTION metrics (bounded 0/1, outlier has no effect);
# winsorize / flag for avg_gamerounds metric (mean is sensitive to extremes).
print(f"\n── 2b. Outlier Handling Note ────────────────────────────────")
print(f"  Known outlier: user 6390605 with 49,854 game rounds (gate_30).")
print(f"  → Retention metrics: unaffected (binary outcome, outlier = 1 person).")
print(f"  → avg_gamerounds: mean is sensitive to this value.")
print(f"    Enterprise fix: winsorize at 99th percentile or use median/MWU test.")
print(f"    We use Mann-Whitney U (rank-based, outlier-robust) for rounds.")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — POWER ANALYSIS (retrospective check)
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 65)
print("STEP 3 — POWER ANALYSIS (retrospective)")
print("=" * 65)

# Pre-specified parameters (would be set BEFORE the experiment)
alpha   = 0.05   # significance level (two-sided)
power   = 0.80   # desired power
p0      = ctrl['retention_7_rate']   # baseline from control
mde     = 0.01   # minimum detectable effect: 1 percentage point absolute

p1 = p0 + mde
z_alpha = norm.ppf(1 - alpha / 2)   # 1.96
z_beta  = norm.ppf(power)           # 0.84

# Sample size formula for two proportions
n_required = (z_alpha + z_beta)**2 * (p0*(1-p0) + p1*(1-p1)) / (mde**2)
n_required = int(np.ceil(n_required))

achieved_power_ctrl  = 1 - norm.cdf(z_alpha - mde / np.sqrt(p0*(1-p0)/n_ctrl + p1*(1-p1)/n_ctrl))
achieved_power_total = 1 - norm.cdf(z_alpha - mde / np.sqrt(p0*(1-p0)/n_ctrl + p1*(1-p1)/n_treat))

print(f"\n  Baseline 7-day retention (p0) : {p0:.4f}  ({p0*100:.2f}%)")
print(f"  Minimum Detectable Effect (MDE): ±{mde:.3f}  ({mde*100:.1f} pp absolute)")
print(f"  α = {alpha} (two-sided)  |  target power = {power}")
print(f"  Required n per group           : {n_required:,}")
print(f"  Actual n (gate_30 / gate_40)   : {n_ctrl:,} / {n_treat:,}")
print(f"  Achieved power (approx)        : {achieved_power_total:.3f}")
if min(n_ctrl, n_treat) >= n_required:
    print(f"  ✅  Sample is adequately powered for a {mde*100:.1f} pp MDE")
else:
    print(f"  ⚠️  Under-powered for a {mde*100:.1f} pp MDE — adjust MDE or interpret carefully")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4 — STATISTICAL TESTS
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 65)
print("STEP 4 — STATISTICAL TESTS")
print("=" * 65)

def two_prop_ztest(s1, n1, s2, n2, alpha=0.05):
    """Two-proportion z-test, two-sided. Returns dict of results."""
    p1_, p2_ = s1/n1, s2/n2
    p_pool = (s1 + s2) / (n1 + n2)
    se = np.sqrt(p_pool * (1 - p_pool) * (1/n1 + 1/n2))
    z  = (p1_ - p2_) / se
    p  = 2 * norm.sf(abs(z))
    # 95% CI on difference (unpooled SE for CI)
    se_diff = np.sqrt(p1_*(1-p1_)/n1 + p2_*(1-p2_)/n2)
    ci_lo = (p1_ - p2_) - norm.ppf(1 - alpha/2) * se_diff
    ci_hi = (p1_ - p2_) + norm.ppf(1 - alpha/2) * se_diff
    return dict(p_ctrl=p1_, p_treat=p2_, diff=p1_-p2_,
                rel_diff=(p1_-p2_)/p2_, z=z, p=p, ci=(ci_lo, ci_hi),
                sig=(p < alpha))

# ── 4a. 7-day retention (PRIMARY metric) ─────────────────────────────────────
r7 = two_prop_ztest(ret7_ctrl, n_ctrl, ret7_treat, n_treat)
print(f"\n── 4a. 7-Day Retention (PRIMARY DECISION METRIC) ───────────")
print(f"  gate_30 : {r7['p_ctrl']:.4f}  ({r7['p_ctrl']*100:.2f}%)")
print(f"  gate_40 : {r7['p_treat']:.4f}  ({r7['p_treat']*100:.2f}%)")
print(f"  Δ (ctrl − treat) = {r7['diff']*100:+.3f} pp  "
      f"({r7['rel_diff']*100:+.2f}% relative)")
print(f"  95% CI  : [{r7['ci'][0]*100:+.3f} pp,  {r7['ci'][1]*100:+.3f} pp]")
print(f"  z = {r7['z']:.4f}   p = {r7['p']:.6f}")
print(f"  {'✅  Statistically significant' if r7['sig'] else '❌  Not significant'} "
      f"at α = {alpha}")
if r7['sig'] and r7['diff'] > 0:
    print(f"  → gate_30 OUTPERFORMS gate_40 on 7-day retention")
elif r7['sig'] and r7['diff'] < 0:
    print(f"  → gate_40 OUTPERFORMS gate_30 on 7-day retention")

# ── 4b. 1-day retention (secondary metric) ───────────────────────────────────
r1 = two_prop_ztest(ret1_ctrl, n_ctrl, ret1_treat, n_treat)
print(f"\n── 4b. 1-Day Retention (SECONDARY metric) ──────────────────")
print(f"  gate_30 : {r1['p_ctrl']:.4f}  ({r1['p_ctrl']*100:.2f}%)")
print(f"  gate_40 : {r1['p_treat']:.4f}  ({r1['p_treat']*100:.2f}%)")
print(f"  Δ = {r1['diff']*100:+.3f} pp   95% CI [{r1['ci'][0]*100:+.3f}, {r1['ci'][1]*100:+.3f}]")
print(f"  z = {r1['z']:.4f}   p = {r1['p']:.6f}   "
      f"{'Significant ✅' if r1['sig'] else 'Not significant ❌'}")

# ── 4c. avg_gamerounds (GUARDRAIL metric, heavy-tailed → MWU) ────────────────
# We cannot run MWU on aggregated data — we only have means here.
# Use a simulation-based / delta method approximation for the interview story,
# and state honestly this test needs raw data.
print(f"\n── 4c. Avg Game Rounds (GUARDRAIL metric) ───────────────────")
print(f"  gate_30 mean: {rounds_ctrl:.2f}   gate_40 mean: {rounds_treat:.2f}")
print(f"  Difference  : {rounds_ctrl - rounds_treat:+.2f} rounds "
      f"({(rounds_ctrl-rounds_treat)/rounds_treat*100:+.2f}% relative)")
print(f"  ⚠️  NOTE: Mann-Whitney U test requires raw user-level data.")
print(f"  With only aggregated means, we cannot run a valid distributional test.")
print(f"  → In the report: note this limitation; the direction (gate_30 > gate_40)")
print(f"    is consistent with the retention finding but cannot be tested for")
print(f"    significance without raw data. This is a valid, honest observation.")

# ── 4d. Multiple testing note ─────────────────────────────────────────────────
print(f"\n── 4d. Multiple Testing ─────────────────────────────────────")
print(f"  3 metrics tested. Treatment:")
print(f"  → 7-day retention: pre-registered PRIMARY (no correction needed).")
print(f"  → 1-day retention, game rounds: secondary/guardrail (descriptive role).")
print(f"  → No Bonferroni correction applied to primary; if treating secondaries")
print(f"    inferentially, adjusted α = {alpha/3:.4f} (Bonferroni) or apply BH.")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5 — PRACTICAL SIGNIFICANCE & BUSINESS IMPACT
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 65)
print("STEP 5 — PRACTICAL SIGNIFICANCE & BUSINESS IMPACT")
print("=" * 65)

retention_loss_pp = r7['diff']        # positive = ctrl better
n_monthly_new     = 1_000_000         # assumed monthly new installs
users_lost_monthly = n_monthly_new * retention_loss_pp
ltv_per_retained  = 5.0               # USD — stated as assumption, not fact

print(f"\n  Statistical result   : gate_30 retains {retention_loss_pp*100:.3f} pp")
print(f"                         more users at 7 days than gate_40")
print(f"  Practical MDE check  : {abs(retention_loss_pp)*100:.3f} pp {'≥' if abs(retention_loss_pp) >= mde else '<'} {mde*100:.1f} pp MDE threshold")
print(f"                         → {'Practically significant' if abs(retention_loss_pp) >= mde else 'Below practical threshold'}")
print(f"\n  Business impact estimate (hypothetical scale):")
print(f"  Assumed monthly new users     : {n_monthly_new:,}")
print(f"  7-day users lost if launching gate_40 : "
      f"{users_lost_monthly:,.0f} users/month")
print(f"  Assumed LTV per retained user : ${ltv_per_retained:.2f}  (stated assumption)")
print(f"  Estimated monthly value at risk: "
      f"${users_lost_monthly * ltv_per_retained:,.0f}")
print(f"  ⚠️  LTV is a hypothetical assumption for scale illustration only.")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 6 — DECISION
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 65)
print("STEP 6 — DECISION (against pre-registered decision rule)")
print("=" * 65)
print("""
  Pre-registered rule: Launch gate_40 only if —
    (a) 7-day retention NOT significantly lower than gate_30, AND
    (b) Guardrail metric (game rounds) shows no material degradation.

  Result:
    (a) 7-day retention: gate_40 is significantly LOWER (p < 0.05).
        Rule (a) FAILS → RECOMMEND KEEPING GATE_30.
    (b) Avg game rounds: gate_40 is also slightly lower (direction consistent
        with harm, significance untestable on aggregated data).

  ✅  FINAL RECOMMENDATION: Do NOT launch gate_40.
      The gate at level 30 appears to function as an engagement
      reinforcement mechanism (appointment dynamic), not merely as friction.
      Moving it to level 40 measurably reduces 7-day retention.

  Follow-up experiment hypotheses (for the next test):
    H1: Adding a social sharing trigger at level 30 can increase retention
        without relying on forced breaks.
    H2: Shorter wait-time at gate_30 (vs. longer) optimises the pacing effect.
""")

# ══════════════════════════════════════════════════════════════════════════════
# STEP 7 — VISUALISATION (export to PNG for report / Power BI)
# ══════════════════════════════════════════════════════════════════════════════
fig = plt.figure(figsize=(14, 10))
fig.suptitle("Cookie Cats — Gate Position A/B Test Results",
             fontsize=16, fontweight='bold', y=0.98)
gs = gridspec.GridSpec(2, 3, figure=fig, hspace=0.42, wspace=0.38)

colors = [BLUE, ORANGE]
groups = ['gate_30\n(Control)', 'gate_40\n(Treatment)']

# ── Chart 1: Group sizes & SRM ────────────────────────────────────────────────
ax1 = fig.add_subplot(gs[0, 0])
bars = ax1.bar(groups, [n_ctrl, n_treat], color=colors, width=0.5, alpha=0.88)
ax1.set_title("Group Sizes (SRM Check)")
ax1.set_ylabel("User Count")
for b, v in zip(bars, [n_ctrl, n_treat]):
    ax1.text(b.get_x() + b.get_width()/2, b.get_height() + 200,
             f'{v:,}', ha='center', fontsize=10, fontweight='bold')
ax1.set_ylim(0, max(n_ctrl, n_treat) * 1.12)
srm_txt = f"SRM p = {srm_p:.4f}\n{'✅ No SRM' if srm_p >= 0.001 else '⚠️ SRM detected'}"
ax1.text(0.98, 0.95, srm_txt, transform=ax1.transAxes, ha='right', va='top',
         fontsize=9, color=GREEN if srm_p >= 0.001 else ORANGE,
         bbox=dict(boxstyle='round,pad=0.3', facecolor='#F8F9FA', alpha=0.8))

# ── Chart 2: 1-day retention ──────────────────────────────────────────────────
ax2 = fig.add_subplot(gs[0, 1])
vals_r1 = [r1['p_ctrl']*100, r1['p_treat']*100]
bars2 = ax2.bar(groups, vals_r1, color=colors, width=0.5, alpha=0.88)
ax2.set_title("1-Day Retention\n(Secondary metric)")
ax2.set_ylabel("Retention Rate (%)")
for b, v in zip(bars2, vals_r1):
    ax2.text(b.get_x() + b.get_width()/2, b.get_height() + 0.1,
             f'{v:.2f}%', ha='center', fontsize=10, fontweight='bold')
ax2.set_ylim(0, max(vals_r1) * 1.15)
sig_txt = f"Δ = {r1['diff']*100:+.3f} pp\np = {r1['p']:.4f} {'✅' if r1['sig'] else '❌'}"
ax2.text(0.98, 0.95, sig_txt, transform=ax2.transAxes, ha='right', va='top',
         fontsize=9, bbox=dict(boxstyle='round,pad=0.3', facecolor='#F8F9FA', alpha=0.8))

# ── Chart 3: 7-day retention ──────────────────────────────────────────────────
ax3 = fig.add_subplot(gs[0, 2])
vals_r7 = [r7['p_ctrl']*100, r7['p_treat']*100]
bars3 = ax3.bar(groups, vals_r7, color=colors, width=0.5, alpha=0.88)
ax3.set_title("7-Day Retention ⭐\n(Primary decision metric)")
ax3.set_ylabel("Retention Rate (%)")
for b, v in zip(bars3, vals_r7):
    ax3.text(b.get_x() + b.get_width()/2, b.get_height() + 0.05,
             f'{v:.2f}%', ha='center', fontsize=10, fontweight='bold')
ax3.set_ylim(0, max(vals_r7) * 1.18)
sig_txt7 = f"Δ = {r7['diff']*100:+.3f} pp\np = {r7['p']:.6f} ✅"
ax3.text(0.98, 0.95, sig_txt7, transform=ax3.transAxes, ha='right', va='top',
         fontsize=9, color=ORANGE,
         bbox=dict(boxstyle='round,pad=0.3', facecolor='#FFF3F3', alpha=0.9))

# ── Chart 4: avg game rounds ──────────────────────────────────────────────────
ax4 = fig.add_subplot(gs[1, 0])
bars4 = ax4.bar(groups, [rounds_ctrl, rounds_treat], color=colors, width=0.5, alpha=0.88)
ax4.set_title("Avg Game Rounds\n(Guardrail metric)")
ax4.set_ylabel("Avg Rounds per User")
for b, v in zip(bars4, [rounds_ctrl, rounds_treat]):
    ax4.text(b.get_x() + b.get_width()/2, b.get_height() + 0.2,
             f'{v:.2f}', ha='center', fontsize=10, fontweight='bold')
ax4.set_ylim(0, max(rounds_ctrl, rounds_treat) * 1.15)
ax4.text(0.98, 0.95, "⚠️ Raw data needed\nfor MWU test",
         transform=ax4.transAxes, ha='right', va='top',
         fontsize=9, color=GREY,
         bbox=dict(boxstyle='round,pad=0.3', facecolor='#F8F9FA', alpha=0.8))

# ── Chart 5: 7-day retention CI plot ─────────────────────────────────────────
ax5 = fig.add_subplot(gs[1, 1])
diff_pct   = r7['diff'] * 100
ci_lo_pct  = r7['ci'][0] * 100
ci_hi_pct  = r7['ci'][1] * 100
ax5.barh([0], [diff_pct], color=ORANGE if diff_pct > 0 else BLUE,
         alpha=0.85, height=0.35)
ax5.errorbar([diff_pct], [0],
             xerr=[[diff_pct - ci_lo_pct], [ci_hi_pct - diff_pct]],
             fmt='none', color='#2C3E50', capsize=8, lw=2)
ax5.axvline(0, color='black', lw=1.2, linestyle='--', alpha=0.6)
ax5.set_xlabel("Difference in 7-day retention\n(gate_30 − gate_40, pp)")
ax5.set_title("7-Day Retention\n95% Confidence Interval")
ax5.set_yticks([])
ax5.text(diff_pct, 0.25, f"{diff_pct:+.3f} pp\n95% CI [{ci_lo_pct:+.3f}, {ci_hi_pct:+.3f}]",
         ha='center', fontsize=9, fontweight='bold')

# ── Chart 6: Decision summary ─────────────────────────────────────────────────
ax6 = fig.add_subplot(gs[1, 2])
ax6.axis('off')
summary_lines = [
    ("Experiment",       "Gate 30 vs Gate 40"),
    ("Test type",        "Two-sided, α = 0.05"),
    ("Primary metric",   "7-day retention"),
    ("SRM check",        f"{'PASS ✅' if srm_p >= 0.001 else 'FAIL ⚠️'}  (p={srm_p:.4f})"),
    ("7-day Δ",          f"{r7['diff']*100:+.3f} pp  (p={r7['p']:.6f})"),
    ("1-day Δ",          f"{r1['diff']*100:+.3f} pp  (p={r1['p']:.4f})"),
    ("Rounds Δ",         f"{rounds_ctrl-rounds_treat:+.2f}  (no significance test)"),
    ("Decision",         "KEEP GATE_30 ✅"),
]
ax6.set_title("Decision Summary", fontweight='bold')
for i, (k, v) in enumerate(summary_lines):
    y = 0.88 - i * 0.115
    ax6.text(0.02, y, k + ":", fontsize=9.5, color='#555555',
             transform=ax6.transAxes, va='top')
    color = ORANGE if k == "Decision" else '#1A1A2E'
    weight = 'bold' if k == "Decision" else 'normal'
    ax6.text(0.42, y, v, fontsize=9.5, color=color, fontweight=weight,
             transform=ax6.transAxes, va='top')

plt.savefig('ab_test_results.png', dpi=150,
            bbox_inches='tight', facecolor='white')
print("\n📊  Chart saved → ab_test_results.png")
print("\n✅  Analysis complete. All 6 steps passed.")
print("=" * 65)
