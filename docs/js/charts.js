// Minimal SVG charts – no libraries, so everything works offline.

import { esc } from "./ui.js";
import { money0 } from "./money.js";

/** Donut chart of [{ amount, color, label }]. */
export function donut(items, { size = 200, thickness = 0.36, center = "" } = {}) {
  const total = items.reduce((t, x) => t + x.amount, 0);
  const r = 50;
  const inner = r * (1 - thickness);
  let angle = -Math.PI / 2;
  const gap = items.length > 1 ? 0.02 : 0;
  const paths = items.map((x) => {
    const sweep = (x.amount / total) * Math.PI * 2;
    const a0 = angle + gap / 2;
    const a1 = angle + sweep - gap / 2;
    angle += sweep;
    if (sweep >= Math.PI * 2 - 0.0001) {
      return `<circle cx="50" cy="50" r="${(r + inner) / 2}" fill="none" stroke="${x.color}" stroke-width="${r - inner}"><title>${esc(x.label)}</title></circle>`;
    }
    if (a1 <= a0) return "";
    const large = a1 - a0 > Math.PI ? 1 : 0;
    const p = (rad, a) => `${50 + rad * Math.cos(a)} ${50 + rad * Math.sin(a)}`;
    return `<path d="M ${p(r, a0)} A ${r} ${r} 0 ${large} 1 ${p(r, a1)} L ${p(inner, a1)} A ${inner} ${inner} 0 ${large} 0 ${p(inner, a0)} Z" fill="${x.color}"><title>${esc(x.label)}</title></path>`;
  });
  return `<div class="donut-wrap" style="width:${size}px;height:${size}px;margin:0 auto">
    <svg viewBox="0 0 100 100" width="${size}" height="${size}" role="img" aria-label="Spending by category">${paths.join("")}</svg>
    <div class="donut-center">${center}</div></div>`;
}

function niceMax(v) {
  if (v <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(v)));
  const n = v / exp;
  const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return step * exp;
}

/** Vertical bar chart. series = [{ color, values: [cents] }], labels = [string]. */
export function bars(labels, series, { height = 180, average = null, labelEvery = 1 } = {}) {
  const W = 340;
  const H = height;
  const left = 40;
  const bottom = 18;
  const top = 8;
  const max = niceMax(Math.max(1, ...series.flatMap((s) => s.values), average || 0));
  const plotW = W - left - 4;
  const plotH = H - bottom - top;
  const groupW = plotW / labels.length;
  const barW = Math.max(2, Math.min(28, (groupW * 0.7) / series.length));
  const y = (v) => top + plotH - (v / max) * plotH;
  let svg = "";
  for (let i = 0; i <= 4; i++) {
    const v = (max / 4) * i;
    svg += `<line class="grid" x1="${left}" x2="${W}" y1="${y(v)}" y2="${y(v)}"/>`;
    svg += `<text x="${left - 4}" y="${y(v) + 3}" text-anchor="end">${money0(v)}</text>`;
  }
  labels.forEach((label, i) => {
    const gx = left + groupW * i + groupW / 2;
    const totalW = barW * series.length + (series.length - 1) * 2;
    series.forEach((s, j) => {
      const v = s.values[i] || 0;
      const h = (v / max) * plotH;
      const x = gx - totalW / 2 + j * (barW + 2);
      if (h > 0) svg += `<rect x="${x}" y="${y(v)}" width="${barW}" height="${h}" rx="${Math.min(3, barW / 2)}" fill="${s.color}"><title>${esc(label)}: ${money0(v)}</title></rect>`;
    });
    if (i % labelEvery === 0) svg += `<text x="${gx}" y="${H - 4}" text-anchor="middle">${esc(label)}</text>`;
  });
  if (average !== null && average > 0) {
    svg += `<line x1="${left}" x2="${W}" y1="${y(average)}" y2="${y(average)}" stroke="currentColor" stroke-dasharray="4 4" opacity="0.5"/>`;
    svg += `<text x="${W}" y="${y(average) - 4}" text-anchor="end">avg ${money0(average)}</text>`;
  }
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Bar chart">${svg}</svg>`;
}

/** Line chart. series = [{ color, values, dashed, label }], x labels by index. */
export function lines(series, { height = 200, xLabel = (i) => i } = {}) {
  const W = 340;
  const H = height;
  const left = 46;
  const bottom = 18;
  const top = 8;
  const all = series.flatMap((s) => s.values);
  let min = Math.min(0, ...all);
  let max = Math.max(1, ...all);
  max = niceMax(max);
  if (min < 0) min = -niceMax(-min);
  const n = series[0].values.length;
  const plotW = W - left - 6;
  const plotH = H - bottom - top;
  const x = (i) => left + (n <= 1 ? 0 : (i / (n - 1)) * plotW);
  const y = (v) => top + plotH - ((v - min) / (max - min)) * plotH;
  let svg = "";
  for (let i = 0; i <= 4; i++) {
    const v = min + ((max - min) / 4) * i;
    svg += `<line class="grid" x1="${left}" x2="${W}" y1="${y(v)}" y2="${y(v)}"/>`;
    svg += `<text x="${left - 4}" y="${y(v) + 3}" text-anchor="end">${money0(v)}</text>`;
  }
  if (min < 0) svg += `<line x1="${left}" x2="${W}" y1="${y(0)}" y2="${y(0)}" stroke="currentColor" opacity="0.4"/>`;
  const step = Math.max(1, Math.ceil(n / 7));
  for (let i = 0; i < n; i += step) svg += `<text x="${x(i)}" y="${H - 4}" text-anchor="middle">${esc(xLabel(i))}</text>`;
  for (const s of series) {
    const d = s.values.map((v, i) => `${i ? "L" : "M"} ${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
    svg += `<path d="${d}" fill="none" stroke="${s.color}" stroke-width="${s.dashed ? 2 : 3}" stroke-linecap="round" stroke-linejoin="round" ${s.dashed ? 'stroke-dasharray="5 4"' : ""}/>`;
  }
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Line chart">${svg}</svg>`;
}

/** Circular progress ring. */
export function ring(fraction, { size = 46, stroke = 5, color = "var(--accent)", inner = "" } = {}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const f = Math.max(0, Math.min(1, fraction));
  return `<div class="ring" style="width:${size}px;height:${size}px">
    <svg width="${size}" height="${size}" style="position:absolute;inset:0">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="var(--fill)" stroke-width="${stroke}"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${c * f} ${c}"/>
    </svg><div style="position:relative">${inner}</div></div>`;
}
