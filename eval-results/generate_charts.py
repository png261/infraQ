"""
Generate all 8 thesis evaluation charts.
Output: PDF (vector, LaTeX-ready) + PNG (preview) in ./charts/
Background: white throughout.
"""
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path

# ── paths ─────────────────────────────────────────────────────────────────────
ROOT  = Path(__file__).parent
MA_CSV  = ROOT / 'iac-eval-local-core-full'  / 'iac_eval_local_results.csv'
LLM_CSV = ROOT / 'iac-eval-llm-gpt55-match-local' / 'iac_eval_llm_results.csv'
OUT   = ROOT / 'charts'
OUT.mkdir(exist_ok=True)

# ── colours ───────────────────────────────────────────────────────────────────
BLUE   = '#4C9BE8'   # GPT-5.5 One-shot
ORANGE = '#E8784C'   # Multi-Agent (Ours)
GREEN  = '#27AE60'   # improvement
FONT   = 'DejaVu Sans'

plt.rcParams.update({
    'font.family':       FONT,
    'axes.spines.top':   False,
    'axes.spines.right': False,
    'axes.spines.left':  True,
    'axes.spines.bottom':True,
    'axes.edgecolor':    '#bbbbbb',
    'axes.grid':         True,
    'axes.grid.axis':    'y',
    'grid.color':        '#e8e8e8',
    'grid.linewidth':    0.8,
    'axes.axisbelow':    True,
    'figure.facecolor':  'white',
    'axes.facecolor':    'white',
    'savefig.facecolor': 'white',
    'savefig.edgecolor': 'none',
})

# ── load & prepare data ───────────────────────────────────────────────────────
ma  = pd.read_csv(MA_CSV)
llm = pd.read_csv(LLM_CSV)

DIFFS = [1, 2, 3, 4, 5, 6]
N_PER_DIFF = {d: int((ma['difficulty'] == d).sum()) for d in DIFFS}

# pass
ma['pass_bool']  = ma['pass'].astype(str).str.lower() == 'true'
llm['pass_bool'] = llm['pass'].astype(str).str.lower() == 'true'

# plan pass: not a terraform_plan failure
ma['plan_pass']  = ~(ma['failure_category'].astype(str).str.strip() == 'terraform_plan')
llm['plan_pass'] = llm['official_plan_success'].astype(str).str.lower() == 'true'

# failure category buckets (for chart 6)
FAIL_MAP = {
    'opa_rule_failure':  'opa_rule',
    'terraform_plan':    'plan',
    'artifact_incomplete': 'artifact',
    'opa_error':         'opa_error',
}
ma['fail_bucket']  = ma['failure_category'].map(FAIL_MAP)
llm['fail_bucket'] = llm['failure_category'].map(FAIL_MAP)

# ── helper ────────────────────────────────────────────────────────────────────
def save(fig, stem):
    fig.tight_layout()
    for ext in ('pdf', 'png'):
        p = OUT / f'{stem}.{ext}'
        fig.savefig(p, format=ext, bbox_inches='tight',
                    facecolor='white', dpi=300 if ext == 'png' else None)
    plt.close(fig)
    print(f'  saved {stem}.pdf + .png')

def make_fig(w=11, h=6.5):
    fig, ax = plt.subplots(figsize=(w, h))
    return fig, ax

