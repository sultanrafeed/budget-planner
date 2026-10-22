// Add/edit forms, shown as bottom sheets.

import * as D from "./dates.js";
import * as E from "./engine.js";
import * as store from "./store.js";
import { CATEGORIES, cat, categoriesFor, GOAL_ICONS } from "./categories.js";
import { money, money0, parseMoney, amountProblem, centsToInput } from "./money.js";
import { uid } from "./data.js";
import { esc, openSheet, closeSheet, showError, toast, catIcon, txRow, sampleBadge } from "./ui.js";
import { ring } from "./charts.js";

const val = (form, name) => form.elements[name]?.value ?? "";
const checked = (form, name) => !!form.elements[name]?.checked;

function amountField(name, value, { large = false, placeholder = "0.00" } = {}) {
  if (large) {
    return `<div class="amount-input"><span>$</span><input name="${name}" inputmode="decimal" autocomplete="off" placeholder="${placeholder}" value="${esc(value)}" aria-label="Amount"></div>`;
  }
  return `<input name="${name}" inputmode="decimal" autocomplete="off" placeholder="${placeholder}" value="${esc(value)}">`;
}

function categoryGrid(kind, selected) {
  return `<div class="cat-grid">${categoriesFor(kind).map((id) => `
    <label><input type="radio" name="category" value="${id}" ${id === selected ? "checked" : ""}>
      ${catIcon(id)}<span>${esc(cat(id).name)}</span></label>`).join("")}</div>`;
}

function categoryOptions(kind, selected, { includeAll = false } = {}) {
  return (includeAll ? `<option value="" ${!selected ? "selected" : ""}>All spending</option>` : "") +
    categoriesFor(kind).map((id) => `<option value="${id}" ${id === selected ? "selected" : ""}>${cat(id).icon} ${esc(cat(id).name)}</option>`).join("");
}

function frequencyOptions(selected, list = Object.keys(D.FREQUENCIES)) {
  return list.map((f) => `<option value="${f}" ${f === selected ? "selected" : ""}>${D.FREQUENCIES[f].label}</option>`).join("");
}

/** The category used most often recently, for quick adding. */
export function suggestedCategory(data, kind) {
  const counts = new Map();
  data.transactions.filter((t) => t.kind === kind && !t.sample).slice(-30)
    .forEach((t) => counts.set(t.category, (counts.get(t.category) || 0) + 1));
  const best = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
  return best ? best[0] : kind === "expense" ? "groceries" : "salary";
}

/** Removes something with an Undo option. */
function withUndo(message, change) {
  const before = structuredClone(store.get());
  store.update(change);
  toast(message, { label: "Undo", run: () => store.replace(before) });
}

// ---- Transactions --------------------------------------------------------------

