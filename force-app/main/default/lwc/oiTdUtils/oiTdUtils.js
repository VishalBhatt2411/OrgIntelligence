/**
 * Purpose: Shared helpers for the Tech Debt tab (oiTd* components).
 * Responsibilities: Severity/status/score constants (frontend/src/severity.ts + page constants of the
 *                    reference app), formatting, expansion of the compact component inventory returned by
 *                    OI_TD_Controller.getComponents (short keys + usage as indices into "refs"), and the
 *                    client-side Excel (.xlsx) export writer.
 * Limitations: The .xlsx writer produces an uncompressed (stored) ZIP — valid for Excel/Sheets/Numbers.
 */

// ---------------------------------------------------------------------------
// Severity / status / score
// ---------------------------------------------------------------------------

export const SEVERITY_ORDER = ["critical", "high", "medium", "low"];
export const SEVERITY_RANK = { critical: 0, high: 1, medium: 2, low: 3 };
export const SEVERITY_HEX = {
  critical: "#D93A3F",
  high: "#EE9A12",
  medium: "#FBB22E",
  low: "#BCC5D1"
};
const SEVERITY_CHIP = {
  low: "chip-default",
  medium: "chip-default",
  high: "chip-warning",
  critical: "chip-error"
};

export function severityChipClass(severity) {
  return "chip " + (SEVERITY_CHIP[severity] || "chip-default");
}

export function sortBySeverity(items) {
  return [...items].sort(
    (a, b) =>
      (SEVERITY_RANK[a.severity] ?? 9) - (SEVERITY_RANK[b.severity] ?? 9)
  );
}

export const STATUS_LABEL = {
  open: "Open",
  acknowledged: "Acknowledged",
  resolved: "Resolved",
  wont_fix: "Won't Fix"
};
export const STATUS_OPTIONS = Object.keys(STATUS_LABEL).map((value) => ({
  value,
  label: STATUS_LABEL[value]
}));

export const SCORE_STATUS = {
  good: "#14854F",
  warning: "#EE9A12",
  critical: "#D93A3F"
};

export function statusOf(score) {
  if (score >= 75) return "good";
  if (score >= 50) return "warning";
  return "critical";
}

export function scoreColor(score) {
  return SCORE_STATUS[statusOf(score)];
}

export const RISK_PILL = {
  good: { label: "Healthy", bg: "#E8F7EF", fg: "#0B5333" },
  warning: { label: "Needs attention", bg: "#FFF7E6", fg: "#9E5E0A" },
  critical: { label: "At risk", bg: "#FCE4E4", fg: "#B82A2F" }
};