# ═══════════════════════════════════════════════════════════════════════════════
# 1  Overall summary (table figure)
# ═══════════════════════════════════════════════════════════════════════════════
def chart1():
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.axis('off')

    n = len(ma)
    ma_opa  = ma['pass_bool'].sum()
    llm_opa = llm['pass_bool'].sum()
    ma_plan  = ma['plan_pass'].sum()
    llm_plan = llm['plan_pass'].sum()
    ma_bleu  = ma['bleuScore'].mean()
    llm_bleu = llm['bleu_score'].mean()
    ma_dur   = ma['durationSeconds'].mean()
    llm_dur  = llm['duration_seconds'].mean()

    rows = [
        ('Total Tasks',           f'{n}',                        f'{n}'),
        ('OPA Pass (count)',       f'{llm_opa}',                  f'{ma_opa}'),
        ('OPA Pass Rate',          f'{llm_opa/n*100:.1f}%',       f'{ma_opa/n*100:.1f}%'),
        ('Terraform Plan Pass',    f'{llm_plan}  ({llm_plan/n*100:.1f}%)',
                                   f'{ma_plan}  ({ma_plan/n*100:.1f}%)'),
        ('Avg BLEU Score',         f'{llm_bleu:.3f}',
                                   f'{ma_bleu:.3f}  (+{(ma_bleu/llm_bleu-1)*100:.0f}%)'),
        ('Avg Duration / task',    f'{llm_dur:.1f} s',            f'{ma_dur:.1f} s'),
        ('Overall Improvement',    '—',
                                   f'+{ma_opa/n*100-llm_opa/n*100:.1f} pp  '
                                   f'(+{(ma_opa/llm_opa-1)*100:.0f}% relative)'),
    ]

    col_labels  = ['Metric', 'GPT-5.5 One-shot', 'Multi-Agent (Ours)']
    hdr_colors  = ['#9eaab5', BLUE, ORANGE]
    xs   = [0.02, 0.36, 0.67]
    ws   = [0.32, 0.29, 0.31]
    row_h, hdr_h = 0.089, 0.105
    top  = 0.90

    # header row
    for lbl, hc, x, w in zip(col_labels, hdr_colors, xs, ws):
        rect = plt.Rectangle((x, top - hdr_h), w - 0.01, hdr_h,
                              transform=ax.transAxes, color=hc, clip_on=False)
        ax.add_patch(rect)
        ax.text(x + (w-0.01)/2, top - hdr_h/2, lbl,
                transform=ax.transAxes, ha='center', va='center',
                fontsize=12, fontweight='bold', color='white')

    row_bgs = ['white', '#f5f5f5']
    txt_colors = ['#333333', BLUE, ORANGE]
    for r, (met, lv, mv) in enumerate(rows):
        y = top - hdr_h - (r+1)*row_h
        bg = row_bgs[r % 2]
        for x, w in zip(xs, ws):
            ax.add_patch(plt.Rectangle((x, y), w-0.01, row_h,
                         transform=ax.transAxes, color=bg, clip_on=False))
        for val, tc, x, w in zip([met, lv, mv], txt_colors, xs, ws):
            ax.text(x+(w-0.01)/2, y+row_h/2, val,
                    transform=ax.transAxes, ha='center', va='center',
                    fontsize=11, color=tc,
                    fontweight='bold' if tc != '#333333' else 'normal')

    save(fig, '1_overall_summary')

# ═══════════════════════════════════════════════════════════════════════════════
# 2  OPA Pass Rate by difficulty
# ═══════════════════════════════════════════════════════════════════════════════
def chart2():
    fig, ax = make_fig()
    x  = np.arange(len(DIFFS))
    bw = 0.37

    llm_r = [llm[llm.difficulty == d]['pass_bool'].mean()*100 for d in DIFFS]
    ma_r  = [ma [ma .difficulty == d]['pass_bool'].mean()*100 for d in DIFFS]

    b1 = ax.bar(x - bw/2, llm_r, bw, color=BLUE,   label='GPT-5.5 One-shot', zorder=3)
    b2 = ax.bar(x + bw/2, ma_r,  bw, color=ORANGE, label='Multi-Agent (Ours)', zorder=3)

    for bar, v in zip(b1, llm_r):
        ax.text(bar.get_x()+bar.get_width()/2, v+1.2, f'{v:.0f}%',
                ha='center', va='bottom', fontsize=9.5, fontweight='bold')
    for bar, v in zip(b2, ma_r):
        ax.text(bar.get_x()+bar.get_width()/2, v+1.2, f'{v:.0f}%',
                ha='center', va='bottom', fontsize=9.5, fontweight='bold')

    for i, (ll, ma_v) in enumerate(zip(llm_r, ma_r)):
        delta = ma_v - ll
        mid_x = x[i] + bw/2
        ax.annotate('', xy=(mid_x, ma_v+3), xytext=(mid_x, ll+3),
                    arrowprops=dict(arrowstyle='->', color=GREEN, lw=2.0))
        ax.text(mid_x+0.2, (ll+ma_v)/2+2, f'+{delta:.0f}pp',
                color=GREEN, fontsize=9, fontweight='bold')

    ax.set_xticks(x)
    ax.set_xticklabels([f'Difficulty {d}\n(n={N_PER_DIFF[d]})' for d in DIFFS], fontsize=10)
    ax.set_ylim(0, 113)
    ax.set_ylabel('OPA Pass Rate (%)', fontsize=11)
    ax.legend(fontsize=10, framealpha=0.9)
    save(fig, '2_pass_rate_by_difficulty')

# ═══════════════════════════════════════════════════════════════════════════════
# 3  Improvement delta
# ═══════════════════════════════════════════════════════════════════════════════
def chart3():
    fig, ax = make_fig(9, 6)

    llm_r  = [llm[llm.difficulty == d]['pass_bool'].mean()*100 for d in DIFFS]
    ma_r   = [ma [ma .difficulty == d]['pass_bool'].mean()*100 for d in DIFFS]
    deltas = [m - l for m, l in zip(ma_r, llm_r)]

    bars = ax.bar(DIFFS, deltas, color=GREEN, width=0.55, zorder=3)
    for bar, delta in zip(bars, deltas):
        ax.text(bar.get_x()+bar.get_width()/2, delta+0.4,
                f'+{delta:.1f} pp', ha='center', va='bottom',
                fontsize=11, fontweight='bold', color=GREEN)

    ax.set_xlabel('Difficulty Level', fontsize=11)
    ax.set_ylabel('Pass Rate Improvement (percentage points)', fontsize=11)
    ax.set_ylim(0, max(deltas)*1.20)
    ax.set_xticks(DIFFS)
    save(fig, '3_improvement_delta')