export function transactionForm(existing, kind = "expense") {
  const data = store.get();
  const t = existing || { kind, amount: 0, category: suggestedCategory(data, kind), date: D.today(), note: "" };
  openSheet({
    title: existing ? "Edit" : kind === "income" ? "New Income" : "New Expense",
    body: `
      <div class="segmented" role="radiogroup">
        <button type="button" data-kind="expense" class="${t.kind === "expense" ? "on" : ""}">Expense</button>
        <button type="button" data-kind="income" class="${t.kind === "income" ? "on" : ""}">Income</button>
      </div>
      <input type="hidden" name="kind" value="${t.kind}">
      ${amountField("amount", centsToInput(t.amount), { large: true })}
      <div class="form-error"></div>
      <div class="form-label">Category</div>
      <div data-cats>${categoryGrid(t.kind, t.category)}</div>
      <div class="form-hint" data-hint>${esc(cat(t.category).hint)}</div>
      <div class="form-label">Details</div>
      <div class="field-group">
        <div class="field"><label for="f-date">Date</label><input id="f-date" type="date" name="date" value="${t.date}" required></div>
        <div class="field"><input class="left" name="note" maxlength="120" placeholder="${t.kind === "expense" ? "Note, e.g. Coles" : "Note, e.g. Pay from work"}" value="${esc(t.note)}" aria-label="Note"></div>
      </div>
      ${existing ? `<div style="margin-top:24px"><button type="button" class="btn danger" data-delete>Delete</button></div>
        ${existing.sample ? `<div class="form-hint">This is a sample record. Saving changes turns it into your own.</div>` : ""}` : ""}`,
    onMount(form) {
      if (!existing) setTimeout(() => form.elements.amount.focus(), 320);
      form.querySelectorAll("[data-kind]").forEach((b) => b.addEventListener("click", () => {
        const k = b.dataset.kind;
        form.elements.kind.value = k;
        form.querySelectorAll("[data-kind]").forEach((x) => x.classList.toggle("on", x === b));
        const current = form.querySelector('input[name="category"]:checked')?.value;
        const next = CATEGORIES[current]?.kind === k ? current : suggestedCategory(store.get(), k);
        form.querySelector("[data-cats]").innerHTML = categoryGrid(k, next);
        form.querySelector("[data-hint]").textContent = cat(next).hint;
      }));
      form.addEventListener("change", (e) => {
        if (e.target.name === "category") form.querySelector("[data-hint]").textContent = cat(e.target.value).hint;
      });
      form.querySelector("[data-delete]")?.addEventListener("click", () => {
        closeSheet();
        withUndo("Deleted", (d) => { d.transactions = d.transactions.filter((x) => x.id !== existing.id); });
      });
    },
    onSave(form) {
      const problem = amountProblem(val(form, "amount"));
      if (problem) return showError(form, problem);
      const date = val(form, "date");
      if (!D.isValid(date)) return showError(form, "Choose a date.");
      const category = form.querySelector('input[name="category"]:checked')?.value;
      const k = val(form, "kind");
      const record = {
        id: existing?.id || uid(), kind: k, amount: parseMoney(val(form, "amount")),
        category: CATEGORIES[category]?.kind === k ? category : suggestedCategory(store.get(), k),
        date, note: val(form, "note").trim(), sample: false, billId: existing?.billId || null,
      };
      store.update((d) => {
        const i = d.transactions.findIndex((x) => x.id === record.id);
        if (i >= 0) d.transactions[i] = record;
        else d.transactions.push(record);
      });
      toast(existing ? "Saved" : `${k === "income" ? "Income" : "Expense"} added`);
    },
  });
}

// ---- Budgets -------------------------------------------------------------------

