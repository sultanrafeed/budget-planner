import * as D from "../dates.js";
import * as E from "../engine.js";
import { cat } from "../categories.js";
import { money, money0 } from "../money.js";
import { hasSampleData } from "../data.js";
import { esc, catIcon, progress, stat, sampleBadge } from "../ui.js";
import { donut } from "../charts.js";
import { ui } from "../state.js";

export function sampleBanner() {
  return `<div class="banner">
    <div style="font-size:22px">🧪</div>
    <div class="grow">
      <div class="title">You're viewing sample data</div>
      <div class="muted">Sample items are marked SAMPLE. Remove them when you're ready to use your own numbers – anything you've added stays.</div>
      <button class="link-btn" style="margin-top:6px" data-action="removeSample">Remove sample data</button>
    </div></div>`;
}

function installHint() {
  const standalone = window.matchMedia("(display-mode: standalone)").matches || navigator.standalone;
  if (standalone || ui.hideInstallHint) return "";
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent);
  return `<div class="banner info">
    <div style="font-size:22px">📲</div>
    <div class="grow">
      <div class="title">Add to your Home Screen</div>
      <div class="muted">${ios
        ? "In Safari, tap the Share button <b>⎋</b> then <b>Add to Home Screen</b>. It opens like an app, works offline and keeps your data safer."
        : "Use your browser's menu and choose <b>Install app</b> or <b>Add to Home Screen</b>."}</div>
      <button class="link-btn" style="margin-top:6px" data-action="hideInstallHint">Got it</button>
    </div></div>`;
}

function greeting() {
  const h = new Date().getHours();
  return h >= 5 && h < 12 ? "Good morning" : h < 17 && h >= 12 ? "Good afternoon" : "Good evening";
}

