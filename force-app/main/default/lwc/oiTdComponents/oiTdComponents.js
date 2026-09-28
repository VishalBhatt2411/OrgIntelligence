import { LightningElement, api } from "lwc";
import getObjectFields from "@salesforce/apex/OI_TD_Controller.getObjectFields";
import {
  APEX_CATEGORY_ORDER,
  FLOW_CATEGORY_ORDER,
  groupByCategory,
  parseFields
} from "c/oiTdUtils";

const USED_COLOR = "#14854F";

function countUsage(items) {
  let used = 0;
  for (const i of items) if (i.usedIn.length > 0) used++;
  return { used, unused: items.length - used };
}

/**
 * Components page (reference: pages/ComponentsPage.tsx) — used-vs-unused chart, object/field browser
 * and the per-type inventories. Fields load per object on demand (getObjectFields).
 */
export default class OiTdComponents extends LightningElement {
  @api scanId;
  @api loading = false;
  _usage;
  _initialSearch;
  objectSearch = "";
  selectedObject = null;
  fieldsByObject = {};
  fieldsLoading = false;
  fieldsError = false;
  collapsed = {};

  @api
  get usage() {
    return this._usage;
  }
  set usage(v) {
    this._usage = v;
    this.fieldsByObject = {};
    this.ensureFields();
  }

  @api
  get initialSearch() {
    return this._initialSearch;
  }
  set initialSearch(v) {
    this._initialSearch = v;
    if (v) {
      this.objectSearch = v;
      this.selectedObject = null;
      this.ensureFields();
    }
  }

  connectedCallback() {
    this.ensureFields();
  }

  get noData() {
    return !this._usage;
  }

  // ------------------------------------------------------------------ chart

  get chartRows() {
    const u = this._usage;
    if (!u) return [];
    const summary = u.summary || {};
    const counts = summary.counts || {};
    const usedCounts = summary.used || {};
    const totalFields = counts.fields || 0;
    const usedFields = usedCounts.fields || 0;
    const rows = [
      { name: "Objects", ...countUsage(u.objects) },
      {
        name: "Fields",
        used: usedFields,
        unused: Math.max(totalFields - usedFields, 0)
      },
      { name: "Classes", ...countUsage(u.classes) },
      { name: "Triggers", ...countUsage(u.triggers) },
      { name: "Flows", ...countUsage(u.flows) },
      { name: "LWC", ...countUsage(u.lwc) },
      { name: "VF Pages", ...countUsage(u.visualforcePages) },
      { name: "VF Components", ...countUsage(u.visualforceComponents) }
    ];
    return rows.map((d, i) => {
      const total = d.used + d.unused;
      const usedPct = total ? (d.used / total) * 100 : 0;
      return {
        ...d,
        total,
        rowClass: i === 0 ? "chart-row" : "chart-row chart-row-border",
        barStyle: `width: ${Math.max(usedPct, d.used > 0 ? 1.5 : 0)}%; background: ${USED_COLOR};`,
        caption: `${d.used} of ${total} used`
      };
    });
  }

  // ------------------------------------------------------------------ objects & fields

  get objectCount() {
    return this._usage ? this._usage.objects.length : 0;
  }

  get filteredObjects() {
    if (!this._usage) return [];
    const q = this.objectSearch.trim().toLowerCase();
    return q
      ? this._usage.objects.filter((o) => o.apiName.toLowerCase().includes(q))
      : this._usage.objects;
  }

  get activeObject() {
    if (!this._usage) return undefined;
    const objects = this._usage.objects;
    return (
      objects.find((o) => o.apiName === this.selectedObject) ||
      this.filteredObjects[0] ||
      objects[0]
    );
  }

  get objectRows() {
    const active = this.activeObject;
    return this.filteredObjects.map((o) => ({
      key: o.apiName,
      apiName: o.apiName,
      used: o.usedIn.length > 0,
      usedLabel: `Used (${o.usedIn.length})`,
      rowClass:
        active && o.apiName === active.apiName
          ? "obj-row obj-row-selected"
          : "obj-row"
    }));
  }

  get noObjectsMatch() {
    return this.filteredObjects.length === 0;
  }

  get activeFields() {
    const active = this.activeObject;
    return active ? this.fieldsByObject[active.apiName] : undefined;
  }

  get fieldsTitle() {
    const active = this.activeObject;
    if (!active) return "Fields";
    const fields = this.activeFields;
    return `${active.apiName} — Fields (${fields ? fields.length : active.fieldCount})`;
  }

  get fieldRows() {
    const active = this.activeObject;
    const fields = this.activeFields;
    if (!active || !fields) return [];
    return fields.map((f) => ({
      key: f.apiName,
      name: `${f.apiName} (${f.type})`,
      usedIn: f.usedIn,
      references: f.references,
      linkName: `${active.apiName}.${f.apiName}`,
      fieldName: f.apiName,
      objectName: active.apiName
    }));
  }

