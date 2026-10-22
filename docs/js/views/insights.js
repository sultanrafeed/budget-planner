import * as D from "../dates.js";
import * as E from "../engine.js";
import { cat } from "../categories.js";
import { money, money0, centsToInput, parseMoney } from "../money.js";
import { esc, catIcon, progress, stat } from "../ui.js";
import { donut, bars, lines } from "../charts.js";
import { ui } from "../state.js";

const PAGES = { spending: "Spending", reports: "Reports", whatIf: "What if" };

export function render(ctx) {
  const page = PAGES[ui.insightsPage] ? ui.insightsPage : "spending";
  return `<div class="screen">
    <div class="large-title">Insights</div>
    <div class="segmented" role="tablist">${Object.entries(PAGES).map(([k, label]) =>
      `<button role="tab" aria-selected="${k === page}" class="${k === page ? "on" : ""}" data-action="insightsPage" data-page="${k}">${label}</button>`).join("")}</div>
    ${{ spending, reports, whatIf }[page](ctx)}
  </div>`;
}

export function spendRange(today) {
  return D.shiftPeriod(D.periodOf(ui.spendPeriod, today), ui.spendPeriod, ui.spendOffset);
}

export function rangeLabel(range, period) {
  return period === "monthly" ? D.fmtMonthYear(range.start) : `${D.fmtDayMonth(range.start)} – ${D.fmtDayMonth(D.addDays(range.end, -1))}`;
}

// ---- Spending ------------------------------------------------------------------

function spending({ data, today }) {
  const range = spendRange(today);
  const items = E.spendingByCategory(data, range);
  const total = items.reduce((s, x) => s + x.amount, 0);
  const t = E.totals(data, range);
  const daily = E.dailySpending(data, range);
  const weekly = ui.spendPeriod === "weekly";
  const tips = E.suggestions(data, today);
  return `<div class="stack">
    <div>
      <div class="segmented" style="margin-bottom:10px">
        <button class="${weekly ? "on" : ""}" data-action="spendPeriod" data-value="weekly">Week</button>
        <button class="${!weekly ? "on" : ""}" data-action="spendPeriod" data-value="monthly">Month</button>
      </div>
      <div class="spread" style="align-items:center">
        <button class="icon-btn" data-action="spendShift" data-value="-1" aria-label="Previous">‹</button>
        <div class="bold">${rangeLabel(range, ui.spendPeriod)}</div>
        <button class="icon-btn" data-action="spendShift" data-value="1" aria-label="Next" ${ui.spendOffset >= 0 ? "disabled style='opacity:.3'" : ""}>›</button>
      </div>
    </div>
    <div class="card"><div class="stats">${stat("Money in", money0(t.income), "good")}${stat("Spent", money0(t.expenses))}${stat("Left over", money0(t.net), t.net < 0 ? "bad" : "")}</div></div>
    <section class="card"><div class="card-title">🥧 Where your money went</div>
      ${items.length ? `
        ${donut(items.map((c) => ({ amount: c.amount, color: cat(c.category).color, label: `${cat(c.category).name}: ${money(c.amount)}` })), {
          size: 210, center: `<div><div class="small muted">Total spent</div><div class="num" style="font-size:24px;font-weight:700">${money0(total)}</div></div>` })}
        <div class="stack" style="gap:12px;margin-top:16px">${items.map((c) => `
          <button class="row tappable" style="background:none;border:0;padding:0;text-align:left;width:100%" data-action="categoryDetail" data-id="${c.category}">
            ${catIcon(c.category, "sm")}
            <div class="grow"><div class="spread small"><span>${esc(cat(c.category).name)}</span>
              <span><span class="num">${money(c.amount)}</span> <span class="muted tiny num" style="display:inline-block;width:32px;text-align:right">${Math.round(c.share * 100)}%</span></span></div>
              <div style="margin-top:4px"><div class="progress thin"><div class="fill" style="width:${c.share * 100}%;background:${cat(c.category).color}"></div></div></div></div>
            <span class="muted">›</span>
          </button>`).join("")}</div>`
        : `<div class="muted center" style="padding:30px 0">No spending in this ${weekly ? "week" : "month"}.</div>`}
    </section>
    ${items.length ? `<section class="card"><div class="card-title">📊 Spending by day</div>
      ${bars(daily.map((d) => (weekly ? D.fmtWeekday(d.date).slice(0, 3) : String(D.parts(d.date).d))), [{ color: "var(--accent)", values: daily.map((d) => d.amount) }],
        { average: Math.round(total / daily.length), labelEvery: weekly ? 1 : 7 })}</section>` : ""}
    <section class="card"><div class="card-title">💡 Ways to save</div>
      ${tips.length ? tips.map((tip) => `
        <div class="tip ${tip.tone}"><div class="icon">${tip.icon}</div>
          <div class="grow"><div class="spread"><span class="bold small">${esc(tip.title)}</span>${tip.saving ? `<span class="tiny good bold">${money0(tip.saving)}/mo</span>` : ""}</div>
            <div class="small muted">${esc(tip.detail)}</div></div></div>`).join("")
        : `<div class="small muted">Once you've recorded a couple of weeks of spending, you'll see practical ideas here.</div>`}
    </section>
  </div>`;
}

