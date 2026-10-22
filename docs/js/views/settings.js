import { money0, money } from "../money.js";
import { hasSampleData } from "../data.js";
import * as D from "../dates.js";

export function render({ data }) {
  const s = data.settings;
  const row = (action, icon, title, sub = "", value = "", cls = "chevron") => `
    <button class="list-row ${cls}" data-action="${action}">
      <span class="cat-icon sm" style="background:var(--fill)">${icon}</span>
      <div class="grow">${title}${sub ? `<div class="tiny muted">${sub}</div>` : ""}</div>
      ${value ? `<span class="muted num">${value}</span>` : ""}
    </button>`;
  return `<div class="screen">
    <div class="large-title">Settings</div>

    <div class="section-label"><span>Money</span></div>
    <div class="list">
      ${row("editOpening", "🏦", `Starting balance${s.openingSample ? ' <span class="badge">SAMPLE</span>' : ""}`, "", money(s.openingBalance))}
      ${row("editPay", "💵", "Payday", "", s.pay ? `${money0(s.pay.amount)} ${D.FREQUENCIES[s.pay.frequency].label.toLowerCase()}` : "Not set")}
    </div>
    <div class="section-foot">Starting balance is what you had in your everyday accounts when you began. Your available balance adds income and subtracts spending from there.</div>

    <div class="section-label"><span>Backup &amp; export</span></div>
    <div class="list">
      ${row("exportCSV", "📄", "Export transactions (CSV)", "Opens in Excel, Numbers or Google Sheets")}
      ${row("backup", "💾", "Back up all data", "Save the file to Files or iCloud Drive")}
      ${row("restore", "♻️", "Restore from backup", "Replaces everything in the app")}
      ${row("importCSV", "📥", "Import transactions (CSV)", "Columns: Date (dd/mm/yyyy), Description, Amount")}
      ${row("exportCalendar", "🔔", "Add bill reminders to Calendar", "Uses your phone's Calendar alerts")}
    </div>
    <div class="section-foot">Your data is stored only in this browser on this phone. Back up regularly – if you delete the app or clear Safari's website data, it's gone. For CSV imports, negative amounts are treated as spending.</div>

    <div class="section-label"><span>Sample data</span></div>
    <div class="list">
      ${hasSampleData(data)
        ? row("removeSample", "🧪", '<span class="bad">Remove sample data</span>', "Keeps everything you've entered", "", "")
        : row("loadSample", "🧪", "Load sample data", "Clearly marked and easy to remove", "", "")}
      ${row("eraseAll", "🗑️", '<span class="bad">Erase all data</span>', "", "", "")}
    </div>

    <div class="section-label"><span>Privacy</span></div>
    <div class="card small muted">
      🔒 No accounts, no bank logins, no ads and no tracking. Everything you enter stays on this device – this app has no server and never sends your data anywhere. Anyone who can unlock your phone can open it, so keep your phone locked with a passcode or Face ID.
    </div>

    <div class="section-label"><span>About</span></div>
    <div class="list plain">
      <div class="list-row"><div class="grow">Currency</div><span class="muted">Australian dollars (AUD)</span></div>
      <div class="list-row"><div class="grow">Date format</div><span class="muted">dd/mm/yyyy</span></div>
      <div class="list-row"><div class="grow">Weeks start on</div><span class="muted">Monday</span></div>
      <div class="list-row"><div class="grow">Version</div><span class="muted">1.0</span></div>
    </div>
  </div>`;
}

export function onboarding() {
  const feature = (icon, title, text) => `<div class="row top"><div style="font-size:28px;width:40px;text-align:center">${icon}</div>
    <div><div class="bold">${title}</div><div class="small muted">${text}</div></div></div>`;
  return `<div class="screen" style="padding-bottom:40px">
    <div style="padding-top:28px">
      <img src="icons/icon-192.png" width="72" height="72" alt="" style="border-radius:16px">
      <div class="large-title" style="margin-top:12px">Budget Planner</div>
      <div class="muted" style="font-size:19px">A simple way to see what you have, where it goes, and how much you can save.</div>
    </div>
    <div class="stack" style="margin:28px 0">
      ${feature("💵", "Know what's available", "See your balance and what's safe to spend until payday.")}
      ${feature("🥧", "See where it goes", "Clear charts and practical ideas to spend less.")}
      ${feature("📅", "Stay ahead of bills", "Know what's due before each payday, with Calendar reminders.")}
      ${feature("🎯", "Save with a plan", "Goals that tell you how much to put aside each week.")}
      ${feature("🔒", "Private by design", "Everything stays on your phone. No bank logins, no accounts.")}
    </div>
    <div id="onboard-actions" class="stack">
      <button class="btn" data-action="startFresh">Start with my own data</button>
      <button class="btn secondary" data-action="startSample">Explore with sample data</button>
      <div class="small muted center">Sample data is clearly marked and can be removed at any time.</div>
    </div>
  </div>`;
}
