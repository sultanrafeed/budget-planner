import * as D from "../dates.js";
import * as E from "../engine.js";
import { money, money0 } from "../money.js";
import { esc, catIcon, progress, stat, sampleBadge } from "../ui.js";
import { ring } from "../charts.js";
import { ui } from "../state.js";

const PAGES = { budgets: "Budgets", bills: "Bills", goals: "Goals", payday: "Payday" };

export function render(ctx) {
  const page = PAGES[ui.planPage] ? ui.planPage : "budgets";
  const add = { budgets: "addBudget", bills: "addBill", goals: "addGoal", payday: "editPay" }[page];
  return `<div class="screen">
    <div class="large-title">${PAGES[page]}<button class="icon-btn" data-action="${add}" aria-label="${page === "payday" ? "Edit payday" : "Add"}">${page === "payday" ? "✎" : "⊕"}</button></div>
    <div class="segmented" role="tablist">${Object.entries(PAGES).map(([k, label]) =>
      `<button role="tab" aria-selected="${k === page}" class="${k === page ? "on" : ""}" data-action="planPage" data-page="${k}">${label}</button>`).join("")}</div>
    ${{ budgets, bills, goals, payday }[page](ctx)}
  </div>`;
}

function empty(icon, title, text, action, label) {
  return `<div class="card empty"><div class="icon">${icon}</div><div class="title">${title}</div><div>${text}</div>
    <button class="btn small" data-action="${action}">${label}</button></div>`;
}

// ---- Budgets -------------------------------------------------------------------

function budgets({ data, today }) {
  const statuses = E.budgetStatuses(data, today);
  if (!statuses.length) {
    const avg = E.monthlyAverages(data, today);
    return empty("📊", "Budgets help you stay on track",
      `Set a limit for all your spending, or for categories like groceries or eating out. You'll see how much is left and what you can spend each day.${avg.enough && avg.expenses ? `<br><br>Tip: you usually spend about <b>${money0(avg.expenses)}</b> a month.` : ""}`,
      "addBudget", "Create a budget");
  }
  const section = (period, title) => {
    const rows = statuses.filter((s) => s.budget.period === period);
    if (!rows.length) return "";
    return `<div class="section-label"><span>${title}</span></div><div class="list">${rows.map((s) => `
      <button class="list-row" data-action="editBudget" data-id="${esc(s.budget.id)}" style="display:block">
        <div class="row">
          ${s.budget.category ? catIcon(s.budget.category, "sm") : `<span class="cat-icon sm" style="background:var(--accent-soft);color:var(--accent);font-weight:700">Σ</span>`}
          <div class="grow"><div style="font-weight:500">${esc(E.budgetName(s.budget))}${sampleBadge(s.budget.sample)}</div>
            <div class="tiny bold" style="color:${{ onTrack: "var(--green-text)", fast: "var(--orange-text)", over: "var(--red)" }[s.state]}">${E.STATE_LABEL[s.state]}</div></div>
          <div style="text-align:right"><div class="num bold ${s.remaining < 0 ? "bad" : ""}">${money(Math.abs(s.remaining))}</div><div class="tiny muted">${s.remaining >= 0 ? "left" : "over"}</div></div>
        </div>
        <div style="margin:10px 0 6px">${progress(s.fractionSpent, s.state, s.fractionElapsed)}</div>
        <div class="tiny muted">${money(s.spent)} of ${money(s.budget.amount)} · ${s.daysLeft} ${s.daysLeft === 1 ? "day" : "days"} left${s.perDayLeft > 0 ? ` · ${money(s.perDayLeft)} a day` : ""}</div>
      </button>`).join("")}</div>`;
  };
  return section("monthly", `This month · ${D.fmtMonthYear(today)}`) +
    section("weekly", `This week · from ${D.fmtWeekday(D.startOfWeek(today))}`) +
    `<div class="section-foot">The line on each bar shows how far through the period you are. Staying left of it means you're on track.</div>`;
}

// ---- Bills ---------------------------------------------------------------------

