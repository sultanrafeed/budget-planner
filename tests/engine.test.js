import { test } from "node:test";
import assert from "node:assert/strict";
import * as D from "../docs/js/dates.js";
import * as E from "../docs/js/engine.js";
import { parseMoney, money, money0, amountProblem } from "../docs/js/money.js";
import { emptyData, sampleData, removeSampleData, hasSampleData, transactionsToCSV, transactionsFromCSV, validateData, billsToICS } from "../docs/js/data.js";

const TODAY = "2026-10-22"; // a Thursday
const tx = (kind, amount, category, date, note = "") => ({ id: Math.random() + "", kind, amount, category, date, note, sample: false });
const bill = (name, amount, frequency, due, extra = {}) => ({ id: name, name, amount, category: "rent", frequency, anchor: due, nextDue: due, remindDays: 1, active: true, sample: false, ...extra });

test("dates and formatting are Australian", () => {
  assert.equal(D.weekday(TODAY), 3);
  assert.equal(D.fmtDMY(TODAY), "22/10/2026");
  assert.equal(D.fmtWeekday(TODAY), "Thu 22 Oct");
  assert.equal(D.periodOf("weekly", TODAY).start, "2026-10-19");
  assert.equal(D.parseAUDate("3/10/2026"), "2026-10-03");
  assert.equal(D.parseAUDate("31/02/2026"), null);
  assert.equal(money(123456), "$1,234.56");
  assert.equal(money(-300), "-$3.00");
  assert.equal(money0(123456), "$1,235");
});

test("money parsing is exact", () => {
  assert.equal(parseMoney("12.5"), 1250);
  assert.equal(parseMoney("$1,200.00"), 120000);
  assert.equal(parseMoney("-54.20"), -5420);
  assert.equal(parseMoney("(54.20)"), -5420);
  assert.equal(parseMoney("0.1"), 10);
  assert.equal(parseMoney("abc"), null);
  assert.equal(amountProblem(""), "Enter an amount.");
  assert.equal(amountProblem("0"), "The amount must be more than $0.");
  assert.equal(amountProblem("12.30"), null);
});

test("monthly schedule doesn't drift from month end", () => {
  assert.equal(D.occurrence("monthly", 1, "2026-01-31"), "2026-02-28");
  assert.equal(D.occurrence("monthly", 2, "2026-01-31"), "2026-03-31");
  assert.equal(D.nextOccurrence("monthly", "2026-02-28", "2026-01-31"), "2026-03-31");
});

test("next and previous occurrence", () => {
  assert.equal(D.nextOccurrence("fortnightly", "2026-10-20", "2026-10-01"), "2026-10-29");
  assert.equal(D.previousOccurrence("fortnightly", "2026-10-20", "2026-10-01"), "2026-10-15");
  assert.equal(D.previousOccurrence("fortnightly", "2026-09-01", "2026-10-01"), null);
  assert.equal(D.nextOccurrence("weekly", "2026-10-01", "2026-10-01", true), "2026-10-01");
  assert.equal(D.nextOccurrence("weekly", "2026-09-01", "2026-10-01"), "2026-10-01");
});

test("available balance", () => {
  const data = emptyData();
  data.settings.openingBalance = 100000;
  data.transactions = [tx("income", 50000, "salary", "2026-10-02"), tx("expense", 12055, "groceries", "2026-10-03"), tx("expense", 99900, "shopping", "2026-10-30")];
  data.goals = [{ id: "g", name: "Trip", target: 100000, contributions: [{ date: "2026-10-04", amount: 20000 }, { date: "2026-10-05", amount: -5000 }] }];
  assert.equal(E.availableBalance(data, TODAY), 122945);
  assert.equal(E.totalInGoals(data), 15000);
});

