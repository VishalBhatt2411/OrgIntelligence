import { createElement } from "lwc";
import OiStateBanner from "c/oiStateBanner";

describe("c-oi-state-banner", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function render(props = {}) {
    const element = createElement("c-oi-state-banner", { is: OiStateBanner });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
  }

  it("renders the caller-supplied title and message rather than copy of its own", () => {
    const element = render({
      state: "true-zero",
      title: "0 orphaned objects",
      message: "Every object is referenced."
    });

    expect(
      element.shadowRoot.querySelector(".oi-state-banner-title").textContent
    ).toBe("0 orphaned objects");
    expect(
      element.shadowRoot.querySelector(".oi-state-banner-sub").textContent
    ).toContain("Every object is referenced.");
  });

  it.each([
    ["true-zero", "success", "✓"],
    ["coverage-incomplete", "warning", "◐"],
    ["not-yet-run", "neutral", "◷"],
    ["not-obtainable", "neutral", "＿"],
    ["error", "critical", "!"]
  ])(
    "gives %s its own distinct glyph and variant, so the five states never collapse",
    (state, variant, glyph) => {
      const element = render({ state });
      const icon = element.shadowRoot.querySelector(".oi-state-banner-icon");

      expect(icon.className).toContain(`oi-state-banner_${variant}`);
      expect(icon.textContent).toBe(glyph);
    }
  );

  it("offers Retry only for a failed request", () => {
    expect(
      render({ state: "error" }).shadowRoot.querySelector(
        '[data-id="state-banner-retry"]'
      )
    ).not.toBeNull();
  });

  it.each([
    "true-zero",
    "coverage-incomplete",
    "not-yet-run",
    "not-obtainable"
  ])(
    "never offers Retry for %s, because re-requesting it would change nothing",
    (state) => {
      expect(
        render({ state }).shadowRoot.querySelector(
          '[data-id="state-banner-retry"]'
        )
      ).toBeNull();
    }
  );

  it("emits retry so the caller can re-run just its own request", () => {
    const element = render({ state: "error" });
    const handler = jest.fn();
    element.addEventListener("retry", handler);

    element.shadowRoot.querySelector('[data-id="state-banner-retry"]').click();

    expect(handler).toHaveBeenCalled();
  });

  it("announces a failure assertively but leaves the other four states polite", () => {
    expect(
      render({ state: "error" })
        .shadowRoot.querySelector(".oi-state-banner")
        .getAttribute("role")
    ).toBe("alert");
    expect(
      render({ state: "true-zero" })
        .shadowRoot.querySelector(".oi-state-banner")
        .getAttribute("role")
    ).toBe("status");
  });

  it("shows a correlation id only on a failure, where it is actionable", () => {
    expect(
      render({
        state: "error",
        correlationId: "abc-123"
      }).shadowRoot.querySelector(".num").textContent
    ).toBe("abc-123");
    expect(
      render({
        state: "coverage-incomplete",
        correlationId: "abc-123"
      }).shadowRoot.querySelector(".num")
    ).toBeNull();
  });

  it("falls back to a neutral state rather than rendering blank for an unknown state key", () => {
    const icon = render({
      state: "something-nobody-has-defined"
    }).shadowRoot.querySelector(".oi-state-banner-icon");

    expect(icon.className).toContain("oi-state-banner_neutral");
    expect(icon.textContent).toBe("◷");
  });
});
