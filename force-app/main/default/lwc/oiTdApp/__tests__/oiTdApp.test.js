import { createElement } from "lwc";
import OiTdApp from "c/oiTdApp";
import getSchedule from "@salesforce/apex/OI_TD_Controller.getSchedule";

jest.mock(
  "@salesforce/apex/OI_TD_Controller.getAppContext",
  () => ({
    default: jest.fn(() => Promise.resolve({ canManageSettings: true }))
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.getSchedule",
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.updateSchedule",
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.getScans",
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.startScan",
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.getFindings",
  () => ({ default: jest.fn(() => Promise.resolve("[]")) }),
  {
    virtual: true
  }
);
jest.mock(
  "@salesforce/apex/OI_TD_Controller.getComponents",
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  {
    virtual: true
  }
);

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-oi-td-app scan schedule dialog", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("marks only the active frequency as pressed", async () => {
    getSchedule.mockResolvedValue({ scheduleFrequency: "weekly" });
    const el = createElement("c-oi-td-app", { is: OiTdApp });
    document.body.appendChild(el);
    await flush();

    el.shadowRoot.querySelector('button[data-key="schedule"]').click();
    await flush();

    const pressed = {};
    el.shadowRoot.querySelectorAll("button[data-value]").forEach((b) => {
      pressed[b.dataset.value] = b.getAttribute("aria-pressed");
    });
    expect(pressed).toEqual({
      off: "false",
      daily: "false",
      weekly: "true",
      monthly: "false"
    });
  });
});