export function titleCase(s) {
  return String(s || "")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

export function abbreviateCount(n) {
  return n >= 1000
    ? `${(n / 1000).toFixed(1).replace(/\.0$/, "")}k`
    : String(n);
}

export function fmtDateTime(v) {
  return v ? new Date(v).toLocaleString() : "";
}

export function fmtDate(v) {
  return v ? new Date(v).toLocaleDateString() : "";
}

export function fmtTime(v) {
  return v ? new Date(v).toLocaleTimeString() : "";
}

/** Readable message from an Apex/LDS error (AuraHandledException messages are already sanitized). */
export function errorMessage(error) {
  if (!error) return "Unknown error";
  if (Array.isArray(error.body))
    return error.body.map((e) => e.message).join(", ");
  if (error.body && typeof error.body.message === "string")
    return error.body.message;
  if (typeof error.message === "string") return error.message;
  return String(error);
}

// ---------------------------------------------------------------------------
// Component inventory
// ---------------------------------------------------------------------------

export const TYPE_LABELS = {
  ApexClass: ["Apex Class", "Apex Classes"],
  ApexTrigger: ["Trigger", "Triggers"],
  Flow: ["Flow", "Flows"],
  LightningWebComponent: ["LWC", "LWCs"],
  SfObject: ["Object", "Objects"],
  SfField: ["Field", "Fields"],
  Profile: ["Profile", "Profiles"],
  PermissionSet: ["Permission Set", "Permission Sets"],
  ApexPage: ["Visualforce Page", "Visualforce Pages"],
  ApexComponent: ["Visualforce Component", "Visualforce Components"],
  WorkflowRule: ["Workflow Rule", "Workflow Rules"]
};

export function typeLabel(type, count) {
  const [singular, plural] = TYPE_LABELS[type] || [type, `${type}s`];
  return count === 1 ? singular : plural;
}

/** "Used in: 2 Flows, 1 Trigger — A (Flow), B (Flow), C (ApexTrigger)" (without the label). */
export function describeRefs(refs) {
  if (!refs || refs.length === 0) return "";
  const counts = new Map();
  for (const ref of refs) counts.set(ref.type, (counts.get(ref.type) || 0) + 1);
  const grouped = [...counts.entries()]
    .map(([type, count]) => `${count} ${typeLabel(type, count)}`)
    .join(", ");
  return `${grouped} — ${refs.map((r) => `${r.name} (${r.type})`).join(", ")}`;
}

export const RISK_COLOR = {
  low: "#14854F",
  medium: "#EE9A12",
  high: "#D93A3F"
};

export function deleteRiskFor(usedIn) {
  const n = usedIn ? usedIn.length : 0;
  if (n === 0) return { level: "low", label: "Low risk" };
  if (n <= 2) return { level: "medium", label: "Medium risk" };
  return { level: "high", label: "High risk" };
}

export const FLOW_CATEGORY_ORDER = [
  "Screen Flow",
  "Record-Triggered Flow",
  "Scheduled-Triggered Flow",
  "Platform Event-Triggered Flow",
  "Autolaunched Flow"
];

export const APEX_CATEGORY_ORDER = [
  "Batch Class",
  "Future Class",
  "Queueable Class",
  "Test Class",
  "Apex Class"
];

export function groupByCategory(items, order) {
  const groups = new Map();
  for (const item of items) {
    if (!groups.has(item.category)) groups.set(item.category, []);
    groups.get(item.category).push(item);
  }
  return order
    .map((category) => ({ category, items: groups.get(category) || [] }))
    .filter((g) => g.items.length > 0);
}

function refsResolver(rawRefs) {
  const refs = (rawRefs || []).map((pair) => ({
    type: pair[0],
    name: pair[1]
  }));
  return (indices) => {
    const out = [];
    for (const i of indices || []) {
      if (refs[i]) out.push(refs[i]);
    }
    return out;
  };
}

/** Expands the JSON document from OI_TD_Controller.getComponents into the reference's ComponentUsage shape. */
export function parseComponents(json) {
  const raw = typeof json === "string" ? JSON.parse(json) : json || {};
  const pick = refsResolver(raw.refs);
  const list = (key) => (Array.isArray(raw[key]) ? raw[key] : []);
  const summary = raw.summary || {};
  return {
    available: raw.available === true,
    summary,
    refsTable: raw.refs || [],
    objects: list("objects").map((o) => ({
      apiName: o.a,
      label: o.l || o.a,
      fieldCount: o.c || 0,
      shard: o.s,
      usedIn: pick(o.u),
      references: pick(o.r)
    })),
    classes: list("classes").map((c) => ({
      name: c.n,
      category: c.c || "Apex Class",
      usedIn: pick(c.u),
      references: pick(c.r)
    })),
    triggers: list("triggers").map((t) => ({
      name: t.n,
      objectName: t.o,
      usedIn: pick(t.u),
      references: pick(t.r)
    })),
    flows: list("flows").map((f) => ({
      apiName: f.a,
      label: f.l || f.a,
      status: f.s,
      triggerType: f.tt,
      objectName: f.o,
      processType: f.p,
      category: f.k,
      usedIn: pick(f.u),
      references: pick(f.r)
    })),
    workflowRules: list("wf").map((w) => ({
      name: w.n,
      objectName: w.o,
      active: w.ac === true,
      usedIn: pick(w.u),
      references: pick(w.r)
    })),
    lwc: list("lwc").map((l) => ({
      apiName: l.a,
      usedIn: pick(l.u),
      references: pick(l.r)
    })),
    visualforcePages: list("vfp").map((p) => ({
      name: p.n,
      usedIn: pick(p.u),
      references: pick(p.r)
    })),
    visualforceComponents: list("vfc").map((c) => ({
      name: c.n,
      usedIn: pick(c.u),
      references: pick(c.r)
    })),
    emailTemplates: list("email").map((e) => ({
      name: e.n,
      developerName: e.d,
      templateType: e.t,
      isActive: e.ac === true
    })),
    installedPackages: list("pkgs").map((p) => ({
      name: p.n,
      namespacePrefix: p.ns,
      versionNumber: p.vn
    }))
  };
}

/** Expands one object's fields (getObjectFields JSON) using the scan's refs table. */
export function parseFields(json, refsTable) {
  const rows = typeof json === "string" ? JSON.parse(json) : json || [];
  const pick = refsResolver(refsTable);
  return rows.map((f) => ({
    apiName: f.a,
    type: f.t,
    usedIn: pick(f.u),
    references: pick(f.r)
  }));
}

/** Total component count for the sidebar badge (reference: totalComponentCount). */
export function totalComponentCount(usage) {
  if (!usage) return undefined;
  const c = (usage.summary && usage.summary.counts) || {};
  const fields =
    c.fields != null
      ? c.fields
      : usage.objects.reduce((n, o) => n + (o.fieldCount || 0), 0);
  return (
    usage.objects.length +
    fields +
    usage.classes.length +
    usage.triggers.length +
    usage.flows.length +
    usage.lwc.length +
    usage.visualforcePages.length +
    usage.visualforceComponents.length +
    usage.workflowRules.length +
    usage.emailTemplates.length +
    usage.installedPackages.length
  );
}

// ---------------------------------------------------------------------------
// Excel export (.xlsx) — same workbook as the reference's reportExport.ts
// ---------------------------------------------------------------------------

function xmlEscape(v) {
  return (
    String(v)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      // Strip characters that are illegal in XML 1.0.
      // eslint-disable-next-line no-control-regex
      .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "")
  );
}

