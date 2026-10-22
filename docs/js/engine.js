// All money maths in one place. Pure functions of (data, today) so results are
// predictable and testable. Amounts are integer cents; dates are "YYYY-MM-DD".

import * as D from "./dates.js";
import { sum } from "./money.js";
import { cat, CATEGORIES } from "./categories.js";
import { money0, money } from "./money.js";

export const DAYS_PER_MONTH = 30.4375;

export function signed(tx) {
  return tx.kind === "income" ? tx.amount : -tx.amount;
}

export function goalSaved(goal) {
  return sum(goal.contributions || [], (c) => c.amount);
}

export function totalInGoals(data) {
  return sum(data.goals, goalSaved);
}

/** Opening balance + income − spending (up to today) − money moved into goals. */
export function availableBalance(data, today) {
  const flows = sum(data.transactions.filter((t) => t.date <= today), signed);
  const moved = sum(data.goals.flatMap((g) => g.contributions || []).filter((c) => c.date <= today), (c) => c.amount);
  return data.settings.openingBalance + flows - moved;
}

export function txIn(data, range) {
  return data.transactions.filter((t) => D.inRange(t.date, range));
}

export function totals(data, range) {
  let income = 0;
  let expenses = 0;
  for (const t of txIn(data, range)) {
    if (t.kind === "income") income += t.amount;
    else expenses += t.amount;
  }
  return { income, expenses, net: income - expenses };
}

function byCategory(list) {
  const sums = new Map();
  for (const t of list) sums.set(t.category, (sums.get(t.category) || 0) + t.amount);
  const total = sum([...sums.values()]);
  return [...sums.entries()]
    .map(([category, amount]) => ({ category, amount, share: total > 0 ? amount / total : 0 }))
    .sort((a, b) => b.amount - a.amount || cat(a.category).name.localeCompare(cat(b.category).name));
}

export function spendingByCategory(data, range) {
  return byCategory(txIn(data, range).filter((t) => t.kind === "expense"));
}

export function dailySpending(data, range) {
  const sums = new Map();
  for (const t of txIn(data, range)) if (t.kind === "expense") sums.set(t.date, (sums.get(t.date) || 0) + t.amount);
  const days = [];
  for (let d = range.start; d < range.end; d = D.addDays(d, 1)) days.push({ date: d, amount: sums.get(d) || 0 });
  return days;
}

export function movedToSavings(data, range) {
  return sum(data.goals.flatMap((g) => g.contributions || []).filter((c) => D.inRange(c.date, range)), (c) => c.amount);
}

// ---- Budgets -----------------------------------------------------------------

export function budgetName(b) {
  return b.category ? cat(b.category).name : "All spending";
}

export function budgetStatus(data, budget, today) {
  const range = D.periodOf(budget.period, today);
  const spent = sum(
    txIn(data, range).filter((t) => t.kind === "expense" && (!budget.category || t.category === budget.category)),
    (t) => t.amount,
  );
  const length = D.diffDays(range.start, range.end);
  const daysLeft = Math.max(0, D.diffDays(today, range.end));
  const fractionElapsed = Math.min(1, Math.max(0, (D.diffDays(range.start, today) + 0.5) / length));
  const fractionSpent = budget.amount > 0 ? spent / budget.amount : spent > 0 ? 1.01 : 0;
  const remaining = budget.amount - spent;
  let state = "onTrack";
  if (spent > budget.amount) state = "over";
  else if (fractionSpent > fractionElapsed + 0.1 && fractionSpent > 0.25) state = "fast";
  const perDayLeft = daysLeft > 0 && remaining > 0 ? Math.round(remaining / daysLeft) : 0;
  return { budget, range, spent, remaining, fractionSpent, fractionElapsed, daysLeft, perDayLeft, state };
}

export const STATE_LABEL = { onTrack: "On track", fast: "Spending fast", over: "Over budget" };

export function budgetStatuses(data, today) {
  return [...data.budgets]
    .sort((a, b) => {
      if (!a.category !== !b.category) return a.category ? 1 : -1;
      if (a.period !== b.period) return a.period === "monthly" ? -1 : 1;
      return budgetName(a).localeCompare(budgetName(b));
    })
    .map((b) => budgetStatus(data, b, today));
}

/** The overall budget to headline (monthly first, then weekly). */
export function primaryBudget(data, today) {
  const overall = data.budgets.filter((b) => !b.category);
  const b = overall.find((x) => x.period === "monthly") || overall[0];
  return b ? budgetStatus(data, b, today) : null;
}