# ═══════════════════════════════════════════════════════════════════════════════
# 4  BLEU by difficulty
# ═══════════════════════════════════════════════════════════════════════════════
def chart4():
    fig, ax = make_fig()

    llm_b = [llm[llm.difficulty == d]['bleu_score'].mean() for d in DIFFS]
    ma_b  = [ma [ma .difficulty == d]['bleuScore'].mean()   for d in DIFFS]

    ax.fill_between(DIFFS, llm_b, ma_b, alpha=0.10, color=ORANGE)
    ax.plot(DIFFS, llm_b, 'o-', color=BLUE,   lw=2.2, ms=8, label='GPT-5.5 One-shot')
    ax.plot(DIFFS, ma_b,  's-', color=ORANGE, lw=2.2, ms=8, label='Multi-Agent (Ours)')

    for d, v in zip(DIFFS, llm_b):
        ax.text(d-0.1, v-0.016, f'{v:.3f}', color=BLUE,   fontsize=9, fontweight='bold', ha='right')
    for d, v in zip(DIFFS, ma_b):
        ax.text(d+0.1, v+0.008, f'{v:.3f}', color=ORANGE, fontsize=9, fontweight='bold', ha='left')

    ax.set_xlabel('Difficulty Level', fontsize=11)
    ax.set_ylabel('Average BLEU Score', fontsize=11)
    ax.set_xticks(DIFFS)
    ax.legend(fontsize=10)
    save(fig, '4_bleu_by_difficulty')

# ═══════════════════════════════════════════════════════════════════════════════
# 5  Terraform Plan Pass Rate by difficulty
# ═══════════════════════════════════════════════════════════════════════════════
def chart5():
    fig, ax = make_fig()
    x  = np.arange(len(DIFFS))
    bw = 0.37

    llm_p = [llm[llm.difficulty == d]['plan_pass'].mean()*100 for d in DIFFS]
    ma_p  = [ma [ma .difficulty == d]['plan_pass'].mean()*100 for d in DIFFS]

    b1 = ax.bar(x - bw/2, llm_p, bw, color=BLUE,   label='GPT-5.5 One-shot', zorder=3)
    b2 = ax.bar(x + bw/2, ma_p,  bw, color=ORANGE, label='Multi-Agent (Ours)', zorder=3)

    for bar, v in zip(b1, llm_p):
        ax.text(bar.get_x()+bar.get_width()/2, v+0.5, f'{v:.0f}%',
                ha='center', va='bottom', fontsize=9.5, fontweight='bold')
    for bar, v in zip(b2, ma_p):
        ax.text(bar.get_x()+bar.get_width()/2, v+0.5, f'{v:.0f}%',
                ha='center', va='bottom', fontsize=9.5, fontweight='bold')

    ax.set_xticks(x)
    ax.set_xticklabels([f'Difficulty {d}' for d in DIFFS], fontsize=10)
    ax.set_ylim(0, 116)
    ax.set_ylabel('Terraform Plan Pass Rate (%)', fontsize=11)
    ax.legend(fontsize=10)
    save(fig, '5_plan_pass_by_difficulty')

# ═══════════════════════════════════════════════════════════════════════════════
# 6  Failure category breakdown
# ═══════════════════════════════════════════════════════════════════════════════
def chart6():
    fig, ax = make_fig(11, 5)
    ax.grid(False)

    ma_fail  = ma [~ma ['pass_bool']]
    llm_fail = llm[~llm['pass_bool']]

    CATS   = ['opa_rule', 'plan', 'artifact', 'opa_error']
    CLRS   = ['#E74C3C', '#E67E22', '#F1C40F', '#9B59B6']
    LABELS = ['OPA Rule Failure', 'Terraform Plan', 'Artifact Incomplete', 'OPA Error']

    def row_data(sub, col):
        total = len(sub)
        out = {}
        for cat in CATS:
            cnt = int((sub[col] == cat).sum())
            out[cat] = (cnt, cnt/total*100 if total else 0)
        return total, out

    ma_total,  ma_d  = row_data(ma_fail,  'fail_bucket')
    llm_total, llm_d = row_data(llm_fail, 'fail_bucket')

    ys     = [0.68, 0.22]
    bar_h  = 0.32
    labels_row = ['Multi-Agent (Ours)', 'GPT-5.5 One-shot']

    for (label, data, total), y in zip(
            [(labels_row[0], ma_d, ma_total),
             (labels_row[1], llm_d, llm_total)],
            ys):
        left = 0.0
        for cat, col, lbl in zip(CATS, CLRS, LABELS):
            cnt, pct = data[cat]
            if pct > 0:
                ax.barh(y, pct, bar_h, left=left, color=col, zorder=3)
                if pct > 5:
                    ax.text(left+pct/2, y, f'{cnt}\n({pct:.0f}%)',
                            ha='center', va='center', fontsize=10,
                            fontweight='bold', color='white')
            left += pct
        ax.text(-1.5, y, label, ha='right', va='center', fontsize=11)

    ax.set_xlim(0, 100)
    ax.set_xlabel('% of Total Failures', fontsize=11)
    ax.set_yticks([])
    ax.spines['left'].set_visible(False)
    patches = [mpatches.Patch(color=c, label=l) for c, l in zip(CLRS, LABELS)]
    ax.legend(handles=patches, loc='upper right', fontsize=9, framealpha=0.9,
              bbox_to_anchor=(1.0, 0.55))
    save(fig, '6_failure_categories')

