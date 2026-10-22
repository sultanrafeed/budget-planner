// Data model helpers: empty state, sample data, CSV, backups and calendar export.

import * as D from "./dates.js";
import { CATEGORIES, cat, matchCategory } from "./categories.js";
import { parseMoney } from "./money.js";

export const VERSION = 1;

export const uid = () =>
  (globalThis.crypto?.randomUUID?.() || Date.now().toString(36) + Math.random().toString(36).slice(2));

export function emptyData() {
  return {
    version: VERSION,
    transactions: [],
    bills: [],
    budgets: [],
    goals: [],
    settings: {
      openingBalance: 0,
      openingSample: false,
      pay: null,
      paySample: false,
      savingsPerPay: 0,
      onboarded: false,
    },
  };
}

export function hasSampleData(data) {
  return (
    data.transactions.some((x) => x.sample) || data.bills.some((x) => x.sample) ||
    data.budgets.some((x) => x.sample) || data.goals.some((x) => x.sample) ||
    data.settings.openingSample || data.settings.paySample
  );
}

/** Removes every sample record and keeps everything the user entered. */
export function removeSampleData(data) {
  data.transactions = data.transactions.filter((x) => !x.sample);
  data.bills = data.bills.filter((x) => !x.sample);
  data.budgets = data.budgets.filter((x) => !x.sample);
  data.goals = data.goals.filter((x) => !x.sample);
  if (data.settings.openingSample) {
    data.settings.openingBalance = 0;
    data.settings.openingSample = false;
  }
  if (data.settings.paySample) {
    data.settings.pay = null;
    data.settings.savingsPerPay = 0;
    data.settings.paySample = false;
  }
  return data;
}

/** Checks and cleans data loaded from storage or a backup file. Throws on bad data. */
export function validateData(raw) {
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.transactions)) {
    throw new Error("This file isn't a Budget Planner backup.");
  }
  if ((raw.version || 1) > VERSION) {
    throw new Error("This backup was made by a newer version of the app.");
  }
  const base = emptyData();
  const int = (v) => (Number.isFinite(v) ? Math.round(v) : 0);
  const date = (v, fallback) => (D.isValid(v) ? v : fallback);
  const t = D.today();
  return {
    version: VERSION,
    transactions: raw.transactions
      .filter((x) => x && (x.kind === "income" || x.kind === "expense") && D.isValid(x.date))
      .map((x) => ({
        id: String(x.id || uid()), kind: x.kind, amount: Math.abs(int(x.amount)),
        category: CATEGORIES[x.category]?.kind === x.kind ? x.category : x.kind === "income" ? "otherIncome" : "otherExpense",
        date: x.date, note: String(x.note || "").slice(0, 200), sample: !!x.sample, billId: x.billId || null,
      })),
    bills: (raw.bills || []).filter((x) => x && x.name).map((x) => ({
      id: String(x.id || uid()), name: String(x.name).slice(0, 80), amount: Math.abs(int(x.amount)),
      category: CATEGORIES[x.category] ? x.category : "otherExpense",
      frequency: D.FREQUENCIES[x.frequency] ? x.frequency : "monthly",
      anchor: date(x.anchor, t), nextDue: date(x.nextDue, date(x.anchor, t)),
      remindDays: Number.isInteger(x.remindDays) ? x.remindDays : null,
      active: x.active !== false, lastPaid: D.isValid(x.lastPaid) ? x.lastPaid : null, sample: !!x.sample,
    })),
    budgets: (raw.budgets || []).filter((x) => x && x.amount > 0).map((x) => ({
      id: String(x.id || uid()), category: CATEGORIES[x.category] ? x.category : null,
      amount: int(x.amount), period: x.period === "weekly" ? "weekly" : "monthly", sample: !!x.sample,
    })),
    goals: (raw.goals || []).filter((x) => x && x.name).map((x) => ({
      id: String(x.id || uid()), name: String(x.name).slice(0, 80), icon: x.icon || "⭐️",
      target: Math.abs(int(x.target)), targetDate: D.isValid(x.targetDate) ? x.targetDate : null,
      created: date(x.created, t), sample: !!x.sample,
      contributions: (x.contributions || []).filter((c) => c && D.isValid(c.date)).map((c) => ({
        id: String(c.id || uid()), date: c.date, amount: int(c.amount), note: String(c.note || "").slice(0, 120),
      })),
    })),
    settings: { ...base.settings, ...(raw.settings || {}) },
  };
}

