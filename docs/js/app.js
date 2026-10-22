import * as D from "./dates.js";
import * as store from "./store.js";
import { ui, remember } from "./state.js";
import { sampleData, removeSampleData, emptyData, validateData, transactionsToCSV, transactionsFromCSV, billsToICS, uid } from "./data.js";
import { toast, shareFile, pickFile, fileDate, openSheet, showError } from "./ui.js";
import { parseMoney, amountProblem } from "./money.js";
import * as F from "./forms.js";
import * as Home from "./views/home.js";
import * as Activity from "./views/activity.js";
import * as Plan from "./views/plan.js";
import * as Insights from "./views/insights.js";
import * as Settings from "./views/settings.js";

const app = document.getElementById("app");
const VIEWS = { home: Home, activity: Activity, plan: Plan, insights: Insights, settings: Settings };

const ICONS = {
  home: '<path d="M4 11.5 13 4l9 7.5V21a1 1 0 0 1-1 1h-5v-6h-6v6H5a1 1 0 0 1-1-1z" fill="currentColor"/>',
  activity: '<rect x="4" y="4" width="18" height="18" rx="4" fill="none" stroke="currentColor" stroke-width="2"/><path d="M8 10h10M8 13.5h10M8 17h6" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  plan: '<rect x="4" y="6" width="18" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="2"/><path d="M4 11h18M9 3.5v5M17 3.5v5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  insights: '<path d="M13 3a10 10 0 1 0 10 10H13z" fill="currentColor" opacity=".45"/><path d="M15 2a9 9 0 0 1 9 9h-9z" fill="currentColor"/>',
  settings: '<circle cx="13" cy="13" r="3.2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M13 3v3M13 20v3M3 13h3M20 13h3M5.9 5.9l2.1 2.1M18 18l2.1 2.1M5.9 20.1 8 18M18 8l2.1-2.1" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
};
const TAB_LABELS = { home: "Home", activity: "Activity", plan: "Plan", insights: "Insights", settings: "Settings" };

function ctx() {
  return { data: store.get(), today: D.today() };
}

// ---- Rendering -----------------------------------------------------------------

function render({ keepScroll = true } = {}) {
  const data = store.get();
  const tabbar = document.querySelector(".tabbar");
  if (!data.settings.onboarded) {
    app.innerHTML = Settings.onboarding();
    tabbar.hidden = true;
    return;
  }
  tabbar.hidden = false;
  // Keep focus and cursor position (e.g. while typing in search).
  const active = document.activeElement;
  const focusId = active && app.contains(active) ? active.id : null;
  const selection = focusId && active.selectionStart != null ? [active.selectionStart, active.selectionEnd] : null;
  const y = window.scrollY;
  const view = VIEWS[ui.tab] || Home;
  app.innerHTML = view.render(ctx());
  if (keepScroll) window.scrollTo(0, y);
  else window.scrollTo(0, 0);
  if (focusId) {
    const el = document.getElementById(focusId);
    el?.focus({ preventScroll: true });
    if (selection && el?.setSelectionRange) try { el.setSelectionRange(...selection); } catch {}
  }
  tabbar.querySelectorAll("button").forEach((b) => {
    const on = b.dataset.tab === ui.tab;
    b.classList.toggle("on", on);
    b.setAttribute("aria-current", on ? "page" : "false");
  });
}

function renderTabbar() {
  const bar = document.createElement("nav");
  bar.className = "tabbar";
  bar.setAttribute("aria-label", "Main");
  bar.innerHTML = `<div class="tabbar-inner">${Object.keys(TAB_LABELS).map((t) =>
    `<button data-tab="${t}"><svg viewBox="0 0 26 26" aria-hidden="true">${ICONS[t]}</svg>${TAB_LABELS[t]}</button>`).join("")}</div>`;
  bar.addEventListener("click", (e) => {
    const b = e.target.closest("button[data-tab]");
    if (!b) return;
    if (ui.tab === b.dataset.tab) {
      window.scrollTo({ top: 0, behavior: "smooth" });
      return;
    }
    go(b.dataset.tab);
  });
  document.body.append(bar);
}

function go(tab, extra = {}) {
  Object.assign(ui, { tab }, extra);
  remember();
  render({ keepScroll: false });
}