function colName(i) {
  let s = "";
  let n = i + 1;
  while (n > 0) {
    const m = (n - 1) % 26;
    s = String.fromCharCode(65 + m) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

/** rows: array of { cells: [...values], bold?: boolean }; widths: column widths. */
function sheetXml(widths, rows) {
  const cols = widths
    .map(
      (w, i) =>
        `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`
    )
    .join("");
  const body = rows
    .map((row, r) => {
      const cells = (row.cells || [])
        .map((v, c) => {
          if (v === null || v === undefined || v === "") return "";
          const ref = `${colName(c)}${r + 1}`;
          const style = row.bold ? ' s="1"' : "";
          if (typeof v === "number" && isFinite(v)) {
            return `<c r="${ref}"${style}><v>${v}</v></c>`;
          }
          return `<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${xmlEscape(v)}</t></is></c>`;
        })
        .join("");
      return `<row r="${r + 1}">${cells}</row>`;
    })
    .join("");
  return (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    `<cols>${cols}</cols><sheetData>${body}</sheetData></worksheet>`
  );
}

function utf8(str) {
  const out = [];
  for (let i = 0; i < str.length; i++) {
    let code = str.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < str.length) {
      const next = str.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
        i++;
      }
    }
    if (code < 0x80) out.push(code);
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 63));
    else if (code < 0x10000)
      out.push(
        0xe0 | (code >> 12),
        0x80 | ((code >> 6) & 63),
        0x80 | (code & 63)
      );
    else
      out.push(
        0xf0 | (code >> 18),
        0x80 | ((code >> 12) & 63),
        0x80 | ((code >> 6) & 63),
        0x80 | (code & 63)
      );
  }
  return new Uint8Array(out);
}