// ---- Sample data -------------------------------------------------------------

/** Realistic demo data for a uni student working part-time in Sydney. */
export function sampleData(today = D.today()) {
  let seed = 2026;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  };
  const between = (lo, hi) => Math.round((lo + rand() * (hi - lo)) * 100);
  const pick = (list) => list[Math.floor(rand() * list.length)];
  const day = (n) => D.addDays(today, n);

  const tx = [];
  const add = (kind, amount, category, date, note) => {
    if (date <= today) tx.push({ id: uid(), kind, amount, category, date, note, sample: true, billId: null });
  };

  const history = 120;
  const start = day(-history);
  const wd = D.weekday(today); // 0 = Monday
  const lastThursday = day(-((wd - 3 + 7) % 7));
  const lastMonday = day(-wd);
  const nextMonthly = (dom) => {
    const { y, m } = D.parts(today);
    let d = D.ymd(y, m, Math.min(dom, D.daysInMonth(y, m)));
    if (d < today) d = D.addMonths(d, 1);
    return d;
  };

  // Pay: fortnightly on Thursdays.
  for (let p = lastThursday; p > start; p = D.addDays(p, -14)) {
    add("income", between(1290, 1420), "partTime", p, "Woolworths – shifts");
  }
  add("income", 12000, "freelance", day(-38), "Maths tutoring");
  add("income", 15000, "freelance", day(-11), "Maths tutoring");
  add("income", 41260, "taxRefund", day(-96), "ATO tax refund");
  add("income", 5000, "giftIncome", day(-64), "Birthday money from Nan");

  // Rent every Monday.
  for (let m = lastMonday; m > start; m = D.addDays(m, -7)) add("expense", 32000, "rent", m, "Rent");

  // Bills already paid.
  const monthlyBills = [
    [12, 3500, "phoneInternet", "Optus mobile"],
    [20, 2750, "phoneInternet", "NBN (my share)"],
    [3, 1899, "subscriptions", "Netflix"],
    [15, 1399, "subscriptions", "Spotify"],
  ];
  const carInsuranceNext = day(23);
  monthlyBills.push([D.parts(carInsuranceNext).d, 7415, "insurance", "Car insurance"]);
  for (let back = 0; back <= 4; back++) {
    for (const [dom, amount, category, note] of monthlyBills) {
      const d = D.addMonths(nextMonthly(dom), -1 - back);
      if (d >= start && d < today) add("expense", amount, category, d, note);
    }
  }
  let gymNext = D.addDays(lastThursday, 1);
  if (gymNext < today) gymNext = D.addDays(gymNext, 14);
  for (let g = D.addDays(gymNext, -14); g > start; g = D.addDays(g, -14)) add("expense", 2490, "subscriptions", g, "Gym membership");
  const electricityNext = day(9);
  add("expense", 17985, "utilities", D.addMonths(electricityNext, -3), "Electricity (share)");

  // Everyday spending.
  const stores = ["Woolworths", "Coles", "Aldi"];
  const cafes = ["Coffee", "Guzman y Gomez", "Sushi train", "Thai takeaway", "Boost Juice", "Uber Eats", "Pub dinner"];
  const shops = ["Kmart", "Uniqlo", "Amazon AU", "JB Hi-Fi", "Big W", "Rebel Sport"];
  const fun = ["Movie tickets", "Concert ticket", "Bowling", "Netball fees", "Mini golf"];
  for (let i = -history; i <= 0; i++) {
    const d = day(i);
    const w = D.weekday(d);
    if (w === 6) add("expense", between(55, 95), "groceries", d, pick(stores));
    if (w === 2) add("expense", between(18, 40), "groceries", d, pick(stores));
    if (w <= 3) add("expense", between(4.2, 9.6), "transport", d, "Opal fares");
    if (w === 4 && rand() < 0.33) add("expense", between(48, 72), "transport", d, "Fuel – Ampol");
    if (rand() < 0.3) add("expense", between(5, 28), "eatingOut", d, pick(cafes));
    if (rand() < 1 / 12) add("expense", between(15, 85), "shopping", d, pick(shops));
    if (rand() < 1 / 14) add("expense", between(14, 60), "entertainment", d, pick(fun));
  }
  add("expense", 12995, "education", day(-102), "Textbooks – Co-op");
  add("expense", 4500, "education", day(-40), "Lab coat & safety glasses");
  add("expense", 3250, "personalCare", day(-75), "Haircut");
  add("expense", 3400, "personalCare", day(-21), "Haircut");
  add("expense", 1840, "health", day(-58), "Chemist Warehouse");
  add("expense", 4200, "gifts", day(-30), "Mum's birthday present");
  add("expense", 18900, "travel", day(-88), "Jetstar to Melbourne");
  add("expense", 6450, "health", day(-6), "GP gap fee");

  const bill = (name, amount, category, frequency, due, remindDays) => ({
    id: uid(), name, amount, category, frequency, anchor: due, nextDue: due, remindDays,
    active: true, lastPaid: null, sample: true,
  });
  const rentNext = D.addDays(lastMonday, 7);
  const bills = [
    { ...bill("Rent", 32000, "rent", "weekly", rentNext, 1), lastPaid: lastMonday },
    bill("Optus mobile", 3500, "phoneInternet", "monthly", nextMonthly(12), 1),
    bill("NBN (my share)", 2750, "phoneInternet", "monthly", nextMonthly(20), 1),
    bill("Netflix", 1899, "subscriptions", "monthly", nextMonthly(3), null),
    bill("Spotify", 1399, "subscriptions", "monthly", nextMonthly(15), null),
    bill("Gym membership", 2490, "subscriptions", "fortnightly", gymNext, null),
    bill("Electricity (share)", 18640, "utilities", "quarterly", electricityNext, 3),
    bill("Car insurance", 7415, "insurance", "monthly", carInsuranceNext, 2),
  ];

  const budgets = [
    { id: uid(), category: null, amount: 270000, period: "monthly", sample: true },
    { id: uid(), category: "groceries", amount: 40000, period: "monthly", sample: true },
    { id: uid(), category: "eatingOut", amount: 16000, period: "monthly", sample: true },
    { id: uid(), category: "transport", amount: 6000, period: "weekly", sample: true },
    { id: uid(), category: "shopping", amount: 12000, period: "monthly", sample: true },
  ];

  const firstPay = D.addDays(lastThursday, -112);
  const payContribs = (amount) => {
    const out = [];
    for (let i = 0; i < 9; i++) {
      const d = D.addDays(firstPay, i * 14);
      if (d <= today) out.push({ id: uid(), date: d, amount, note: "Payday transfer" });
    }
    return out;
  };
  const goals = [
    { id: uid(), name: "Emergency fund", icon: "🛟", target: 200000, targetDate: null, created: day(-110), sample: true,
      contributions: [{ id: uid(), date: day(-110), amount: 40000, note: "Starting amount" }, ...payContribs(6000)] },
    { id: uid(), name: "Japan trip", icon: "✈️", target: 350000, targetDate: D.addMonths(today, 9), created: day(-110), sample: true,
      contributions: payContribs(8000) },
    { id: uid(), name: "New laptop", icon: "💻", target: 160000, targetDate: D.addMonths(today, 5), created: day(-96), sample: true,
      contributions: [{ id: uid(), date: day(-96), amount: 30000, note: "Part of tax refund" }] },
  ];

  return {
    transactions: tx.sort((a, b) => (a.date < b.date ? 1 : -1)),
    bills, budgets, goals,
    settings: {
      openingBalance: 220000, openingSample: true,
      pay: { amount: 135000, frequency: "fortnightly", anchor: lastThursday, category: "partTime" },
      paySample: true, savingsPerPay: 14000,
    },
  };
}