export function render({ data, today }) {
  const available = E.availableBalance(data, today);
  const inGoals = E.totalInGoals(data);
  const plan = E.paydayPlan(data, today);
  return `<div class="screen">
    <div class="large-title">${greeting()}<button class="icon-btn" data-action="addExpense" aria-label="Add expense">⊕</button></div>
    <div class="stack">
      ${hasSampleData(data) ? sampleBanner() : ""}
      ${installHint()}

      <section class="hero ${available < 0 ? "negative" : ""}" aria-label="Available money">
        <div class="label">Available now</div>
        <div class="big">${money(available)}</div>
        ${inGoals > 0 ? `<div class="sub">Plus ${money(inGoals)} set aside in savings</div>` : ""}
        <hr>
        ${plan ? `<button data-action="goPlan" data-page="payday">
            <div class="spread">
              <div><div class="sub">Safe to spend until payday</div><div class="value">${money(plan.safeToSpend)}</div></div>
              <div style="text-align:right"><div class="sub">${plan.daysUntil === 1 ? "Payday tomorrow" : `Payday in ${plan.daysUntil} days`}</div>
                <div style="font-weight:600">${plan.safeToSpend > 0 ? `${money(plan.safePerDay)} a day` : "Bills need more than you have"}</div></div>
            </div></button>`
          : `<button data-action="goPlan" data-page="payday" style="font-weight:500">📅 Set your payday to see what's safe to spend ›</button>`}
      </section>

      <div class="quick">
        <button data-action="addExpense"><span class="dot" style="background:rgba(255,59,48,.14);color:var(--red)">−</span>Expense</button>
        <button data-action="addIncome"><span class="dot" style="background:rgba(52,199,89,.16);color:var(--green-text)">＋</span>Income</button>
        <button data-action="goPlan" data-page="bills"><span class="dot" style="background:rgba(0,122,255,.13)">📅</span>Bills</button>
      </div>

      ${budgetCard(data, today)}
      ${billsCard(data, today)}
      ${spendingCard(data, today)}
      ${savingsCard(data, today)}
    </div></div>`;
}

function budgetCard(data, today) {
  const statuses = E.budgetStatuses(data, today);
  const main = E.primaryBudget(data, today);
  const others = statuses.filter((s) => s.budget.id !== main?.budget.id).slice(0, 3);
  let body = "";
  if (main) {
    const left = main.remaining >= 0;
    body += `<div class="spread" style="align-items:center">
        <div><span class="num" style="font-size:24px;font-weight:700;${left ? "" : "color:var(--red)"}">${money(Math.abs(main.remaining))}</span>
          <span class="muted">${left ? `left this ${main.budget.period === "weekly" ? "week" : "month"}` : "over budget"}</span></div>
        <span class="pill ${main.state}">${E.STATE_LABEL[main.state]}</span></div>
      <div style="margin:10px 0 6px">${progress(main.fractionSpent, main.state, main.fractionElapsed)}</div>
      <div class="small muted">${money0(main.spent)} of ${money0(main.budget.amount)} spent · ${main.daysLeft} days left${main.perDayLeft > 0 ? ` · ${money0(main.perDayLeft)}/day` : ""}</div>`;
  }
  if (others.length) {
    body += `<div class="stack" style="gap:10px;margin-top:${main ? 14 : 0}px">${others.map((s) => `
      <div class="row">${catIcon(s.budget.category, "sm")}
        <div class="grow"><div class="spread small"><span>${esc(E.budgetName(s.budget))}</span>
          <span class="num ${s.remaining < 0 ? "bad" : "muted"}">${s.remaining >= 0 ? `${money0(s.remaining)} left` : `${money0(-s.remaining)} over`}</span></div>
          <div style="margin-top:4px">${progress(s.fractionSpent, s.state, null, true)}</div></div></div>`).join("")}</div>`;
  }
  if (!statuses.length) body = `<div class="muted small">Set a weekly or monthly limit to see how much you have left to spend.</div>`;
  return `<section class="card"><div class="card-title">📊 Budget</div>${body}
    <div style="margin-top:12px"><button class="link-btn" data-action="goPlan" data-page="budgets">${statuses.length ? "See all budgets" : "Create a budget"}</button></div></section>`;
}

function billsCard(data, today) {
  const up = E.upcomingBills(data, today, 14);
  const total = up.reduce((s, x) => s + x.bill.amount, 0);
  let body;
  if (!up.length) {
    body = `<div class="muted small">${E.activeBills(data).length ? "Nothing due in the next two weeks." : "Add rent, phone and subscriptions to see what's due and when."}</div>`;
  } else {
    body = `<div class="stack" style="gap:12px">${up.slice(0, 4).map((x) => `
      <div class="row">${catIcon(x.bill.category, "sm")}
        <div class="grow"><div class="small" style="font-weight:500">${esc(x.bill.name)}${sampleBadge(x.bill.sample)}</div>
          <div class="tiny ${x.overdue ? "bad" : "muted"}">${D.fmtDue(x.date, today)}</div></div>
        <div class="num small">${money(x.bill.amount)}</div>
        ${x.date === x.bill.nextDue ? `<button class="icon-btn" style="font-size:22px" data-action="payBill" data-id="${esc(x.bill.id)}" aria-label="Mark ${esc(x.bill.name)} as paid">✓</button>` : `<span style="width:30px"></span>`}
      </div>`).join("")}</div>
      <div class="tiny muted" style="margin-top:10px">${up.length > 4 ? `+ ${up.length - 4} more · ` : ""}${money(total)} in total</div>`;
  }
  return `<section class="card"><div class="card-title">📅 Coming up · next 14 days</div>${body}
    <div style="margin-top:12px"><button class="link-btn" data-action="goPlan" data-page="bills">${E.activeBills(data).length ? "See all bills" : "Add a bill"}</button></div></section>`;
}

function spendingCard(data, today) {
  const month = D.periodOf("monthly", today);
  const t = E.totals(data, month);
  const items = E.spendingByCategory(data, month);
  const chart = items.length
    ? `<div class="row" style="margin-top:14px">
        ${donut(items.map((c) => ({ amount: c.amount, color: cat(c.category).color, label: cat(c.category).name })), { size: 96 })}
        <div class="grow stack" style="gap:6px">${items.slice(0, 4).map((c) => `
          <div class="row small" style="gap:6px"><span class="legend-dot" style="background:${cat(c.category).color}"></span>
            <span class="grow ellipsis">${esc(cat(c.category).name)}</span><span class="num">${money0(c.amount)}</span>
            <span class="num muted tiny" style="width:30px;text-align:right">${Math.round(c.share * 100)}%</span></div>`).join("")}</div></div>`
    : `<div class="muted small" style="margin-top:10px">No spending recorded this month yet.</div>`;
  return `<section class="card"><div class="card-title">🥧 This month · ${D.fmtMonthYear(today)}</div>
    <div class="stats">${stat("Money in", money0(t.income), "good")}${stat("Spent", money0(t.expenses))}${stat("Left over", money0(t.net), t.net < 0 ? "bad" : "")}</div>
    ${chart}
    <div style="margin-top:12px"><button class="link-btn" data-action="goInsights">See spending insights</button></div></section>`;
}

function savingsCard(data, today) {
  const cap = E.savingsCapacity(data, today);
  let body;
  if (!cap.averages.enough) body = `<div class="muted small">Add a couple of weeks of income and spending to see how much you can save.</div>`;
  else if (cap.monthly > 0) {
    body = `<div class="small muted">You could realistically save</div>
      <div style="font-size:20px;font-weight:700">${money0(cap.monthly)} a month</div>
      <div class="tiny muted">About ${money0(cap.weekly)} a week, based on your last ${cap.averages.days} days. It leaves a 20% buffer for surprises.</div>`;
  } else {
    body = `<div class="small">Right now you're spending about ${money0(-cap.averages.surplus)} a month more than you earn. Check Insights for ideas to close the gap.</div>`;
  }
  const goals = [...data.goals].sort((a, b) => E.goalSaved(b) / (b.target || 1) - E.goalSaved(a) / (a.target || 1)).slice(0, 3);
  if (goals.length) {
    body += `<div class="stack" style="gap:10px;margin-top:14px">${goals.map((g) => {
      const saved = E.goalSaved(g);
      return `<button class="tappable" style="background:none;border:0;padding:0;text-align:left" data-action="openGoal" data-id="${esc(g.id)}">
        <div class="spread small"><span>${g.icon} ${esc(g.name)}</span><span class="num muted">${money0(saved)} of ${money0(g.target)}</span></div>
        <div style="margin-top:4px">${progress(g.target ? saved / g.target : 0, saved >= g.target ? "onTrack" : "", null, true)}</div></button>`;
    }).join("")}</div>`;
  }
  return `<section class="card"><div class="card-title">💰 Savings</div>${body}
    <div style="margin-top:12px"><button class="link-btn" data-action="goPlan" data-page="goals">${data.goals.length ? "See savings goals" : "Create a savings goal"}</button></div></section>`;
}