export function budgetForm(existing) {
  const data = store.get();
  const today = D.today();
  const b = existing || { category: null, amount: 0, period: "monthly" };
  const typical = () => {
    const form = document.querySelector(".sheet form");
    if (!form) return "";
    const avg = E.monthlyAverages(store.get(), today);
    if (!avg.enough) return "";
    const category = val(form, "category") || null;
    const period = val(form, "period");
    const monthly = category ? E.monthlySpendingByCategory(store.get(), today).find((c) => c.category === category)?.amount || 0 : avg.expenses;
    if (!monthly) return "";
    const amount = period === "weekly" ? Math.round((monthly * 12) / 52) : monthly;
    return `You usually spend about ${money0(amount)} a ${period === "weekly" ? "week" : "month"} on ${category ? cat(category).name.toLowerCase() : "everything"}.`;
  };
  openSheet({
    title: existing ? "Edit Budget" : "New Budget",
    body: `
      <div class="field-group">
        <div class="field"><label for="b-cat">Budget for</label><select id="b-cat" name="category">${categoryOptions("expense", b.category, { includeAll: true })}</select></div>
        <div class="field"><label for="b-period">Period</label><select id="b-period" name="period">
          <option value="monthly" ${b.period === "monthly" ? "selected" : ""}>Monthly</option>
          <option value="weekly" ${b.period === "weekly" ? "selected" : ""}>Weekly</option></select></div>
      </div>
      <div class="form-label">Limit</div>
      ${amountField("amount", centsToInput(b.amount), { large: true })}
      <div class="form-error"></div>
      <div class="form-hint" data-typical></div>
      ${existing ? `<div style="margin-top:24px"><button type="button" class="btn danger" data-delete>Delete budget</button></div>
        <div class="form-hint">Deleting a budget doesn't affect your transactions.</div>` : ""}`,
    onMount(form) {
      const refresh = () => (form.querySelector("[data-typical]").textContent = typical());
      refresh();
      form.addEventListener("change", refresh);
      form.querySelector("[data-delete]")?.addEventListener("click", () => {
        closeSheet();
        withUndo("Budget deleted", (d) => { d.budgets = d.budgets.filter((x) => x.id !== existing.id); });
      });
    },
    onSave(form) {
      const problem = amountProblem(val(form, "amount"));
      if (problem) return showError(form, problem);
      const category = val(form, "category") || null;
      const period = val(form, "period");
      if (data.budgets.some((x) => x.id !== existing?.id && (x.category || null) === category && x.period === period)) {
        return showError(form, `You already have a ${period} budget for ${category ? cat(category).name.toLowerCase() : "all spending"}. Edit that one instead.`);
      }
      const record = { id: existing?.id || uid(), category, period, amount: parseMoney(val(form, "amount")), sample: false };
      store.update((d) => {
        const i = d.budgets.findIndex((x) => x.id === record.id);
        if (i >= 0) d.budgets[i] = record;
        else d.budgets.push(record);
      });
    },
  });
}

// ---- Bills ---------------------------------------------------------------------

const PRESETS = [
  ["Rent", "rent", "weekly"], ["Electricity", "utilities", "quarterly"], ["Phone", "phoneInternet", "monthly"],
  ["Internet", "phoneInternet", "monthly"], ["Car rego", "transport", "yearly"], ["Car insurance", "insurance", "monthly"],
  ["Health insurance", "insurance", "monthly"], ["Netflix", "subscriptions", "monthly"], ["Spotify", "subscriptions", "monthly"],
  ["Gym", "subscriptions", "fortnightly"], ["Water", "utilities", "quarterly"], ["Gas", "utilities", "quarterly"],
];

const REMINDERS = [[null, "No reminder"], [0, "On the day"], [1, "1 day before"], [2, "2 days before"], [3, "3 days before"], [7, "1 week before"]];

/** Records a bill payment and moves it to the next due date. */
export function markPaid(billId, { undo = true } = {}) {
  const today = D.today();
  const change = (d) => {
    const b = d.bills.find((x) => x.id === billId);
    if (!b) return;
    d.transactions.push({ id: uid(), kind: "expense", amount: b.amount, category: b.category, date: today, note: b.name, sample: b.sample, billId: b.id });
    b.lastPaid = today;
    advance(b);
  };
  const name = store.get().bills.find((x) => x.id === billId)?.name || "Bill";
  if (undo) withUndo(`${name} marked as paid`, change);
  else store.update(change);
}

export function skipBill(billId) {
  withUndo("Skipped to next due date", (d) => {
    const b = d.bills.find((x) => x.id === billId);
    if (b) advance(b);
  });
}

function advance(bill) {
  const next = D.nextOccurrence(bill.frequency, bill.nextDue, bill.anchor);
  if (next) bill.nextDue = next;
  else bill.active = false;
}