test("budget status", () => {
  const data = emptyData();
  data.budgets = [{ id: "a", category: "groceries", amount: 40000, period: "monthly" }, { id: "b", category: null, amount: 10000, period: "weekly" }];
  data.transactions = [
    tx("expense", 15000, "groceries", "2026-10-02"), tx("expense", 5000, "groceries", "2026-09-28"),
    tx("expense", 8000, "eatingOut", "2026-10-20"), tx("expense", 3000, "groceries", "2026-10-19"),
    tx("expense", 4000, "groceries", "2026-10-18"),
  ];
  const m = E.budgetStatus(data, data.budgets[0], TODAY);
  assert.equal(m.spent, 22000);
  assert.equal(m.remaining, 18000);
  assert.equal(m.daysLeft, 10);
  assert.equal(m.perDayLeft, 1800);
  assert.equal(m.state, "onTrack");
  const w = E.budgetStatus(data, data.budgets[1], TODAY);
  assert.equal(w.spent, 11000);
  assert.equal(w.state, "over");
  assert.equal(E.primaryBudget(data, TODAY).budget.id, "b");
});

test("upcoming bills include overdue and repeats", () => {
  const data = emptyData();
  data.bills = [
    bill("Rent", 30000, "weekly", "2026-10-26"),
    bill("Phone", 3500, "monthly", "2026-10-12"),
    bill("Old", 1000, "once", "2026-10-01", { active: false }),
  ];
  const up = E.upcomingBills(data, TODAY, 14);
  assert.deepEqual(up.map((x) => x.bill.name), ["Phone", "Rent", "Rent"]);
  assert.ok(up[0].overdue);
  assert.equal(up[2].date, "2026-11-02");
  assert.equal(E.monthlyBillsCost(data), 130000 + 3500);
});

test("payday plan", () => {
  const data = emptyData();
  data.settings.openingBalance = 80000;
  data.settings.pay = { amount: 120000, frequency: "fortnightly", anchor: "2026-10-15", category: "salary" };
  data.settings.savingsPerPay = 10000;
  data.bills = [bill("Rent", 30000, "weekly", "2026-10-26")];
  const p = E.paydayPlan(data, TODAY);
  assert.equal(p.nextPayday, "2026-10-29");
  assert.equal(p.lastPayday, "2026-10-15");
  assert.equal(p.daysUntil, 7);
  assert.equal(p.billsBeforeTotal, 30000);
  assert.equal(p.safeToSpend, 50000);
  assert.equal(p.safePerDay, 7143);
  assert.equal(p.nextCycleTotal, 60000);
  assert.equal(p.nextCycleSpare, 50000);
});

test("monthly averages and realistic savings", () => {
  const data = emptyData();
  data.transactions = [tx("income", 300000, "salary", D.addDays(TODAY, -59)), tx("expense", 200000, "rent", D.addDays(TODAY, -30))];
  const avg = E.monthlyAverages(data, TODAY);
  assert.equal(avg.days, 60);
  assert.equal(avg.income, 152188);
  assert.equal(avg.expenses, 101458);
  assert.equal(E.savingsCapacity(data, TODAY).monthly, 40000);
});

test("goal planner", () => {
  const r = E.goalRequired(100000, TODAY, D.addDays(TODAY, 70));
  assert.equal(r.perWeek, 10000);
  assert.equal(r.perFortnight, 20000);
  assert.equal(r.perMonth, 43500);
  assert.equal(E.goalRequired(100000, TODAY, TODAY), null);
  assert.equal(E.goalFinishDate(25000, 10000, TODAY), D.addDays(TODAY, 21));
  assert.equal(E.goalFinishDate(25000, 0, TODAY), null);
});

test("what-if", () => {
  const w = E.whatIf({ income: 240000, expenses: 210000, incomeChange: 20000, expenseChange: -10000, oneOff: 30000, start: 100000, months: 6 });
  assert.equal(w.currentMonthly, 30000);
  assert.equal(w.newMonthly, 60000);
  assert.equal(w.currentTotal, 280000);
  assert.equal(w.scenarioTotal, 430000);
  assert.equal(w.points.length, 7);
});