// ---- Bills -------------------------------------------------------------------

export function monthlyCost(bill) {
  return Math.round((bill.amount * D.FREQUENCIES[bill.frequency].perYear) / 12);
}

export const activeBills = (data) => data.bills.filter((b) => b.active);

export function overdueBills(data, today) {
  return activeBills(data)
    .filter((b) => b.nextDue < today)
    .map((bill) => ({ bill, date: bill.nextDue, overdue: true }))
    .sort((a, b) => (a.date < b.date ? -1 : 1));
}

/** Due dates of a bill inside a range, starting from its next unpaid date. */
export function dueDates(bill, range) {
  if (!bill.active) return [];
  const dates = [];
  let current = bill.nextDue;
  while (current && current < range.end && dates.length < 400) {
    if (current >= range.start) dates.push(current);
    if (bill.frequency === "once") break;
    current = D.nextOccurrence(bill.frequency, current, bill.anchor);
  }
  return dates;
}

export function billsDue(data, range, today, includeOverdue = false) {
  const result = includeOverdue ? overdueBills(data, today) : [];
  for (const bill of activeBills(data)) {
    for (const date of dueDates(bill, range)) result.push({ bill, date, overdue: date < today });
  }
  return result.sort((a, b) => (a.date === b.date ? a.bill.name.localeCompare(b.bill.name) : a.date < b.date ? -1 : 1));
}

export function upcomingBills(data, today, days = 30) {
  return billsDue(data, { start: today, end: D.addDays(today, days) }, today, true);
}

export const monthlyBillsCost = (data) => sum(activeBills(data), monthlyCost);

// ---- Payday ------------------------------------------------------------------

export function paydayPlan(data, today) {
  const pay = data.settings.pay;
  if (!pay || pay.frequency === "once") return null;
  const next = D.nextOccurrence(pay.frequency, today, pay.anchor);
  const after = next && D.nextOccurrence(pay.frequency, next, pay.anchor);
  if (!next || !after) return null;
  const before = billsDue(data, { start: today, end: next }, today, true);
  const beforeTotal = sum(before, (x) => x.bill.amount);
  const nextCycle = billsDue(data, { start: next, end: after }, today);
  const nextCycleTotal = sum(nextCycle, (x) => x.bill.amount);
  const days = Math.max(1, D.diffDays(today, next));
  const safe = availableBalance(data, today) - beforeTotal;
  const savingsPerPay = data.settings.savingsPerPay || 0;
  return {
    pay,
    lastPayday: D.previousOccurrence(pay.frequency, today, pay.anchor),
    nextPayday: next,
    paydayAfterNext: after,
    daysUntil: days,
    billsBefore: before,
    billsBeforeTotal: beforeTotal,
    safeToSpend: safe,
    safePerDay: safe > 0 ? Math.round(safe / days) : 0,
    nextCycleBills: nextCycle,
    nextCycleTotal,
    savingsPerPay,
    nextCycleSpare: pay.amount - nextCycleTotal - savingsPerPay,
  };
}

// ---- Averages and savings ----------------------------------------------------

/** Average monthly income and spending over up to the last 90 days. */
export function monthlyAverages(data, today, maxDays = 90) {
  const dates = data.transactions.map((t) => t.date).filter((d) => d <= today);
  if (!dates.length) return { income: 0, expenses: 0, days: 0, surplus: 0, enough: false };
  const first = dates.reduce(D.minDate);
  const days = Math.min(maxDays, D.diffDays(first, today) + 1);
  const range = { start: D.addDays(today, -(days - 1)), end: D.addDays(today, 1) };
  const t = totals(data, range);
  const income = Math.round((t.income * DAYS_PER_MONTH) / days);
  const expenses = Math.round((t.expenses * DAYS_PER_MONTH) / days);
  return { income, expenses, days, surplus: income - expenses, enough: days >= 14, range };
}

export function monthlySpendingByCategory(data, today) {
  const avg = monthlyAverages(data, today);
  if (!avg.days) return [];
  return spendingByCategory(data, avg.range).map((c) => ({ ...c, amount: Math.round((c.amount * DAYS_PER_MONTH) / avg.days) }));
}