let crcTable;
function crc32(bytes) {
  if (!crcTable) {
    crcTable = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++)
    crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** Stored (uncompressed) ZIP of { name, data: Uint8Array } entries. */
function zip(files) {
  const now = new Date();
  const dosTime =
    (now.getHours() << 11) |
    (now.getMinutes() << 5) |
    Math.floor(now.getSeconds() / 2);
  const dosDate =
    ((now.getFullYear() - 1980) << 9) |
    ((now.getMonth() + 1) << 5) |
    now.getDate();
  const chunks = [];
  const central = [];
  let offset = 0;
  for (const f of files) {
    const name = utf8(f.name);
    const crc = crc32(f.data);
    const size = f.data.length;
    const local = new DataView(new ArrayBuffer(30));
    local.setUint32(0, 0x04034b50, true);
    local.setUint16(4, 20, true);
    local.setUint16(6, 0x0800, true);
    local.setUint16(8, 0, true);
    local.setUint16(10, dosTime, true);
    local.setUint16(12, dosDate, true);
    local.setUint32(14, crc, true);
    local.setUint32(18, size, true);
    local.setUint32(22, size, true);
    local.setUint16(26, name.length, true);
    local.setUint16(28, 0, true);
    chunks.push(new Uint8Array(local.buffer), name, f.data);

    const cd = new DataView(new ArrayBuffer(46));
    cd.setUint32(0, 0x02014b50, true);
    cd.setUint16(4, 20, true);
    cd.setUint16(6, 20, true);
    cd.setUint16(8, 0x0800, true);
    cd.setUint16(10, 0, true);
    cd.setUint16(12, dosTime, true);
    cd.setUint16(14, dosDate, true);
    cd.setUint32(16, crc, true);
    cd.setUint32(20, size, true);
    cd.setUint32(24, size, true);
    cd.setUint16(28, name.length, true);
    cd.setUint16(30, 0, true);
    cd.setUint16(32, 0, true);
    cd.setUint16(34, 0, true);
    cd.setUint16(36, 0, true);
    cd.setUint32(38, 0, true);
    cd.setUint32(42, offset, true);
    central.push(new Uint8Array(cd.buffer), name);

    offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((n, c) => n + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true);
  end.setUint16(4, 0, true);
  end.setUint16(6, 0, true);
  end.setUint16(8, files.length, true);
  end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true);
  end.setUint32(16, offset, true);
  end.setUint16(20, 0, true);

  const all = [...chunks, ...central, new Uint8Array(end.buffer)];
  const total = all.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(total);
  let pos = 0;
  for (const c of all) {
    out.set(c, pos);
    pos += c.length;
  }
  return out;
}

function toBase64(bytes) {
  let binary = "";
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + step));
  }
  return btoa(binary);
}

/** Builds the report workbook (Summary + Findings sheets) from OI_TD_Controller.getReportData. */
export function buildReportXlsx(report) {
  const summaryRows = [
    { cells: ["Org", report.org] },
    { cells: ["Scan date", report.scanDate] },
    { cells: ["Overall health score", `${report.overall} / 100`] },
    { cells: ["Total findings", report.totalFindings] },
    { cells: [] },
    { cells: ["Category", "Score"], bold: true },
    ...(report.categoryScores || []).map((c) => ({
      cells: [c.category, c.score]
    }))
  ];
  const findingRows = [
    {
      cells: [
        "Severity",
        "Category",
        "Status",
        "Component Type",
        "Component Name",
        "Title",
        "Detail",
        "Assigned To"
      ],
      bold: true
    },
    ...(report.findings || []).map((f) => ({
      cells: [
        f.severity,
        String(f.category || "").replace(/_/g, " "),
        f.status,
        f.componentType,
        f.componentName,
        f.title,
        f.detail,
        f.assignedTo || ""
      ]
    }))
  ];

  const contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
    "</Types>";
  const rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    "</Relationships>";
  const workbook =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    '<sheets><sheet name="Summary" sheetId="1" r:id="rId1"/><sheet name="Findings" sheetId="2" r:id="rId2"/></sheets>' +
    "</workbook>";
  const workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>' +
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
    "</Relationships>";
  const styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>' +
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>' +
    "</styleSheet>";

  const bytes = zip([
    { name: "[Content_Types].xml", data: utf8(contentTypes) },
    { name: "_rels/.rels", data: utf8(rootRels) },
    { name: "xl/workbook.xml", data: utf8(workbook) },
    { name: "xl/_rels/workbook.xml.rels", data: utf8(workbookRels) },
    { name: "xl/styles.xml", data: utf8(styles) },
    {
      name: "xl/worksheets/sheet1.xml",
      data: utf8(sheetXml([28, 20], summaryRows))
    },
    {
      name: "xl/worksheets/sheet2.xml",
      data: utf8(sheetXml([12, 16, 14, 20, 30, 40, 60, 20], findingRows))
    }
  ]);
  return toBase64(bytes);
}

export const XLSX_MIME =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

/** Triggers a browser download of base64 content (anchor + data URI works under Lightning Web Security). */
export function downloadBase64(filename, mime, base64, host) {
  const a = document.createElement("a");
  a.href = `data:${mime};base64,${base64}`;
  a.download = filename;
  a.style.display = "none";
  const parent = host || document.body;
  parent.appendChild(a);
  a.click();
  parent.removeChild(a);
}