// ---- Reports -------------------------------------------------------------------

function reports({ data, today }) {
  const period = ui.reportPeriod;
  const noun = period === "weekly" ? "week" : "month";
  const summaries = E.periodSummaries(data, period, period === "monthly" ? 6 : 8, today);
  const complete = summaries.filter((s) => !s.isCurrent && (s.totals.income || s.totals.expenses));
  const avgIn = complete.length ? Math.round(complete.reduce((s, x) => s + x.totals.income, 0) / complete.length) : 0;
  const avgOut = complete.length ? Math.round(complete.reduce((s, x) => s + x.totals.expenses, 0) / complete.length) : 0;
  const current = D.periodOf(period, today);
  const changes = E.categoryComparison(data, current, D.shiftPeriod(current, period, -1)).slice(0, 8);
  return `<div class="stack">
    <div class="segmented" style="margin:0">
      <button class="${period === "weekly" ? "on" : ""}" data-action="reportPeriod" data-value="weekly">Weeks</button>
      <button class="${period === "monthly" ? "on" : ""}" data-action="reportPeriod" data-value="monthly">Months</button>
    </div>
    <section class="card"><div class="card-title">📊 Money in vs spent</div>
      <div class="row small" style="gap:14px;margin-bottom:8px"><span class="row" style="gap:5px"><span class="legend-dot" style="background:var(--green)"></span>Money in</span>
        <span class="row" style="gap:5px"><span class="legend-dot" style="background:var(--blue)"></span>Spent</span></div>
      ${bars(summaries.map((s) => s.label), [
        { color: "var(--green)", values: summaries.map((s) => s.totals.income) },
        { color: "var(--blue)", values: summaries.map((s) => s.totals.expenses) },
      ], { height: 200 })}
      ${complete.length ? `<div class="small muted" style="margin-top:8px">Over the last ${complete.length} full ${noun}s you averaged ${money0(avgIn)} in and ${money0(avgOut)} spent per ${noun}.</div>` : ""}
    </section>
    <section class="card"><div class="card-title">🧾 ${period === "weekly" ? "Weekly" : "Monthly"} summary</div>
      <table class="table"><thead><tr><th>${period === "weekly" ? "Week of" : "Month"}</th><th>In</th><th>Spent</th><th>Left over</th></tr></thead>
        <tbody>${[...summaries].reverse().map((s) => `<tr><td>${esc(s.label)}${s.isCurrent ? ` <span class="tiny muted">(now)</span>` : ""}</td>
          <td class="good">${money0(s.totals.income)}</td><td>${money0(s.totals.expenses)}</td><td class="${s.totals.net < 0 ? "bad" : ""}">${money0(s.totals.net)}</td></tr>`).join("")}</tbody></table>
      <div class="tiny muted" style="margin-top:8px">Left over is money in minus money spent. Money moved into savings goals isn't counted as spending.</div>
    </section>
    <section class="card"><div class="card-title">↔️ This ${noun} vs last ${noun}</div>
      ${changes.length ? `<div class="stack" style="gap:10px">${changes.map((c) => `
        <div class="row">${catIcon(c.category, "sm")}
          <div class="grow"><div class="small">${esc(cat(c.category).name)}</div><div class="tiny muted num">${money0(c.current)} vs ${money0(c.previous)}</div></div>
          <div class="small bold num ${c.change > 0 ? "warn" : c.change < 0 ? "good" : "muted"}">${c.change === 0 ? "Same" : `${c.change > 0 ? "↑" : "↓"} ${money0(Math.abs(c.change))}`}</div></div>`).join("")}</div>
        <div class="tiny muted" style="margin-top:10px">This ${noun} isn't finished yet, so it may look lower than last ${noun}.</div>`
        : `<div class="small muted">No spending to compare yet.</div>`}
    </section>
    <button class="btn secondary" data-action="exportCSV" ${data.transactions.length ? "" : "disabled"}>Export all transactions (CSV)</button>
  </div>`;
}

// ---- What if -------------------------------------------------------------------

export function whatIfDefaults(data, today) {
  const avg = E.monthlyAverages(data, today);
  return { income: centsToInput(Math.round(avg.income / 100) * 100), expenses: centsToInput(Math.round(avg.expenses / 100) * 100),
    incomeChange: "", incomeUp: true, expenseChange: "", expenseUp: false, oneOff: "", months: 12 };
}

export function whatIfPresets(data, today) {
  const eatingOut = E.monthlySpendingByCategory(data, today).find((c) => c.category === "eatingOut")?.amount || 0;
  return [
    ["Extra shift a week (+$150)", { incomeChange: centsToInput(Math.round((15000 * 52) / 12 / 100) * 100), incomeUp: true }],
    ["Rent up $30 a week", { expenseChange: centsToInput(Math.round((3000 * 52) / 12 / 100) * 100), expenseUp: true }],
    ["Halve eating out", { expenseChange: centsToInput(Math.max(100, Math.round(eatingOut / 2 / 100) * 100)), expenseUp: false }],
    ["Cancel a subscription", { expenseChange: "15", expenseUp: false }],
    ["Fewer hours (−$300/mo)", { incomeChange: "300", incomeUp: false }],
  ];
}

export function whatIfResults({ data }) {
  const w = ui.whatIf;
  const c = (s) => parseMoney(s) || 0;
  const start = E.totalInGoals(data);
  const r = E.whatIf({
    income: c(w.income), expenses: c(w.expenses),
    incomeChange: (w.incomeUp ? 1 : -1) * c(w.incomeChange),
    expenseChange: (w.expenseUp ? 1 : -1) * c(w.expenseChange),
    oneOff: c(w.oneOff), start, months: w.months,
  });
  const diff = r.scenarioTotal - r.currentTotal;
  const label = w.months === 12 ? "1 year" : w.months === 24 ? "2 years" : `${w.months} months`;
  return `<div class="stats two">${stat("Saved per month now", money0(r.currentMonthly), r.currentMonthly < 0 ? "bad" : "")}
      ${stat("With changes", money0(r.newMonthly), r.newMonthly < 0 ? "bad" : "")}</div>
    <div style="margin-top:14px" class="small muted">After ${label}, your savings would be</div>
    <div class="num ${r.scenarioTotal < 0 ? "bad" : ""}" style="font-size:34px;font-weight:700">${money0(r.scenarioTotal)}</div>
    ${diff ? `<div class="small bold ${diff > 0 ? "good" : "warn"}">${diff > 0 ? "+" : "−"}${money0(Math.abs(diff))} compared with no changes (${money0(r.currentTotal)})</div>` : ""}
    <div class="row small" style="gap:14px;margin:14px 0 6px"><span class="row" style="gap:5px"><span class="legend-dot" style="background:var(--text-3)"></span>No changes</span>
      <span class="row" style="gap:5px"><span class="legend-dot" style="background:var(--accent)"></span>With changes</span></div>
    ${lines([
      { color: "var(--text-3)", dashed: true, values: r.points.map((p) => p.current) },
      { color: "var(--accent)", values: r.points.map((p) => p.scenario) },
    ], { xLabel: (i) => (i === 0 ? "Now" : `${i}m`) })}
    <div class="tiny muted" style="margin-top:8px">${start > 0 ? `Starts from the ${money0(start)} already in your savings goals. ` : ""}Estimates only – real months vary.</div>`;
}

function whatIf(ctx) {
  const { data, today } = ctx;
  if (!ui.whatIf) ui.whatIf = whatIfDefaults(data, today);
  const w = ui.whatIf;
  const avg = E.monthlyAverages(data, today);
  const field = (label, key) => `<div class="field"><label for="wi-${key}">${label}</label>
    <span class="row" style="gap:2px;flex:1;justify-content:flex-end"><span class="muted">$</span><input id="wi-${key}" style="max-width:120px" inputmode="decimal" placeholder="0" value="${esc(w[key])}" data-input="whatIf" data-key="${key}"></span></div>`;
  const change = (label, key, upKey) => `<div class="field"><label for="wi-${key}">${label}</label>
    <select data-change="whatIfDir" data-key="${upKey}" style="flex:none;width:auto;color:var(--accent)" aria-label="${label} direction">
      <option value="up" ${w[upKey] ? "selected" : ""}>up by</option><option value="down" ${!w[upKey] ? "selected" : ""}>down by</option></select>
    <span class="row" style="gap:2px;flex:1;justify-content:flex-end"><span class="muted">$</span><input id="wi-${key}" style="max-width:110px" inputmode="decimal" placeholder="0" value="${esc(w[key])}" data-input="whatIf" data-key="${key}"></span></div>`;
  return `<div>
    <div class="form-label" style="margin-top:0">A usual month</div>
    <div class="field-group">${field("Money in", "income")}${field("Spending", "expenses")}</div>
    <div class="form-hint">${avg.enough ? `Filled in from your last ${avg.days} days. You can change these.` : "Enter your usual monthly income and spending."}</div>
    <div class="form-label">Try a change</div>
    <div class="chips" style="margin-bottom:10px">${whatIfPresets(data, today).map(([label], i) => `<button class="chip" data-action="whatIfPreset" data-value="${i}">${esc(label)}</button>`).join("")}</div>
    <div class="field-group">
      ${change("Income each month", "incomeChange", "incomeUp")}
      ${change("Spending each month", "expenseChange", "expenseUp")}
      ${field("One-off cost", "oneOff")}
      <div class="field"><label for="wi-months">Over</label><select id="wi-months" data-change="whatIfMonths">
        ${[[3, "3 months"], [6, "6 months"], [12, "1 year"], [24, "2 years"]].map(([m, l]) => `<option value="${m}" ${w.months === m ? "selected" : ""}>${l}</option>`).join("")}</select></div>
    </div>
    <div class="form-label">Result</div>
    <section class="card" id="whatif-results">${whatIfResults(ctx)}</section>
    <div style="margin-top:14px"><button class="btn secondary" data-action="whatIfReset">Reset to my usual month</button></div>
  </div>`;
}
