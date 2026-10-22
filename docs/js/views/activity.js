import * as D from "../dates.js";
import { CATEGORIES, cat } from "../categories.js";
import { money, money0, signedMoney } from "../money.js";
import { hasSampleData } from "../data.js";
import { esc, txRow, stat } from "../ui.js";
import { ui } from "../state.js";
import { sampleBanner } from "./home.js";

export function filtered(data) {
  const q = ui.search.trim().toLowerCase();
  return data.transactions
    .filter((t) => {
      if (ui.kindFilter === "expense" && t.kind !== "expense") return false;
      if (ui.kindFilter === "income" && t.kind !== "income") return false;
      if (ui.categoryFilter && t.category !== ui.categoryFilter) return false;
      if (ui.monthFilter && !t.date.startsWith(ui.monthFilter)) return false;
      if (!q) return true;
      return t.note.toLowerCase().includes(q) || cat(t.category).name.toLowerCase().includes(q) ||
        money(t.amount).includes(q) || (t.amount / 100).toFixed(2).includes(q) || D.fmtDMY(t.date).includes(q);
    })
    .sort((a, b) => (a.date === b.date ? 0 : a.date < b.date ? 1 : -1));
}

export const isFiltered = () => ui.kindFilter !== "all" || ui.categoryFilter || ui.monthFilter || ui.search;

export function render({ data, today }) {
  const items = filtered(data);
  const months = [...new Set(data.transactions.map((t) => t.date.slice(0, 7)))].sort().reverse();
  const groups = [];
  for (const t of items) {
    const last = groups[groups.length - 1];
    if (last && last.date === t.date) last.items.push(t);
    else groups.push({ date: t.date, items: [t] });
  }
  const income = items.filter((t) => t.kind === "income").reduce((s, t) => s + t.amount, 0);
  const spent = items.filter((t) => t.kind === "expense").reduce((s, t) => s + t.amount, 0);
  // Long lists are drawn in pages so the screen stays fast.
  const shown = groups.slice(0, ui.activityLimit || 60);

  return `<div class="screen">
    <div class="large-title">Activity
      <span class="row" style="gap:4px">
        <button class="icon-btn" style="font-size:22px" data-action="exportFiltered" aria-label="Export as CSV" ${items.length ? "" : "disabled"}>⇪</button>
        <button class="icon-btn" data-action="addExpense" aria-label="Add transaction">⊕</button>
      </span></div>
    <label class="search"><span class="muted">🔍</span><input id="search" type="search" placeholder="Search notes, categories or amounts" value="${esc(ui.search)}" data-input="search" autocomplete="off" enterkeyhint="search"></label>
    <div class="chips" style="margin-bottom:12px">
      ${["all", "expense", "income"].map((k) => `<button class="chip ${ui.kindFilter === k ? "on" : ""}" data-action="kindFilter" data-value="${k}">${{ all: "All", expense: "Spending", income: "Income" }[k]}</button>`).join("")}
      <select class="chip ${ui.monthFilter ? "on" : ""}" data-change="monthFilter" aria-label="Month">
        <option value="">All months</option>
        ${months.map((m) => `<option value="${m}" ${ui.monthFilter === m ? "selected" : ""}>${D.fmtMonthYear(m + "-01")}</option>`).join("")}
      </select>
      <select class="chip ${ui.categoryFilter ? "on" : ""}" data-change="categoryFilter" aria-label="Category">
        <option value="">All categories</option>
        ${Object.keys(CATEGORIES).map((id) => `<option value="${id}" ${ui.categoryFilter === id ? "selected" : ""}>${cat(id).icon} ${esc(cat(id).name)}</option>`).join("")}
      </select>
      ${isFiltered() ? `<button class="chip" data-action="clearFilters">✕ Clear</button>` : ""}
    </div>
    <div class="stack">
      ${hasSampleData(data) && !isFiltered() ? sampleBanner() : ""}
      ${items.length ? `<div class="card"><div class="stats">${stat("Money in", money0(income), "good")}${stat("Money out", money0(spent))}${stat("Difference", money0(income - spent), income - spent < 0 ? "bad" : "")}</div>
        <div class="tiny muted" style="margin-top:8px">${items.length} ${items.length === 1 ? "transaction" : "transactions"}</div></div>` : ""}
    </div>
    ${shown.map((g) => {
      const net = g.items.reduce((s, t) => s + (t.kind === "income" ? t.amount : -t.amount), 0);
      return `<div class="section-label"><span>${D.fmtDayHeader(g.date, today)}</span><span class="num">${signedMoney(net)}</span></div>
        <div class="list">${g.items.map((t) => txRow(t)).join("")}</div>`;
    }).join("")}
    ${groups.length > shown.length ? `<div style="margin-top:16px"><button class="btn secondary" data-action="moreActivity">Show more</button></div>` : ""}
    ${items.length ? "" : data.transactions.length
      ? `<div class="empty"><div class="icon">🔍</div><div class="title">Nothing matches</div><div>Try a different search or clear the filters.</div></div>`
      : `<div class="empty"><div class="icon">🧾</div><div class="title">No transactions yet</div><div>Add your income and spending to see where your money goes.</div>
          <button class="btn small" data-action="addExpense">Add an expense</button></div>`}
  </div>`;
}