export function billForm(existing) {
  const b = existing || { name: "", amount: 0, category: "utilities", frequency: "monthly", nextDue: D.today(), remindDays: 1 };
  openSheet({
    title: existing ? "Edit Bill" : "New Bill",
    body: `
      ${existing ? "" : `<div class="form-label" style="margin-top:4px">Quick pick</div>
        <div class="chips">${PRESETS.map(([n, c, f]) => `<button type="button" class="chip" data-preset="${esc(n)}|${c}|${f}">${cat(c).icon} ${esc(n)}</button>`).join("")}</div>
        <div style="height:12px"></div>`}
      <div class="field-group">
        <div class="field"><input class="left" name="name" maxlength="60" placeholder="Name, e.g. Rent" value="${esc(b.name)}" aria-label="Name"></div>
        <div class="field"><label>Amount</label>${amountField("amount", centsToInput(b.amount))}</div>
      </div>
      <div class="form-error"></div>
      <div class="field-group" style="margin-top:18px">
        <div class="field"><label for="bl-f">Repeats</label><select id="bl-f" name="frequency">${frequencyOptions(b.frequency)}</select></div>
        <div class="field"><label for="bl-d">${existing ? "Next due" : "First due"}</label><input id="bl-d" type="date" name="nextDue" value="${b.nextDue}"></div>
        <div class="field"><label for="bl-c">Category</label><select id="bl-c" name="category">${categoryOptions("expense", b.category)}</select></div>
        <div class="field"><label for="bl-r">Remind me</label><select id="bl-r" name="remindDays">${REMINDERS.map(([v, l]) => `<option value="${v ?? ""}" ${v === b.remindDays ? "selected" : ""}>${l}</option>`).join("")}</select></div>
      </div>
      <div class="form-hint">Reminders work through your phone's Calendar: after saving, use Plan → Bills → "Add reminders to Calendar".</div>
      ${existing ? `
        <div style="margin-top:24px" class="stack">
          <button type="button" class="btn secondary" data-paid>Mark as paid today</button>
          ${existing.frequency !== "once" ? `<button type="button" class="btn secondary" data-skip>Skip this payment</button>` : ""}
          <button type="button" class="btn danger" data-delete>Delete bill</button>
        </div>
        ${existing.lastPaid ? `<div class="form-hint">Last paid ${D.fmtDMY(existing.lastPaid)}. Past payments stay in your activity.</div>` : ""}` : ""}`,
    onMount(form) {
      form.querySelectorAll("[data-preset]").forEach((btn) => btn.addEventListener("click", () => {
        const [n, c, f] = btn.dataset.preset.split("|");
        form.elements.name.value = n;
        form.elements.category.value = c;
        form.elements.frequency.value = f;
        form.elements.amount.focus();
      }));
      form.querySelector("[data-paid]")?.addEventListener("click", () => {
        if (save(form) === false) return;
        closeSheet();
        markPaid(existing.id);
      });
      form.querySelector("[data-skip]")?.addEventListener("click", () => {
        if (save(form) === false) return;
        closeSheet();
        skipBill(existing.id);
      });
      form.querySelector("[data-delete]")?.addEventListener("click", () => {
        closeSheet();
        withUndo("Bill deleted", (d) => { d.bills = d.bills.filter((x) => x.id !== existing.id); });
      });
    },
    onSave: (form) => save(form),
  });

  function save(form) {
    const name = val(form, "name").trim();
    if (!name) return showError(form, "Give the bill a name.");
    const problem = amountProblem(val(form, "amount"));
    if (problem) return showError(form, problem);
    const due = val(form, "nextDue");
    if (!D.isValid(due)) return showError(form, "Choose a due date.");
    const frequency = val(form, "frequency");
    const remind = val(form, "remindDays");
    const record = {
      ...(existing || { id: uid(), lastPaid: null }),
      name, amount: parseMoney(val(form, "amount")), category: val(form, "category"), frequency,
      remindDays: remind === "" ? null : Number(remind), active: true, sample: false,
    };
    // Changing the date or how often it repeats restarts the schedule from the new date.
    if (!existing || existing.nextDue !== due || existing.frequency !== frequency) {
      record.anchor = due;
      record.nextDue = due;
    }
    store.update((d) => {
      const i = d.bills.findIndex((x) => x.id === record.id);
      if (i >= 0) d.bills[i] = record;
      else d.bills.push(record);
    });
  }
}