/** 80% of the usual monthly surplus, rounded down to $10 – leaves a buffer. */
export function savingsCapacity(data, today) {
  const averages = monthlyAverages(data, today);
  const monthly = averages.surplus > 0 ? Math.floor((averages.surplus * 0.8) / 1000) * 1000 : 0;
  return {
    averages,
    monthly,
    weekly: Math.round((monthly * 12) / 52 / 100) * 100,
    rate: averages.income > 0 ? averages.surplus / averages.income : 0,
  };
}

// ---- Reports -----------------------------------------------------------------

export function periodSummaries(data, period, count, today) {
  const current = D.periodOf(period, today);
  const out = [];
  for (let i = count - 1; i >= 0; i--) {
    const range = D.shiftPeriod(current, period, -i);
    out.push({
      range,
      label: period === "monthly" ? D.fmtMonth(range.start) : D.fmtDayMonth(range.start),
      totals: totals(data, range),
      saved: movedToSavings(data, range),
      isCurrent: i === 0,
    });
  }
  return out;
}

export function categoryComparison(data, current, previous) {
  const now = new Map(spendingByCategory(data, current).map((c) => [c.category, c.amount]));
  const before = new Map(spendingByCategory(data, previous).map((c) => [c.category, c.amount]));
  return [...new Set([...now.keys(), ...before.keys()])]
    .map((category) => {
      const cur = now.get(category) || 0;
      const prev = before.get(category) || 0;
      return { category, current: cur, previous: prev, change: cur - prev };
    })
    .sort((a, b) => Math.max(b.current, b.previous) - Math.max(a.current, a.previous));
}

// ---- Suggestions -------------------------------------------------------------

/** Plain-English, realistic ideas for saving money. */
export function suggestions(data, today) {
  const avg = monthlyAverages(data, today);
  if (!avg.enough) return [];
  const tips = [];
  const byCat = new Map(monthlySpendingByCategory(data, today).map((c) => [c.category, c]));
  const share = (c) => byCat.get(c)?.share || 0;
  const monthly = (c) => byCat.get(c)?.amount || 0;

  if (avg.surplus < 0) {
    const biggest = [...byCat.values()].filter((c) => c.category !== "rent").sort((a, b) => b.amount - a.amount)[0];
    tips.push({
      tone: "warning", icon: "⚠️", title: "You're spending more than you earn",
      detail: `On average you spend ${money0(-avg.surplus)} more than you earn each month.` +
        (biggest ? ` Start with ${cat(biggest.category).name.toLowerCase()}, your biggest flexible cost.` : ""),
    });
  }

  for (const s of budgetStatuses(data, today)) {
    if (s.state === "over") {
      tips.push({
        tone: "warning", icon: "📊", title: `Over your ${budgetName(s.budget).toLowerCase()} budget`,
        detail: `You're ${money(-s.remaining)} over this ${s.budget.period === "weekly" ? "week" : "month"}. Hold off on extras here until it resets.`,
      });
    }
  }

  if (share("eatingOut") > 0.08 && monthly("eatingOut") > 6000) {
    const saving = Math.round(monthly("eatingOut") / 4);
    tips.push({
      tone: "tip", icon: "🍜", title: "Eat out a little less", saving,
      detail: `Eating out costs about ${money0(monthly("eatingOut"))} a month. Cooking a couple more meals at home and cutting this by a quarter saves around ${money0(saving)} a month.`,
    });
  }

  const subs = activeBills(data).filter((b) => b.category === "subscriptions" && b.frequency !== "once");
  if (subs.length >= 2) {
    const total = sum(subs, monthlyCost);
    const cheapest = [...subs].sort((a, b) => monthlyCost(a) - monthlyCost(b))[0];
    tips.push({
      tone: "tip", icon: "🔁", title: "Review your subscriptions", saving: monthlyCost(cheapest),
      detail: `You have ${subs.length} subscriptions costing about ${money0(total)} a month. Cancelling one you rarely use, like ${cheapest.name}, saves ${money0(monthlyCost(cheapest) * 12)} a year.`,
    });
  }

  if (share("shopping") > 0.12 && monthly("shopping") > 8000) {
    const saving = Math.round(monthly("shopping") / 5);
    tips.push({
      tone: "tip", icon: "🛍️", title: "Wait 48 hours before buying", saving,
      detail: `Shopping is about ${money0(monthly("shopping"))} a month. Waiting two days before non-essential buys could cut this by a fifth – around ${money0(saving)} a month.`,
    });
  }

  if (share("groceries") > 0.18 && monthly("groceries") > 30000) {
    const saving = Math.round(monthly("groceries") / 10);
    tips.push({
      tone: "tip", icon: "🛒", title: "Plan meals before you shop", saving,
      detail: `Shopping with a list, buying home brands and checking Aldi or weekly specials can trim groceries by 10% – about ${money0(saving)} a month.`,
    });
  }

  if (share("transport") > 0.1 && monthly("transport") > 10000) {
    tips.push({
      tone: "tip", icon: "🚆", title: "Check your transport costs", saving: Math.round(monthly("transport") / 10),
      detail: `Transport is about ${money0(monthly("transport"))} a month. Off-peak travel and the weekly fare caps on Opal, Myki and go card can lower this. Concession fares may apply if you study.`,
    });
  }

  const thisMonth = D.periodOf("monthly", today);
  const lastMonth = D.shiftPeriod(thisMonth, "monthly", -1);
  const monthBefore = D.shiftPeriod(thisMonth, "monthly", -2);
  const jump = categoryComparison(data, lastMonth, monthBefore)
    .filter((c) => c.category !== "rent" && c.previous > 0 && c.change > 5000 && c.change / c.previous > 0.25)
    .sort((a, b) => b.change - a.change)[0];
  if (jump) {
    tips.push({
      tone: "warning", icon: "📈", title: `${cat(jump.category).name} went up`,
      detail: `You spent ${money0(jump.change)} more on ${cat(jump.category).name.toLowerCase()} in ${D.fmtMonthYear(lastMonth.start)} than the month before. Worth a quick look.`,
    });
  }

  const rate = avg.income > 0 ? avg.surplus / avg.income : 0;
  if (avg.income > 0 && avg.surplus >= 0 && rate < 0.1) {
    tips.push({
      tone: "tip", icon: "💵", title: "Aim to save 10% of your income",
      detail: `That's about ${money0(Math.round(avg.income / 10))} a month. Moving it to savings on payday makes it automatic.`,
    });
  } else if (rate >= 0.2) {
    tips.push({
      tone: "praise", icon: "👏", title: "You're saving well",
      detail: `You keep about ${Math.round(rate * 100)}% of your income. Put the extra towards a goal so it doesn't get spent.`,
    });
  }

  const order = { warning: 0, tip: 1, praise: 2 };
  return tips
    .sort((a, b) => order[a.tone] - order[b.tone] || (b.saving || 0) - (a.saving || 0))
    .slice(0, 6);
}

