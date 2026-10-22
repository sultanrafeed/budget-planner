// Saves data in this browser only (localStorage). Nothing is sent anywhere.

import { emptyData, validateData } from "./data.js";

const KEY = "budgetPlanner.v1";
const listeners = new Set();
let data = null;
let loadError = null;

export function load() {
  try {
    const raw = localStorage.getItem(KEY);
    data = raw ? validateData(JSON.parse(raw)) : emptyData();
  } catch (err) {
    // Keep the unreadable copy so nothing is lost.
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) localStorage.setItem(`${KEY}.unreadable.${Date.now()}`, raw);
    } catch {}
    data = emptyData();
    loadError = "Your saved data couldn't be read, so the app started fresh. A copy was kept. You can restore a backup from Settings.";
  }
  // Ask the browser not to clear our data when space is low.
  navigator.storage?.persist?.().catch(() => {});
  return data;
}

export const get = () => data;
export const takeLoadError = () => {
  const e = loadError;
  loadError = null;
  return e;
};

/** Applies a change, saves it, and redraws the screen. */
export function update(change) {
  change(data);
  save();
  listeners.forEach((fn) => fn(data));
}

export function replace(next) {
  data = next;
  save();
  listeners.forEach((fn) => fn(data));
}

function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch (err) {
    alert("Couldn't save your changes – your browser storage may be full or turned off (Private Browsing). Please make a backup from Settings.");
  }
}

export function onChange(fn) {
  listeners.add(fn);
}