function bills({ data, today }) {
  const active = E.activeBills(data).sort((a, b) => (a.nextDue < b.nextDue ? -1 : 1));
  if (!active.length) {
    return empty("📅", "Never miss a payment",
      "Add rent, phone, internet, insurance and subscriptions. You'll see what's due before each payday, and paying one takes a tap.",
      "addBill", "Add a bill");
  }
  const week = D.addDays(today, 7);
  const groups = [
    ["Overdue", active.filter((b) => b.nextDue < today)],
    ["Next 7 days", active.filter((b) => b.nextDue >= today && b.nextDue < week)],
    ["Later", active.filter((b) => b.nextDue >= week)],
  ];
  const next30 = E.upcomingBills(data, today, 30).reduce((s, x) => s + x.bill.amount, 0);
  const finished = data.bills.filter((b) => !b.active);
  return `<div class="card"><div class="stats two">${stat("Bills per month", money0(E.monthlyBillsCost(data)))}${stat("Due next 30 days", money0(next30))}</div></div>
    ${groups.filter(([, list]) => list.length).map(([title, list]) => `
      <div class="section-label"><span>${title}</span></div>
      <div class="list">${list.map((b) => `
        <div class="list-row">
          <button class="row grow tappable" style="background:none;border:0;padding:0;text-align:left" data-action="editBill" data-id="${esc(b.id)}">
            ${catIcon(b.category)}
            <div class="grow"><div class="ellipsis">${esc(b.name)}${sampleBadge(b.sample)}</div>
              <div class="small ${b.nextDue < today ? "bad" : "muted"}">${D.fmtDue(b.nextDue, today)}</div></div>
            <div style="text-align:right"><div class="num">${money(b.amount)}</div><div class="tiny muted">${b.remindDays !== null ? "🔔 " : ""}${D.FREQUENCIES[b.frequency].label}</div></div>
          </button>
          <button class="btn small secondary" data-action="payBill" data-id="${esc(b.id)}" aria-label="Mark ${esc(b.name)} as paid">Paid</button>
        </div>`).join("")}</div>`).join("")}
    <div class="section-foot">Tap <b>Paid</b> to record the payment and move the bill to its next due date.</div>
    <div class="section-label"><span>Reminders</span></div>
    <div class="list"><button class="list-row chevron" data-action="exportCalendar"><span class="cat-icon sm" style="background:rgba(255,59,48,.12)">🔔</span><div class="grow">Add reminders to Calendar<div class="tiny muted">Adds your bills, with alerts, to your phone's Calendar app</div></div></button></div>
    ${finished.length ? `<div class="section-label"><span>Finished one-off bills</span></div><div class="list plain">${finished.map((b) => `
      <button class="list-row" data-action="editBill" data-id="${esc(b.id)}"><div class="grow">${esc(b.name)}</div><div class="muted num">${money(b.amount)}</div></button>`).join("")}</div>` : ""}`;
}

// ---- Goals ---------------------------------------------------------------------

function goals({ data, today }) {
  const cap = E.savingsCapacity(data, today);
  const list = [...data.goals].sort((a, b) => {
    const da = E.goalSaved(a) >= a.target;
    const db = E.goalSaved(b) >= b.target;
    return da !== db ? (da ? 1 : -1) : a.created < b.created ? -1 : 1;
  });
  const summary = `<div class="card"><div class="stats two">${stat("Total saved", money0(E.totalInGoals(data)))}${stat("Still to save", money0(list.reduce((s, g) => s + Math.max(0, g.target - E.goalSaved(g)), 0)))}</div>
    ${cap.averages.enough ? `<div class="small muted" style="margin-top:10px">${cap.monthly > 0
      ? `Based on your recent income and spending, you could realistically put aside about <b>${money0(cap.monthly)}</b> a month (${money0(cap.weekly)} a week).`
      : "You're currently spending more than you earn, so start small – even $10 a week adds up to $520 a year."}</div>` : ""}</div>`;
  if (!list.length) {
    return summary + `<div style="height:14px"></div>` + empty("🎯", "Save for what matters",
      "An emergency fund, a holiday, a car or a new laptop. Set a target and a date and we'll work out how much to put aside each week.",
      "addGoal", "Create a goal");
  }
  return summary + `<div class="section-label"><span>Goals</span></div><div class="list">${list.map((g) => {
    const saved = E.goalSaved(g);
    const done = g.target > 0 && saved >= g.target;
    const req = !done && g.targetDate ? E.goalRequired(g.target - saved, today, g.targetDate) : null;
    const line = done ? `<span class="good bold">Goal reached 🎉</span>`
      : req ? `${money0(req.perWeek)} a week to reach it by ${D.fmtDMY(g.targetDate)}`
      : g.targetDate ? `<span class="warn">Target date has passed</span>` : "";
    return `<button class="list-row chevron" data-action="openGoal" data-id="${esc(g.id)}">
      ${ring(g.target ? saved / g.target : 0, { color: done ? "var(--green)" : "var(--accent)", inner: `<span style="font-size:18px">${done ? "✅" : g.icon}</span>` })}
      <div class="grow"><div style="font-weight:500">${esc(g.name)}${sampleBadge(g.sample)}</div>
        <div class="small muted num">${money(saved)} of ${money(g.target)}</div>
        ${line ? `<div class="tiny muted">${line}</div>` : ""}</div>
      <div class="small muted num bold">${Math.round((g.target ? Math.min(1, saved / g.target) : 0) * 100)}%</div>
    </button>`;
  }).join("")}</div>`;
}