// ---- Goals -------------------------------------------------------------------

const ceilDollar = (cents) => Math.ceil(cents / 100) * 100;

/** How much to put aside to save `remaining` cents by `targetDate`. */
export function goalRequired(remaining, today, targetDate) {
  const days = D.diffDays(today, targetDate);
  if (days <= 0) return null;
  if (remaining <= 0) return { perWeek: 0, perFortnight: 0, perMonth: 0, days };
  const perDay = remaining / days;
  return {
    perWeek: ceilDollar(Math.min(remaining, perDay * 7)),
    perFortnight: ceilDollar(Math.min(remaining, perDay * 14)),
    perMonth: ceilDollar(Math.min(remaining, perDay * DAYS_PER_MONTH)),
    days,
  };
}

/** When a goal is reached saving `perWeek` cents every week. */
export function goalFinishDate(remaining, perWeek, today) {
  if (remaining <= 0) return today;
  if (perWeek <= 0) return null;
  const weeks = Math.ceil(remaining / perWeek);
  return weeks > 5200 ? null : D.addDays(today, weeks * 7);
}

// ---- What-if -----------------------------------------------------------------

export function whatIf({ income, expenses, incomeChange = 0, expenseChange = 0, oneOff = 0, start = 0, months = 12 }) {
  const currentMonthly = income - expenses;
  const newMonthly = income + incomeChange - Math.max(0, expenses + expenseChange);
  const points = [{ month: 0, current: start, scenario: start }];
  let cur = start;
  let scen = start - oneOff;
  for (let m = 1; m <= Math.max(1, months); m++) {
    cur += currentMonthly;
    scen += newMonthly;
    points.push({ month: m, current: cur, scenario: scen });
  }
  const last = points[points.length - 1];
  return { currentMonthly, newMonthly, points, currentTotal: last.current, scenarioTotal: last.scenario };
}

export { CATEGORIES };
