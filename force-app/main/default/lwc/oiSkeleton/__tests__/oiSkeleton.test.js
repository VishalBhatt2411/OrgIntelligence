import { createElement } from "lwc";
import OiSkeleton from "c/oiSkeleton";

describe("c-oi-skeleton", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  function render(props = {}) {
    const element = createElement("c-oi-skeleton", { is: OiSkeleton });
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
  }

  function lineCount(element) {
    return element.shadowRoot.querySelectorAll(".oi-skeleton-line").length;
  }

  it("draws three bars by default", () => {
    expect(lineCount(render())).toBe(3);
  });

  it("draws the requested number of bars so a caller can match the content being awaited", () => {
    expect(lineCount(render({ lines: 6 }))).toBe(6);
  });

  it.each([
    ["zero", 0],
    ["a negative count", -4],
    ["a non-numeric value", "lots"]
  ])(
    "still renders something for %s, rather than an empty region that looks broken",
    (_label, lines) => {
      expect(lineCount(render({ lines }))).toBeGreaterThan(0);
    }
  );

  it("caps the bar count so a bad caller value cannot flood the page", () => {
    expect(lineCount(render({ lines: 500 }))).toBeLessThanOrEqual(12);
  });

  it("keeps bar widths stable for a given count, so the skeleton does not reshuffle on re-render", () => {
    const first = Array.from(
      render({ lines: 4 }).shadowRoot.querySelectorAll(".oi-skeleton-line")
    ).map((l) => l.style.width);
    const second = Array.from(
      render({ lines: 4 }).shadowRoot.querySelectorAll(".oi-skeleton-line")
    ).map((l) => l.style.width);

    expect(second).toEqual(first);
  });

  it("announces politely with the caller-supplied label, since loading is ambient", () => {
    const container = render({
      label: "Loading Metadata Health"
    }).shadowRoot.querySelector('[data-id="skeleton"]');

    expect(container.getAttribute("role")).toBe("status");
    expect(container.getAttribute("aria-live")).toBe("polite");
    expect(container.getAttribute("aria-label")).toBe(
      "Loading Metadata Health"
    );
  });

  it("adopts a card surface only when asked, so it can stand in for either a card or inline text", () => {
    expect(
      render({ card: true }).shadowRoot.querySelector(".oi-skeleton").className
    ).toContain("oi-skeleton_card");
    expect(
      render().shadowRoot.querySelector(".oi-skeleton").className
    ).not.toContain("oi-skeleton_card");
  });

  it("hides the decorative bars from assistive tech, which only needs the one announcement", () => {
    const bars = render({ lines: 3 }).shadowRoot.querySelectorAll(
      ".oi-skeleton-line"
    );

    bars.forEach((bar) => expect(bar.getAttribute("aria-hidden")).toBe("true"));
  });
});
