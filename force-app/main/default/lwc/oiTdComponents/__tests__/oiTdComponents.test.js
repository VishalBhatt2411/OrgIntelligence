import { createElement } from "lwc";
import OiTdComponents from "c/oiTdComponents";

jest.mock(
  "@salesforce/apex/OI_TD_Controller.getObjectFields",
  () => ({ default: jest.fn(() => Promise.resolve("[]")) }),
  { virtual: true }
);

function usage(objects) {
  return {
    objects,
    refsTable: [],
    classes: [],
    triggers: [],
    flows: [],
    workflowRules: [],
    lwc: [],
    emailTemplates: [],
    visualforcePages: [],
    visualforceComponents: [],
    installedPackages: []
  };
}

function mount(objects) {
  const el = createElement("c-oi-td-components", { is: OiTdComponents });
  el.usage = usage(objects);
  document.body.appendChild(el);
  return el;
}

function emptyMessage(el) {
  const p = [...el.shadowRoot.querySelectorAll(".obj-list p")];
  return p.length ? p[0].textContent : null;
}

describe("c-oi-td-components object list", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("says the scan has no objects instead of quoting an empty search", async () => {
    const el = mount([]);
    await Promise.resolve();
    expect(emptyMessage(el)).toBe("No objects in this scan.");
  });

  it("quotes the search when it filters every object out", async () => {
    const el = mount([
      { apiName: "Account", usedIn: [], fieldCount: 0, shard: null }
    ]);
    await Promise.resolve();
    expect(emptyMessage(el)).toBeNull();

    const input = el.shadowRoot.querySelector(".obj-pane input");
    input.value = "zzz";
    input.dispatchEvent(new CustomEvent("input"));
    await Promise.resolve();
    expect(emptyMessage(el)).toBe('No objects match "zzz".');
  });
});