// ---- Goals ---------------------------------------------------------------------

export function goalForm(existing) {
  const g = existing || { name: "", icon: "⭐️", target: 0, targetDate: null };
  const defaultDate = D.addMonths(D.today(), 6);
  openSheet({
    title: existing ? "Edit Goal" : "New Goal",
    body: `
      <div class="field-group">
        <div class="field"><input class="left" name="name" maxlength="60" placeholder="Name, e.g. Emergency fund" value="${esc(g.name)}" aria-label="Name"></div>
        <div class="field"><label>Target</label>${amountField("target", centsToInput(g.target))}</div>
      </div>
      <div class="form-error"></div>
      <div class="form-label">Icon</div>
      <div class="icon-grid">${GOAL_ICONS.map((i) => `<label><input type="radio" name="icon" value="${i}" ${i === g.icon ? "checked" : ""}><span>${i}</span></label>`).join("")}</div>
      <div class="field-group" style="margin-top:18px">
        <div class="field toggle"><label for="g-has">Reach it by a date</label><span class="switch"><input id="g-has" type="checkbox" name="hasDate" ${g.targetDate ? "checked" : ""}><span></span></span></div>
        <div class="field" data-date-row ${g.targetDate ? "" : "hidden"}><label for="g-date">Target date</label><input id="g-date" type="date" name="targetDate" min="${D.addDays(D.today(), 1)}" value="${g.targetDate || defaultDate}"></div>
      </div>
      <div class="form-hint" data-plan></div>
      ${existing ? "" : `
        <div class="field-group" style="margin-top:18px">
          <div class="field"><label>Already saved</label>${amountField("starting", "", { placeholder: "Optional" })}</div>
        </div>
        <div class="form-hint">This amount is moved from your available balance into the goal.</div>`}
      ${existing ? `<div style="margin-top:24px"><button type="button" class="btn danger" data-delete>Delete goal</button></div>
        <div class="form-hint">The money saved in this goal goes back into your available balance.</div>` : ""}`,
    onMount(form) {
      const refresh = () => {
        form.querySelector("[data-date-row]").hidden = !checked(form, "hasDate");
        const target = parseMoney(val(form, "target")) || 0;
        const saved = existing ? E.goalSaved(existing) : parseMoney(val(form, "starting")) || 0;
        const r = checked(form, "hasDate") && target > 0 && E.goalRequired(Math.max(0, target - saved), D.today(), val(form, "targetDate"));
        form.querySelector("[data-plan]").textContent = r ? `You'll need to save about ${money0(r.perWeek)} a week or ${money0(r.perMonth)} a month.` : "";
      };
      refresh();
      form.addEventListener("input", refresh);
      form.addEventListener("change", refresh);
      form.querySelector("[data-delete]")?.addEventListener("click", () => {
        closeSheet();
        withUndo("Goal deleted", (d) => { d.goals = d.goals.filter((x) => x.id !== existing.id); });
      });
    },
    onSave(form) {
      const name = val(form, "name").trim();
      if (!name) return showError(form, "Give the goal a name.");
      const problem = amountProblem(val(form, "target"));
      if (problem) return showError(form, problem);
      const hasDate = checked(form, "hasDate");
      const targetDate = val(form, "targetDate");
      if (hasDate && (!D.isValid(targetDate) || targetDate <= D.today())) return showError(form, "Choose a target date in the future.");
      const startText = val(form, "starting");
      const starting = startText ? parseMoney(startText) : 0;
      if (starting === null || starting < 0) return showError(form, "Check the amount already saved.");
      const record = {
        ...(existing || { id: uid(), contributions: [], created: D.today() }),
        name, icon: form.querySelector('input[name="icon"]:checked')?.value || "⭐️",
        target: parseMoney(val(form, "target")), targetDate: hasDate ? targetDate : null, sample: false,
      };
      if (!existing && starting > 0) record.contributions = [{ id: uid(), date: D.today(), amount: starting, note: "Starting amount" }];
      store.update((d) => {
        const i = d.goals.findIndex((x) => x.id === record.id);
        if (i >= 0) d.goals[i] = record;
        else d.goals.push(record);
      });
    },
  });
}