// ---- Actions -------------------------------------------------------------------

const findTx = (id) => store.get().transactions.find((t) => t.id === id);

const actions = {
  addExpense: () => F.transactionForm(null, "expense"),
  addIncome: () => F.transactionForm(null, "income"),
  editTx: (el) => { const t = findTx(el.dataset.id); if (t) F.transactionForm(t); },

  goPlan: (el) => go("plan", { planPage: el.dataset.page }),
  goInsights: () => go("insights", { insightsPage: "spending" }),
  planPage: (el) => { ui.planPage = el.dataset.page; remember(); render(); },
  insightsPage: (el) => { ui.insightsPage = el.dataset.page; remember(); render(); },

  addBudget: () => F.budgetForm(null),
  editBudget: (el) => F.budgetForm(store.get().budgets.find((b) => b.id === el.dataset.id)),
  addBill: () => F.billForm(null),
  editBill: (el) => F.billForm(store.get().bills.find((b) => b.id === el.dataset.id)),
  payBill: (el) => { F.markPaid(el.dataset.id); navigator.vibrate?.(15); },
  addGoal: () => F.goalForm(null),
  openGoal: (el) => F.goalDetail(el.dataset.id),
  editPay: () => F.payForm(),
  editOpening: () => F.openingBalanceForm(),
  recordPay: () => {
    const pay = store.get().settings.pay;
    if (!pay) return;
    store.update((d) => d.transactions.push({ id: uid(), kind: "income", amount: pay.amount, category: pay.category, date: D.today(), note: "Pay", sample: false, billId: null }));
    toast("Pay added as income");
  },

  // Activity
  kindFilter: (el) => { ui.kindFilter = el.dataset.value; ui.activityLimit = 60; render(); },
  clearFilters: () => { Object.assign(ui, { kindFilter: "all", categoryFilter: "", monthFilter: "", search: "", activityLimit: 60 }); render(); },
  moreActivity: () => { ui.activityLimit = (ui.activityLimit || 60) + 60; render(); },
  exportFiltered: () => shareFile(`Budget Planner Transactions ${fileDate()}.csv`, transactionsToCSV(Activity.filtered(store.get())), "text/csv"),

  // Insights
  spendPeriod: (el) => { ui.spendPeriod = el.dataset.value; ui.spendOffset = 0; render(); },
  spendShift: (el) => { ui.spendOffset = Math.min(0, ui.spendOffset + Number(el.dataset.value)); render(); },
  categoryDetail: (el) => {
    const range = Insights.spendRange(D.today());
    F.categorySheet(el.dataset.id, range, Insights.rangeLabel(range, ui.spendPeriod));
  },
  reportPeriod: (el) => { ui.reportPeriod = el.dataset.value; render(); },
  whatIfPreset: (el) => {
    const [, change] = Insights.whatIfPresets(store.get(), D.today())[Number(el.dataset.value)];
    Object.assign(ui.whatIf, change);
    render();
  },
  whatIfReset: () => { ui.whatIf = Insights.whatIfDefaults(store.get(), D.today()); render(); },

  // Data
  exportCSV: () => shareFile(`Budget Planner Transactions ${fileDate()}.csv`, transactionsToCSV(store.get().transactions), "text/csv"),
  backup: () => shareFile(`Budget Planner Backup ${fileDate()}.json`, JSON.stringify(store.get(), null, 2), "application/json"),
  restore: async () => {
    const text = await pickFile(".json,application/json");
    if (text === null) return;
    let next;
    try {
      next = validateData(JSON.parse(text));
    } catch (err) {
      alert(err instanceof SyntaxError ? "This file isn't a Budget Planner backup." : err.message);
      return;
    }
    if (!confirm("Replace everything in the app with this backup? Consider making a backup of your current data first.")) return;
    next.settings.onboarded = true;
    store.replace(next);
    toast("Backup restored");
  },
  importCSV: async () => {
    const text = await pickFile(".csv,text/csv,text/plain");
    if (text === null) return;
    try {
      const { transactions, skipped } = transactionsFromCSV(text);
      store.update((d) => d.transactions.push(...transactions));
      alert(`Imported ${transactions.length} transactions.${skipped.length ? ` ${skipped.length} rows couldn't be read and were skipped (rows ${skipped.slice(0, 10).join(", ")}${skipped.length > 10 ? "…" : ""}).` : ""}`);
    } catch (err) {
      alert(err.message);
    }
  },
  exportCalendar: () => {
    const bills = store.get().bills.filter((b) => b.active);
    if (!bills.length) return alert("Add a bill first.");
    shareFile("Bill reminders.ics", billsToICS(bills), "text/calendar");
  },
  loadSample: () => {
    loadSample();
    toast("Sample data added");
  },
  removeSample: () => {
    if (!confirm("Remove all sample data? Anything you've entered yourself is kept.")) return;
    store.update(removeSampleData);
    toast("Sample data removed");
  },
  eraseAll: () => {
    if (!confirm("Erase all data? This deletes every transaction, bill, budget and goal from this device. It can't be undone.")) return;
    ui.whatIf = null;
    ui.tab = "home";
    remember();
    store.replace(emptyData());
  },
  hideInstallHint: () => { ui.hideInstallHint = true; remember(); render(); },

  // Onboarding
  startSample: () => {
    loadSample();
    store.update((d) => (d.settings.onboarded = true));
    go("home");
  },
  startFresh: () => {
    openSheet({
      title: "Welcome",
      save: "Start",
      body: `<div class="form-label" style="margin-top:4px">How much money do you have right now?</div>
        <div class="amount-input"><span>$</span><input name="amount" inputmode="decimal" placeholder="0.00" aria-label="Current balance"></div>
        <div class="form-error"></div>
        <div class="form-hint">Add up your everyday accounts. You can leave this blank and change it later in Settings.</div>`,
      onMount: (form) => setTimeout(() => form.elements.amount.focus(), 320),
      onSave(form) {
        const text = form.elements.amount.value;
        if (text && amountProblem(text, { allowZero: true })) return showError(form, amountProblem(text, { allowZero: true }));
        store.update((d) => {
          d.settings.openingBalance = text ? parseMoney(text) : 0;
          d.settings.onboarded = true;
        });
        go("home");
      },
    });
  },
};

function loadSample() {
  const sample = sampleData(D.today());
  store.update((d) => {
    removeSampleData(d);
    d.transactions.push(...sample.transactions);
    d.bills.push(...sample.bills);
    d.budgets.push(...sample.budgets);
    d.goals.push(...sample.goals);
    if (!d.settings.openingBalance) Object.assign(d.settings, { openingBalance: sample.settings.openingBalance, openingSample: true });
    if (!d.settings.pay) Object.assign(d.settings, { pay: sample.settings.pay, savingsPerPay: sample.settings.savingsPerPay, paySample: true });
  });
}

// ---- Events --------------------------------------------------------------------

document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-action]");
  if (!el || el.disabled) return;
  const fn = actions[el.dataset.action];
  if (fn) {
    e.preventDefault();
    fn(el, e);
  }
});

