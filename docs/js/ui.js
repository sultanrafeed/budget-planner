// Small UI helpers: escaping, sheets, toasts, sharing files.

import { cat } from "./categories.js";
import { money } from "./money.js";
import * as D from "./dates.js";

/** Escapes text for safe use inside HTML. */
export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

export const sampleBadge = (on) => (on ? ` <span class="badge">SAMPLE</span>` : "");

export function catIcon(id, size = "") {
  const c = cat(id);
  return `<span class="cat-icon ${size}" style="background:${c.color}22" aria-hidden="true">${c.icon}</span>`;
}

export function progress(value, state = "", marker = null, thin = false) {
  const w = Math.max(0, Math.min(1, value)) * 100;
  const m = marker === null ? "" : `<span class="marker" style="left:calc(${Math.min(1, Math.max(0, marker)) * 100}% - 1px)"></span>`;
  return `<div class="progress ${thin ? "thin" : ""}" role="progressbar" aria-valuenow="${Math.round(value * 100)}" aria-valuemin="0" aria-valuemax="100"><div class="fill ${state}" style="width:${w}%"></div>${m}</div>`;
}

export function stat(label, value, cls = "") {
  return `<div class="stat"><div class="label">${esc(label)}</div><div class="value ${cls}">${value}</div></div>`;
}

export function txRow(t, { showDate = false, today } = {}) {
  const c = cat(t.category);
  const amount = (t.kind === "income" ? "+" : "-") + money(t.amount);
  const sub = showDate ? `${esc(c.name)} · ${D.fmtDayMonth(t.date)}` : esc(c.name);
  return `<button class="list-row" data-action="editTx" data-id="${esc(t.id)}">
    ${catIcon(t.category)}
    <div class="grow"><div class="ellipsis">${esc(t.note || c.name)}${sampleBadge(t.sample)}</div><div class="small muted">${sub}</div></div>
    <div class="num ${t.kind === "income" ? "good" : ""}" style="font-weight:500">${amount}</div>
  </button>`;
}

// ---- Sheets ------------------------------------------------------------------

let sheetCleanup = null;

/** Opens a bottom sheet. `onMount(el)` runs after it is in the page. */
export function openSheet({ title, body, save = "Save", onSave, onMount, cancel = "Cancel" }) {
  closeSheet(true);
  const backdrop = document.createElement("div");
  backdrop.className = "sheet-backdrop";
  const sheet = document.createElement("div");
  sheet.className = "sheet";
  sheet.setAttribute("role", "dialog");
  sheet.setAttribute("aria-modal", "true");
  sheet.setAttribute("aria-label", title);
  sheet.innerHTML = `
    <div class="sheet-head">
      <div class="left"><button type="button" data-sheet="cancel">${esc(cancel)}</button></div>
      <div class="center ellipsis">${esc(title)}</div>
      <div class="right">${onSave ? `<button type="button" data-sheet="save">${esc(save)}</button>` : ""}</div>
    </div>
    <form class="sheet-body" novalidate>${body}<button type="submit" hidden></button></form>`;
  document.body.append(backdrop, sheet);
  document.body.style.overflow = "hidden";
  requestAnimationFrame(() => {
    backdrop.classList.add("open");
    sheet.classList.add("open");
  });
  const form = sheet.querySelector("form");
  const trySave = () => {
    if (!onSave) return;
    const ok = onSave(form);
    if (ok !== false) closeSheet();
  };
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    trySave();
  });
  sheet.querySelector('[data-sheet="cancel"]').addEventListener("click", () => closeSheet());
  sheet.querySelector('[data-sheet="save"]')?.addEventListener("click", trySave);
  backdrop.addEventListener("click", () => closeSheet());
  const onKey = (e) => e.key === "Escape" && closeSheet();
  document.addEventListener("keydown", onKey);
  sheetCleanup = () => {
    document.removeEventListener("keydown", onKey);
    backdrop.classList.remove("open");
    sheet.classList.remove("open");
    document.body.style.overflow = "";
    setTimeout(() => {
      backdrop.remove();
      sheet.remove();
    }, 300);
  };
  onMount?.(form);
  return form;
}

export function closeSheet(immediate = false) {
  if (!sheetCleanup) return;
  const fn = sheetCleanup;
  sheetCleanup = null;
  fn(immediate);
}

export function showError(form, message) {
  const el = form.querySelector(".form-error");
  if (el) {
    el.textContent = message;
    el.scrollIntoView({ block: "nearest", behavior: "smooth" });
  } else alert(message);
  navigator.vibrate?.(30);
  return false;
}

// ---- Toast -------------------------------------------------------------------

let toastTimer = null;

export function toast(message, action) {
  document.querySelector(".toast")?.remove();
  clearTimeout(toastTimer);
  const el = document.createElement("div");
  el.className = "toast";
  el.setAttribute("role", "status");
  el.innerHTML = `<span>${esc(message)}</span>${action ? `<button type="button">${esc(action.label)}</button>` : ""}`;
  document.body.append(el);
  if (action) {
    el.querySelector("button").addEventListener("click", () => {
      action.run();
      el.remove();
    });
  }
  requestAnimationFrame(() => el.classList.add("show"));
  toastTimer = setTimeout(() => {
    el.classList.remove("show");
    setTimeout(() => el.remove(), 250);
  }, action ? 5000 : 2500);
}

// ---- Files -------------------------------------------------------------------

/** Shares a file (iPhone share sheet → Save to Files, AirDrop…) or downloads it. */
export async function shareFile(name, text, type) {
  const file = new File([text], name, { type });
  try {
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], title: name });
      return;
    }
  } catch (err) {
    if (err?.name === "AbortError") return;
  }
  const url = URL.createObjectURL(file);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

export function pickFile(accept) {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.addEventListener("change", async () => {
      const file = input.files?.[0];
      resolve(file ? await file.text() : null);
    });
    input.click();
  });
}

export function fileDate() {
  return D.fmtDMY(D.today()).replace(/\//g, "-");
}