// ---- CSV ---------------------------------------------------------------------

const csvEscape = (value) => {
  let v = String(value ?? "");
  if (/^[=+\-@]/.test(v) && parseMoney(v) === null) v = "'" + v; // stop spreadsheet formulas
  return /[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
};

export function transactionsToCSV(transactions) {
  const rows = [["Date", "Type", "Category", "Description", "Amount (AUD)", "Sample"]];
  for (const t of [...transactions].sort((a, b) => (a.date < b.date ? 1 : -1))) {
    const signedCents = t.kind === "income" ? t.amount : -t.amount;
    rows.push([D.fmtDMY(t.date), t.kind === "income" ? "Income" : "Expense", cat(t.category).name, t.note,
      (signedCents / 100).toFixed(2), t.sample ? "Yes" : "No"]);
  }
  return rows.map((r) => r.map(csvEscape).join(",")).join("\r\n") + "\r\n";
}

export function parseCSVRows(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  const s = text.replace(/^﻿/, "");
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (quoted) {
      if (c === '"') {
        if (s[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && s[i + 1] === "\n") i++;
      row.push(field); field = "";
      rows.push(row); row = [];
    } else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows.filter((r) => r.some((f) => f.trim()));
}

/** Reads transactions from CSV with Date and Amount columns (Type, Category, Description optional). */
export function transactionsFromCSV(text) {
  const rows = parseCSVRows(text);
  if (!rows.length) throw new Error("The file has no rows to import.");
  const names = rows[0].map((h) => h.trim().toLowerCase());
  const col = (...opts) => names.findIndex((n) => opts.some((o) => n.startsWith(o)));
  const dateCol = col("date");
  const amountCol = col("amount", "value");
  if (dateCol < 0 || amountCol < 0) {
    throw new Error("The file needs at least Date and Amount columns. Export a CSV from this app to see the layout.");
  }
  const typeCol = col("type", "kind");
  const catCol = col("category");
  const noteCol = col("description", "note", "details", "payee");
  const transactions = [];
  const skipped = [];
  rows.slice(1).forEach((row, i) => {
    const f = (c) => (c >= 0 && c < row.length ? row[c].trim() : "");
    const date = D.parseAUDate(f(dateCol));
    const amount = parseMoney(f(amountCol));
    if (!date || amount === null || amount === 0) { skipped.push(i + 2); return; }
    const type = f(typeCol).toLowerCase();
    const kind = type.startsWith("inc") || type === "credit" ? "income"
      : type.startsWith("exp") || type === "debit" ? "expense"
      : amount < 0 ? "expense" : "income";
    transactions.push({
      id: uid(), kind, amount: Math.abs(amount), category: matchCategory(f(catCol), kind),
      date, note: f(noteCol).replace(/^'/, "").slice(0, 120), sample: false, billId: null,
    });
  });
  return { transactions, skipped };
}

// ---- Calendar (.ics) -----------------------------------------------------------

const RRULE = { weekly: "FREQ=WEEKLY", fortnightly: "FREQ=WEEKLY;INTERVAL=2", monthly: "FREQ=MONTHLY",
  quarterly: "FREQ=MONTHLY;INTERVAL=3", yearly: "FREQ=YEARLY" };

/** Bills as calendar events with alerts, so the phone's Calendar can remind you. */
export function billsToICS(bills) {
  const esc = (s) => String(s).replace(/[\\;,]/g, (m) => "\\" + m).replace(/\n/g, "\\n");
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
  const lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Budget Planner//EN", "CALSCALE:GREGORIAN"];
  for (const b of bills.filter((x) => x.active)) {
    const start = b.nextDue.replace(/-/g, "");
    const end = D.addDays(b.nextDue, 1).replace(/-/g, "");
    lines.push("BEGIN:VEVENT", `UID:${b.id}@budget-planner`, `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${start}`, `DTEND;VALUE=DATE:${end}`,
      `SUMMARY:${esc(`${b.name} due – $${(b.amount / 100).toFixed(2)}`)}`,
      `DESCRIPTION:${esc("Added from Budget Planner")}`);
    if (RRULE[b.frequency]) lines.push(`RRULE:${RRULE[b.frequency]}`);
    const days = b.remindDays ?? 1;
    // All-day events start at midnight, so this fires at 9 am on the reminder day.
    const hours = days * 24 - 9;
    lines.push("BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${esc(`${b.name} is due`)}`,
      hours > 0 ? `TRIGGER:-PT${hours}H` : `TRIGGER:PT${-hours}H`, "END:VALARM", "END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}