export function contributionForm(goal, mode) {
  const data = store.get();
  const saved = E.goalSaved(goal);
  const usual = data.settings.savingsPerPay;
  openSheet({
    title: mode === "add" ? `Add to ${goal.name}` : `Take out of ${goal.name}`,
    body: `
      ${amountField("amount", "", { large: true })}
      <div class="form-error"></div>
      <div class="form-hint">${mode === "add" ? `Available to move: ${money(E.availableBalance(data, D.today()))}` : `In this goal: ${money(saved)}`}</div>
      ${mode === "add" && usual > 0 ? `<div style="margin:12px 0 0"><button type="button" class="chip" data-usual>Use my usual ${money(usual)} per pay</button></div>` : ""}
      <div class="field-group" style="margin-top:18px">
        <div class="field"><label for="c-date">Date</label><input id="c-date" type="date" name="date" value="${D.today()}"></div>
        <div class="field"><input class="left" name="note" maxlength="80" placeholder="Note (optional)" aria-label="Note"></div>
      </div>`,
    onMount(form) {
      setTimeout(() => form.elements.amount.focus(), 320);
      form.querySelector("[data-usual]")?.addEventListener("click", () => (form.elements.amount.value = centsToInput(usual)));
    },
    onSave(form) {
      const problem = amountProblem(val(form, "amount"));
      if (problem) return showError(form, problem);
      const amount = parseMoney(val(form, "amount"));
      if (mode === "withdraw" && amount > saved) return showError(form, `You can take out up to ${money(saved)}.`);
      const date = D.isValid(val(form, "date")) ? val(form, "date") : D.today();
      store.update((d) => {
        d.goals.find((x) => x.id === goal.id)?.contributions.push({ id: uid(), date, amount: mode === "add" ? amount : -amount, note: val(form, "note").trim() });
      });
      toast(mode === "add" ? "Added to goal" : "Taken out of goal");
      setTimeout(() => goalDetail(goal.id), 320);
    },
  });
}