document.addEventListener("change", (e) => {
  const el = e.target.closest("[data-change]");
  if (!el) return;
  switch (el.dataset.change) {
    case "monthFilter": ui.monthFilter = el.value; ui.activityLimit = 60; break;
    case "categoryFilter": ui.categoryFilter = el.value; ui.activityLimit = 60; break;
    case "whatIfDir": ui.whatIf[el.dataset.key] = el.value === "up"; break;
    case "whatIfMonths": ui.whatIf.months = Number(el.value); break;
  }
  render();
});

document.addEventListener("input", (e) => {
  const el = e.target.closest("[data-input]");
  if (!el) return;
  if (el.dataset.input === "search") {
    ui.search = el.value;
    ui.activityLimit = 60;
    render();
  } else if (el.dataset.input === "whatIf") {
    ui.whatIf[el.dataset.key] = el.value;
    const results = document.getElementById("whatif-results");
    if (results) results.innerHTML = Insights.whatIfResults(ctx());
  }
});

// Redraw when coming back to the app (the date may have changed).
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && !document.querySelector(".sheet")) render();
});

// ---- Start ---------------------------------------------------------------------

store.load();
store.onChange(() => render());
renderTabbar();
render({ keepScroll: false });
const err = store.takeLoadError();
if (err) alert(err);

if ("serviceWorker" in navigator && location.protocol === "https:") {
  navigator.serviceWorker.register("sw.js").catch(() => {});
}