# ═══════════════════════════════════════════════════════════════════════════════
# 7  Duration by difficulty
# ═══════════════════════════════════════════════════════════════════════════════
def chart7():
    fig, ax = make_fig()

    ma_dur  = [ma [ma .difficulty == d]['durationSeconds'].mean() for d in DIFFS]
    llm_dur = [llm[llm.difficulty == d]['duration_seconds'].mean() for d in DIFFS]

    ax.fill_between(DIFFS, llm_dur, ma_dur,  alpha=0.10, color=ORANGE)
    ax.fill_between(DIFFS, 0,       llm_dur, alpha=0.07, color=BLUE)

    ax.plot(DIFFS, llm_dur, 'o-', color=BLUE,   lw=2.2, ms=8, label='GPT-5.5 One-shot')
    ax.plot(DIFFS, ma_dur,  's-', color=ORANGE, lw=2.2, ms=8, label='Multi-Agent (Ours)')

    for d, v in zip(DIFFS, llm_dur):
        ax.text(d, v+8, f'{v:.0f}s', color=BLUE,   ha='center', fontsize=9.5, fontweight='bold')
    for d, v in zip(DIFFS, ma_dur):
        ax.text(d, v+12, f'{v:.0f}s', color=ORANGE, ha='center', fontsize=9.5, fontweight='bold')

    ax.set_xlabel('Difficulty Level', fontsize=11)
    ax.set_ylabel('Average Duration (seconds)', fontsize=11)
    ax.set_xticks(DIFFS)
    ax.legend(fontsize=10)
    save(fig, '7_duration_by_difficulty')

# ═══════════════════════════════════════════════════════════════════════════════
# 8  Cumulative pass count
# ═══════════════════════════════════════════════════════════════════════════════
def chart8():
    fig, ax = make_fig(12, 7)

    ma_cum  = ma ['pass_bool'].cumsum().values
    llm_cum = llm['pass_bool'].cumsum().values
    xs = np.arange(len(ma))

    ax.fill_between(xs, llm_cum, ma_cum, alpha=0.16, color=GREEN,
                    label=f'+{int(ma_cum[-1]-llm_cum[-1])} additional correct (multi-agent)')
    ax.plot(xs, llm_cum, color=BLUE,   lw=2.0, label='GPT-5.5 One-shot')
    ax.plot(xs, ma_cum,  color=ORANGE, lw=2.0, label='Multi-Agent (Ours)')

    n = len(ma)
    ax.axhline(ma_cum[-1],  color=ORANGE, ls='--', lw=1.0, alpha=0.5)
    ax.axhline(llm_cum[-1], color=BLUE,   ls='--', lw=1.0, alpha=0.5)

    ax.text(n+3, ma_cum[-1],
            f"{int(ma_cum[-1])} ({ma_cum[-1]/n*100:.1f}%)",
            color=ORANGE, va='center', fontsize=10, fontweight='bold')
    ax.text(n+3, llm_cum[-1],
            f"{int(llm_cum[-1])} ({llm_cum[-1]/n*100:.1f}%)",
            color=BLUE, va='center', fontsize=10, fontweight='bold')

    ax.set_xlabel('Task Index', fontsize=11)
    ax.set_ylabel('Cumulative Passes', fontsize=11)
    ax.legend(fontsize=10, loc='upper left')
    ax.set_xlim(0, n+50)
    save(fig, '8_cumulative_pass')


# ── run ───────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print('Generating charts (white background, PDF + PNG) …')
    chart1()
    chart2()
    chart3()
    chart4()
    chart5()
    chart6()
    chart7()
    chart8()
    print('Done — files in ./charts/')