export function goalDetail(goalId) {
  const data = store.get();
  const goal = data.goals.find((g) => g.id === goalId);
  if (!goal) return;
  const today = D.today();
  const saved = E.goalSaved(goal);
  const remaining = Math.max(0, goal.target - saved);
  const done = goal.target > 0 && saved >= goal.target;
  const req = goal.targetDate && !done ? E.goalRequired(remaining, today, goal.targetDate) : null;
  const capacity = E.savingsCapacity(data, today);
  let plan;
  if (done) plan = `<div class="good bold">🎉 You've reached this goal. Nice work!</div>`;
  else if (req) {
    plan = `<div class="small" style="margin-bottom:10px">To save ${money(remaining)} more by ${D.fmtLong(goal.targetDate)} (${req.days} days), put aside:</div>
      <div class="stats">
        <div class="stat"><div class="label">Each week</div><div class="value" style="color:var(--accent)">${money0(req.perWeek)}</div></div>
        <div class="stat"><div class="label">Each fortnight</div><div class="value">${money0(req.perFortnight)}</div></div>
        <div class="stat"><div class="label">Each month</div><div class="value">${money0(req.perMonth)}</div></div>
      </div>
      ${capacity.averages.enough && req.perMonth > capacity.monthly ? `<div class="small warn" style="margin-top:10px">⚠️ That's more than the ${money0(capacity.monthly)} a month you can realistically save right now. Consider a later date or trimming spending.</div>` : ""}`;
  } else {
    plan = `${goal.targetDate ? `<div class="small warn" style="margin-bottom:10px">The target date (${D.fmtDMY(goal.targetDate)}) has passed. Edit the goal to set a new one.</div>` : ""}
      <div class="row small">If I save <span class="amount-input" style="padding:4px 10px;margin:0;width:110px"><span style="font-size:17px">$</span><input data-weekly inputmode="decimal" placeholder="50" style="font-size:17px" aria-label="Weekly amount"></span> a week</div>
      <div class="small" style="margin-top:8px" data-finish>Enter a weekly amount to see when you'll get there.</div>`;
  }
  const history = [...goal.contributions].sort((a, b) => (a.date < b.date ? 1 : -1));
  openSheet({
    title: goal.name,
    cancel: "Done",
    body: `
      <div class="card center" style="padding:20px">
        <div style="display:flex;justify-content:center">${ring(goal.target ? saved / goal.target : 0, { size: 170, stroke: 14, color: done ? "var(--green)" : "var(--accent)",
          inner: `<div style="font-size:28px">${goal.icon}</div><div class="num" style="font-size:26px;font-weight:700">${money0(saved)}</div><div class="small muted">of ${money0(goal.target)}</div>` })}</div>
        <div class="row" style="margin-top:18px">
          <button type="button" class="btn" data-add>＋ Add money</button>
          <button type="button" class="btn secondary" data-withdraw ${saved <= 0 ? "disabled" : ""}>− Take out</button>
        </div>
      </div>
      <div class="form-label">Plan</div>
      <div class="card">${plan}</div>
      <div class="form-label">History</div>
      <div class="list plain">${history.length ? history.map((c) => `
        <div class="list-row"><div class="grow"><div>${esc(c.note || (c.amount >= 0 ? "Added" : "Taken out"))}</div><div class="small muted">${D.fmtDMY(c.date)}</div></div>
          <div class="num ${c.amount >= 0 ? "good" : ""}">${c.amount >= 0 ? "+" : "-"}${money(Math.abs(c.amount))}</div>
          <button type="button" class="icon-btn" style="font-size:18px;color:var(--text-3)" data-del-contrib="${esc(c.id)}" aria-label="Delete entry">✕</button></div>`).join("")
        : `<div class="list-row muted">No money added yet.</div>`}</div>
      <div class="form-hint">Money added to a goal is set aside from your available balance. Taking it out puts it back.</div>
      <div style="margin-top:20px"><button type="button" class="btn secondary" data-edit>Edit goal</button></div>`,
    onMount(form) {
      form.querySelector("[data-add]").addEventListener("click", () => contributionForm(goal, "add"));
      form.querySelector("[data-withdraw]").addEventListener("click", () => contributionForm(goal, "withdraw"));
      form.querySelector("[data-edit]").addEventListener("click", () => goalForm(goal));
      form.querySelectorAll("[data-del-contrib]").forEach((b) => b.addEventListener("click", () => {
        if (!confirm("Delete this entry?")) return;
        store.update((d) => {
          const g = d.goals.find((x) => x.id === goal.id);
          g.contributions = g.contributions.filter((c) => c.id !== b.dataset.delContrib);
        });
        goalDetail(goal.id);
      }));
      const weekly = form.querySelector("[data-weekly]");
      weekly?.addEventListener("input", () => {
        const per = parseMoney(weekly.value) || 0;
        const finish = per > 0 ? E.goalFinishDate(remaining, per, today) : null;
        form.querySelector("[data-finish]").innerHTML = finish
          ? `You'll reach ${money0(goal.target)} around <b>${D.fmtLong(finish)}</b>.`
          : "Enter a weekly amount to see when you'll get there.";
      });
    },
  });
}

// ---- Pay and balance -----------------------------------------------------------

