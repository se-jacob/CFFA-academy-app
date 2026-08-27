import * as XLSX from "xlsx";
import { writeFileSync } from "fs";

const wb = XLSX.utils.book_new();

function addSheet(name, headers, notes, exampleRows) {
  const rows = [headers, ...exampleRows];
  const ws = XLSX.utils.aoa_to_sheet(rows);
  ws["!cols"] = headers.map((h) => ({ wch: Math.max(h.length + 2, 18) }));
  XLSX.utils.book_append_sheet(wb, ws, name);
  if (notes.length) {
    const notesWs = XLSX.utils.aoa_to_sheet([["Column", "Notes"], ...notes]);
    notesWs["!cols"] = [{ wch: 22 }, { wch: 90 }];
    XLSX.utils.book_append_sheet(wb, notesWs, name + " Notes");
  }
}

addSheet(
  "1 Locations",
  ["name", "address", "contact", "admin_name", "admin_user_id"],
  [
    ["name", "Location name shown throughout the app. Required."],
    ["address", "Street/area, city. Optional."],
    ["contact", "Phone number for this location. Optional."],
    ["admin_name", "Display name of the location's admin-in-charge (free text label only, not a login). Optional."],
    ["admin_user_id", "Only fill this in if you already know the actual login account (UUID from admin_profiles) to link as this location's admin — this is different from admin_name above, which is just a display label. Leave blank if you don't have this yet; admins are normally linked via Manage Admins > Invite Admin in the app instead."],
  ],
  [
    ["Downtown Arena", "12 Sheikh Zayed Road, Dubai", "+971 50 111 2233", "Farah Khan", ""],
    ["Marina Sports Hub", "Marina Walk, Dubai", "+971 50 444 5566", "Imran Sheikh", ""],
  ]
);

addSheet(
  "2 Payment Plans",
  ["location_name", "name", "gender", "duration", "sessions_count", "amount"],
  [
    ["location_name", "Must exactly match a \"name\" from the Locations sheet."],
    ["name", "Plan name, e.g. \"Monthly - Any\". Required."],
    ["gender", "One of: Any, Male, Female."],
    ["duration", "One of: Monthly, Quarterly, 4 Months, Fixed Sessions."],
    ["sessions_count", "Only fill this in if duration = Fixed Sessions. Leave blank otherwise."],
    ["amount", "Fee amount as a plain number (no currency symbol), e.g. 450."],
  ],
  [
    ["Downtown Arena", "Monthly - Any", "Any", "Monthly", "", 450],
    ["Downtown Arena", "Quarterly - Any", "Any", "Quarterly", "", 1200],
    ["Marina Sports Hub", "10 Session Pack", "Any", "Fixed Sessions", 10, 800],
  ]
);

addSheet(
  "3 Batches",
  ["location_name", "batch_code", "name"],
  [
    ["location_name", "Must exactly match a \"name\" from the Locations sheet."],
    ["batch_code", "Short internal code, e.g. \"DA-U12\". Optional."],
    ["name", "Batch name shown in the app, e.g. \"Under 12 Football\". Required."],
  ],
  [
    ["Downtown Arena", "DA-U12", "Under 12 Football"],
    ["Marina Sports Hub", "MSH-SWM", "Marina Swim Squad"],
  ]
);

addSheet(
  "4 Coaches",
  ["name", "phone", "email", "specialty", "location_names"],
  [
    ["name", "Required."],
    ["phone", "Optional."],
    ["email", "Optional."],
    ["specialty", "e.g. Football, Swimming. Optional."],
    ["location_names", "One or more locations this coach works at, separated by semicolons (;) — must exactly match \"name\" values from the Locations sheet, e.g. \"Downtown Arena;Marina Sports Hub\"."],
  ],
  [
    ["Marcus Webb", "+971 55 222 1010", "marcus.webb@academy.com", "Football", "Downtown Arena"],
    ["Daniel Osei", "+971 55 222 3030", "daniel.osei@academy.com", "Swimming", "Marina Sports Hub"],
  ]
);

addSheet(
  "5 Players",
  [
    "name", "phone", "email", "dob", "location_name", "batch_name",
    "jersey_name", "jersey_no", "attendance_days", "sessions_payment_plan_name",
    "override_fee", "status", "remark",
  ],
  [
    ["name", "Required."],
    ["phone", "Optional."],
    ["email", "Optional."],
    ["dob", "Date of birth, format YYYY-MM-DD, e.g. 2013-04-12. Optional."],
    ["location_name", "Must exactly match a \"name\" from the Locations sheet. Required."],
    ["batch_name", "Must exactly match a \"name\" from the Batches sheet AND belong to the same location. Optional."],
    ["jersey_name", "Printed on jersey, e.g. AARAV. Optional."],
    ["jersey_no", "Jersey number. Optional."],
    ["attendance_days", "Days this player trains, separated by commas, using: Mon,Tue,Wed,Thu,Fri,Sat,Sun. e.g. \"Mon,Wed,Fri\". Sessions/Week is calculated automatically from this."],
    ["sessions_payment_plan_name", "Must exactly match a \"name\" from the Payment Plans sheet AND belong to the same location. Optional."],
    ["override_fee", "Only fill in if this player pays a custom amount instead of the plan's fee. Leave blank otherwise."],
    ["status", "Active or Inactive."],
    ["remark", "Free-text note, max 150 characters. Optional."],
  ],
  [
    ["Aarav Mehta", "+971 50 900 1111", "aarav@example.com", "2013-04-12", "Downtown Arena", "Under 12 Football", "AARAV", "7", "Mon,Wed,Fri", "Monthly - Any", "", "Active", ""],
    ["Fatima Noor", "+971 50 900 4444", "fatima@example.com", "2014-06-30", "Marina Sports Hub", "Marina Swim Squad", "FATIMA", "21", "Tue,Thu,Sat,Sun", "10 Session Pack", "", "Active", ""],
  ]
);

// Read-me sheet first
const readme = XLSX.utils.aoa_to_sheet([
  ["CFFA Academy — Mass Data Upload Worksheet"],
  [""],
  ["How to use this workbook:"],
  ["1. Fill in each sheet in order: Locations, Payment Plans, Batches, Coaches, Players."],
  ["   (Order matters — Payment Plans/Batches reference Locations by name; Players reference Locations/Batches/Payment Plans by name.)"],
  ["2. Each data sheet has a matching \"... Notes\" sheet explaining every column."],
  ["3. Delete the example row(s) before adding your real data, or just add your rows below them and delete the examples after."],
  ["4. Names used for lookups (location_name, batch_name, etc.) must match EXACTLY (same spelling/case) across sheets."],
  ["5. Once filled in, send the workbook back and it can be converted into the SQL insert script (data-import/import.sql) automatically."],
  [""],
  ["Do not rename the sheet tabs — the import script matches them by name."],
  [""],
  ["This workbook was generated directly from the live Supabase schema (checked via the actual running app's database connection, not from memory) — every column shown here is a real column in the database."],
  ["Every table also has created_at / created_by / updated_at / updated_by columns that are NOT included in this worksheet — those are managed automatically by the database itself and should never be filled in manually."],
]);
readme["!cols"] = [{ wch: 100 }];
XLSX.utils.book_append_sheet(wb, readme, "0 Read Me");
// Move Read Me to front
wb.SheetNames = ["0 Read Me", ...wb.SheetNames.filter((n) => n !== "0 Read Me")];

const out = XLSX.write(wb, { bookType: "xlsx", type: "buffer" });
writeFileSync("data-import/CFFA-Data-Upload-Worksheet.xlsx", out);
console.log("workbook written");