// ---- Payday --------------------------------------------------------------------

function payday({ data, today }) {
  const p = E.paydayPlan(data, today);
  if (!p) {
    return empty("💵", "Plan around your payday",
      "Tell us how much you're paid and when. We'll show what's safe to spend until your next pay, after the bills due before then.",
      "editPay", "Set up payday");
  }
  const billRow = (x) => `<div class="list-row">${catIcon(x.bill.category, "sm")}
    <div class="grow"><div>${esc(x.bill.name)}</div><div class="tiny ${x.overdue ? "bad" : "muted"}">${D.fmtDue(x.date, today)}</div></div>
    <div class="num">-${money(x.bill.amount)}</div></div>`;
  const line = (label, value, cls = "") => `<div class="list-row"><div class="grow">${label}</div><div class="num ${cls}">${value}</div></div>`;
  const cycleDays = D.diffDays(p.nextPayday, p.paydayAfterNext);
  return `<div class="card">
      <div style="font-size:24px;font-weight:700">${p.daysUntil === 1 ? "Payday is tomorrow" : `Payday in ${p.daysUntil} days`}</div>
      <div class="muted small">${D.fmtWeekday(p.nextPayday)} · ${D.FREQUENCIES[p.pay.frequency].label} pay of ${money(p.pay.amount)}</div>
      <div style="margin-top:12px"><button class="btn small secondary" data-action="recordPay">💵 I got paid – add ${money(p.pay.amount)}</button></div>
    </div>
    <div class="section-label"><span>Until payday</span></div>
    <div class="list">
      ${line("Available now", money(E.availableBalance(data, today)))}
      ${p.billsBefore.length ? p.billsBefore.map(billRow).join("") : `<div class="list-row muted">No bills due before payday</div>`}
      <div class="list-row"><div class="grow bold">Safe to spend</div><div style="text-align:right"><div class="num bold ${p.safeToSpend < 0 ? "bad" : ""}">${money(p.safeToSpend)}</div>
        ${p.safeToSpend > 0 ? `<div class="tiny muted">about ${money(p.safePerDay)} a day</div>` : ""}</div></div>
    </div>
    <div class="section-foot ${p.safeToSpend < 0 ? "bad" : ""}">${p.safeToSpend < 0
      ? "Your bills before payday add up to more than you have. Consider moving money back from savings, or contact the biller early about a payment plan."
      : "This is what's left after the bills due before your next pay."}</div>
    <div class="section-label"><span>Next pay · ${D.fmtDayMonth(p.nextPayday)} to ${D.fmtDayMonth(D.addDays(p.paydayAfterNext, -1))}</span></div>
    <div class="list">
      ${line("Pay", money(p.pay.amount), "good")}
      ${line(`Bills in that cycle (${p.nextCycleBills.length})`, "-" + money(p.nextCycleTotal))}
      ${line("Move to savings", "-" + money(p.savingsPerPay))}
      <div class="list-row"><div class="grow bold">Free to spend</div><div class="num bold ${p.nextCycleSpare < 0 ? "bad" : ""}">${money(p.nextCycleSpare)}</div></div>
    </div>
    <div class="section-foot ${p.nextCycleSpare < 0 ? "bad" : ""}">${p.nextCycleSpare < 0
      ? "Your next pay doesn't cover the bills and savings in that cycle. Try lowering the savings amount for this pay."
      : `That's about ${money(Math.round(p.nextCycleSpare / cycleDays))} a day for groceries, transport and everything else.`}</div>
    ${p.nextCycleBills.length ? `<div class="section-label"><span>Bills in the next pay cycle</span></div>
      <div class="list plain">${p.nextCycleBills.map((x) => `<div class="list-row small"><div class="grow">${esc(x.bill.name)}</div><div class="muted">${D.fmtWeekday(x.date)}</div><div class="num">${money(x.bill.amount)}</div></div>`).join("")}</div>` : ""}`;
}