export function payForm() {
  const data = store.get();
  const p = data.settings.pay || { amount: 0, frequency: "fortnightly", anchor: D.today(), category: "salary" };
  openSheet({
    title: "Payday",
    body: `
      <div class="field-group">
        <div class="field"><label>Take-home pay</label>${amountField("amount", centsToInput(p.amount))}</div>
        <div class="field"><label for="p-f">How often</label><select id="p-f" name="frequency">${frequencyOptions(p.frequency, ["weekly", "fortnightly", "monthly"])}</select></div>
        <div class="field"><label for="p-d">A recent or next payday</label><input id="p-d" type="date" name="anchor" value="${p.anchor}"></div>
        <div class="field"><label for="p-c">Pay type</label><select id="p-c" name="category">${categoryOptions("income", p.category)}</select></div>
      </div>
      <div class="form-error"></div>
      <div class="form-hint">Use the amount that lands in your account after tax. Any past or future payday works – we count forward from it.</div>
      <div class="field-group" style="margin-top:18px">
        <div class="field"><label>Savings per pay</label>${amountField("savings", centsToInput(data.settings.savingsPerPay), { placeholder: "Optional" })}</div>
      </div>
      <div class="form-hint">How much you'd like to move to savings each payday. Used to plan your next pay.</div>
      ${data.settings.pay ? `<div style="margin-top:24px"><button type="button" class="btn danger" data-remove>Remove payday</button></div>` : ""}`,
    onMount(form) {
      form.querySelector("[data-remove]")?.addEventListener("click", () => {
        closeSheet();
        store.update((d) => Object.assign(d.settings, { pay: null, savingsPerPay: 0, paySample: false }));
      });
    },
    onSave(form) {
      const problem = amountProblem(val(form, "amount"));
      if (problem) return showError(form, problem);
      const anchor = val(form, "anchor");
      if (!D.isValid(anchor)) return showError(form, "Choose a payday.");
      const savingsText = val(form, "savings");
      const savings = savingsText ? parseMoney(savingsText) : 0;
      if (savings === null || savings < 0) return showError(form, "Check the savings amount.");
      const amount = parseMoney(val(form, "amount"));
      if (savings > amount) return showError(form, "Savings per pay can't be more than your pay.");
      store.update((d) => Object.assign(d.settings, {
        pay: { amount, frequency: val(form, "frequency"), anchor, category: val(form, "category") },
        savingsPerPay: savings, paySample: false,
      }));
    },
  });
}

export function openingBalanceForm() {
  const s = store.get().settings;
  openSheet({
    title: "Starting balance",
    body: `
      ${amountField("amount", centsToInput(Math.abs(s.openingBalance)), { large: true })}
      <div class="field-group">
        <div class="field toggle"><label for="ob-neg">I'm in overdraft (negative)</label><span class="switch"><input id="ob-neg" type="checkbox" name="negative" ${s.openingBalance < 0 ? "checked" : ""}><span></span></span></div>
      </div>
      <div class="form-error"></div>
      <div class="form-hint">Add up the everyday accounts you spend from, as they were when you started using the app. Don't include money already in savings goals.</div>`,
    onSave(form) {
      const text = val(form, "amount");
      if (text && amountProblem(text, { allowZero: true })) return showError(form, amountProblem(text, { allowZero: true }));
      const amount = text ? parseMoney(text) : 0;
      store.update((d) => Object.assign(d.settings, { openingBalance: checked(form, "negative") ? -amount : amount, openingSample: false }));
    },
  });
}

/** Lists transactions for one category in a date range. */
export function categorySheet(category, range, label) {
  const items = E.txIn(store.get(), range).filter((t) => t.category === category).sort((a, b) => (a.date < b.date ? 1 : -1));
  const total = items.reduce((s, t) => s + t.amount, 0);
  openSheet({
    title: `${cat(category).name} · ${label}`,
    cancel: "Done",
    body: `<div class="list">${items.map((t) => txRow(t, { showDate: true })).join("")}</div>
      <div class="form-hint">${items.length} transactions · ${money(total)}</div>`,
  });
}

export { sampleBadge };