test("reports and comparison", () => {
  const data = emptyData();
  data.transactions = [tx("expense", 10000, "groceries", "2026-09-05"), tx("expense", 16000, "groceries", "2026-10-05"), tx("expense", 4000, "eatingOut", "2026-10-06"), tx("income", 90000, "salary", "2026-10-01")];
  const months = E.periodSummaries(data, "monthly", 3, TODAY);
  assert.deepEqual(months.map((m) => m.totals.expenses), [0, 10000, 20000]);
  assert.equal(months[2].totals.net, 70000);
  const now = D.periodOf("monthly", TODAY);
  const change = E.categoryComparison(data, now, D.shiftPeriod(now, "monthly", -1));
  assert.equal(change[0].category, "groceries");
  assert.equal(change[0].change, 6000);
  assert.deepEqual(E.spendingByCategory(data, now).map((c) => c.share), [0.8, 0.2]);
});

test("CSV round trip and import without a type column", () => {
  const txs = [tx("expense", 1250, "eatingOut", "2026-10-03", 'Lunch, with "Sam"'), tx("income", 115000, "partTime", "2026-10-02", "=Pay")];
  const csv = transactionsToCSV(txs);
  assert.ok(csv.includes('"Lunch, with ""Sam"""'));
  assert.ok(csv.includes("'=Pay"));
  const back = transactionsFromCSV(csv);
  assert.equal(back.transactions.length, 2);
  const lunch = back.transactions.find((t) => t.kind === "expense");
  assert.equal(lunch.amount, 1250);
  assert.equal(lunch.category, "eatingOut");
  assert.equal(lunch.date, "2026-10-03");
  assert.equal(lunch.note, 'Lunch, with "Sam"');

  const r = transactionsFromCSV('Date,Description,Amount\n03/10/2026,Coles,-$54.20\n04/10/2026,Pay,"1,200.00"\nbad,row,1\n');
  assert.deepEqual(r.transactions.map((t) => t.kind), ["expense", "income"]);
  assert.equal(r.transactions[1].amount, 120000);
  assert.deepEqual(r.skipped, [4]);
  assert.throws(() => transactionsFromCSV("Name,Thing\nA,B"));
});

test("sample data is flagged, sensible and removable", () => {
  const sample = sampleData(TODAY);
  const data = { ...emptyData(), ...sample, settings: { ...emptyData().settings, ...sample.settings } };
  assert.ok(data.transactions.every((t) => t.sample && t.date <= TODAY));
  assert.ok(data.bills.every((b) => b.sample && b.nextDue >= TODAY));
  const balance = E.availableBalance(data, TODAY);
  assert.ok(balance > 50000 && balance < 400000, `balance ${balance}`);
  assert.ok(E.paydayPlan(data, TODAY));
  assert.ok(E.suggestions(data, TODAY).length > 0);
  data.transactions.push(tx("expense", 1000, "groceries", TODAY));
  removeSampleData(data);
  assert.equal(data.transactions.length, 1);
  assert.equal(hasSampleData(data), false);
  assert.equal(data.settings.openingBalance, 0);
  assert.equal(data.settings.pay, null);
});

test("backups validate and round trip", () => {
  const sample = sampleData(TODAY);
  const data = { ...emptyData(), ...sample, settings: { ...emptyData().settings, ...sample.settings } };
  assert.deepEqual(validateData(JSON.parse(JSON.stringify(data))), data);
  assert.throws(() => validateData({ hello: 1 }), /isn't a Budget Planner backup/);
  assert.throws(() => validateData({ version: 99, transactions: [] }), /newer version/);
});

test("calendar export", () => {
  const ics = billsToICS([bill("Rent", 32000, "weekly", "2026-10-26"), bill("Now", 100, "monthly", "2026-10-26", { remindDays: 0 })]);
  assert.ok(ics.includes("RRULE:FREQ=WEEKLY"));
  assert.ok(ics.includes("TRIGGER:-PT15H"));
  assert.ok(ics.includes("TRIGGER:PT9H"));
  assert.ok(ics.includes("DTSTART;VALUE=DATE:20261026"));
});