  get showFieldsLoading() {
    return this.fieldsLoading && !this.activeFields;
  }

  handleObjectSearch(event) {
    this.objectSearch = event.target.value;
    this.ensureFields();
  }

  handleSelectObject(event) {
    this.selectedObject = event.currentTarget.dataset.name;
    this.ensureFields();
  }

  ensureFields() {
    const active = this.activeObject;
    if (!active || !this.scanId || this.fieldsByObject[active.apiName]) return;
    if (active.shard === null || active.shard === undefined) {
      this.fieldsByObject = { ...this.fieldsByObject, [active.apiName]: [] };
      return;
    }
    const apiName = active.apiName;
    const refsTable = this._usage.refsTable;
    this.fieldsLoading = true;
    this.fieldsError = false;
    getObjectFields({
      scanId: this.scanId,
      shardSeq: active.shard,
      objectName: apiName
    })
      .then((json) => {
        this.fieldsByObject = {
          ...this.fieldsByObject,
          [apiName]: parseFields(json, refsTable)
        };
      })
      .catch(() => {
        this.fieldsError = true;
      })
      .finally(() => {
        this.fieldsLoading = false;
      });
  }

  // ------------------------------------------------------------------ sections

  groups(kind, items, order, nameOf, linkOf) {
    return groupByCategory(items, order).map(({ category, items: rows }) => {
      const key = `${kind}:${category}`;
      const open = !this.collapsed[key];
      return {
        key,
        open,
        label: `${category} (${rows.length})`,
        caret: open ? "▾" : "▸",
        rows: rows.map((r) => ({
          key: linkOf(r),
          name: nameOf(r),
          linkName: linkOf(r),
          item: r
        }))
      };
    });
  }

  get classGroups() {
    return this._usage
      ? this.groups(
          "apex",
          this._usage.classes,
          APEX_CATEGORY_ORDER,
          (c) => c.name,
          (c) => c.name
        )
      : [];
  }

  get flowGroups() {
    return this._usage
      ? this.groups(
          "flow",
          this._usage.flows,
          FLOW_CATEGORY_ORDER,
          (f) => `${f.label} (${f.status})`,
          (f) => f.apiName
        )
      : [];
  }

  handleToggleGroup(event) {
    const key = event.currentTarget.dataset.key;
    this.collapsed = { ...this.collapsed, [key]: !this.collapsed[key] };
  }

  get classCount() {
    return this._usage ? this._usage.classes.length : 0;
  }
  get triggers() {
    return this._usage ? this._usage.triggers : [];
  }
  get triggerCount() {
    return this.triggers.length;
  }
  get flowCount() {
    return this._usage ? this._usage.flows.length : 0;
  }
  get lwc() {
    return this._usage ? this._usage.lwc : [];
  }
  get lwcCount() {
    return this.lwc.length;
  }
  get workflowRules() {
    return this._usage
      ? this._usage.workflowRules.map((w) => ({
          key: `${w.objectName}.${w.name}`,
          name: `${w.name} (${w.objectName})`,
          linkName: `${w.objectName}.${w.name}`,
          badge: w.active ? "Active" : "Inactive",
          active: w.active,
          item: w
        }))
      : [];
  }
  get workflowCount() {
    return this.workflowRules.length;
  }
  get processBuilderFlows() {
    return this._usage
      ? this._usage.flows
          .filter((f) => f.category === "Process Builder")
          .map((f) => ({
            key: f.apiName,
            name: `${f.label} (${f.status})`,
            item: f
          }))
      : [];
  }
  get processBuilderCount() {
    return this.processBuilderFlows.length;
  }
  get noProcessBuilder() {
    return this.processBuilderFlows.length === 0;
  }
  get vfPages() {
    return this._usage ? this._usage.visualforcePages : [];
  }
  get vfPageCount() {
    return this.vfPages.length;
  }
  get vfComponents() {
    return this._usage ? this._usage.visualforceComponents : [];
  }
  get vfComponentCount() {
    return this.vfComponents.length;
  }
  get emailTemplates() {
    return this._usage
      ? this._usage.emailTemplates.map((t, i) => ({
          key: `${t.developerName || t.name}-${i}`,
          name: t.name,
          templateType: t.templateType,
          label: t.isActive ? "Active" : "Inactive",
          chipClass: t.isActive ? "chip chip-used" : "chip chip-outlined"
        }))
      : [];
  }
  get emailCount() {
    return this.emailTemplates.length;
  }
  get noEmailTemplates() {
    return this.emailTemplates.length === 0;
  }
  get packages() {
    return this._usage
      ? this._usage.installedPackages.map((p, i) => ({
          key: `${p.namespacePrefix}-${p.name}-${i}`,
          name: p.name,
          namespacePrefix: p.namespacePrefix,
          version: p.versionNumber ? `v${p.versionNumber}` : null
        }))
      : [];
  }
  get packageCount() {
    return this.packages.length;
  }
  get noPackages() {
    return this.packages.length === 0;
  }
}
