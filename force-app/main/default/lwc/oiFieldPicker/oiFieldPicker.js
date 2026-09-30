import { api, LightningElement } from "lwc";

const LIST_CLOSE_DELAY_MS = 150;

/**
 * Purpose: Searchable picker for Field mode's relationship fields.
 * Responsibilities: The result list overlays the canvas, so it behaves like a combobox. It
 *                    starts open, so the list shows as soon as an object is chosen. It closes
 *                    on selection, Escape or blur, so the picked field's graph is visible, and
 *                    reopens on focus or typing.
 * Limitations: Shows at most 12 matches; typing narrows the list.
 */
export default class OiFieldPicker extends LightningElement {
  @api options = [];
  query = "";
  isListOpen = true;

  get filteredOptions() {
    const term = this.query.trim().toLowerCase();
    return (this.options || [])
      .filter((option) => !term || option.label.toLowerCase().includes(term))
      .slice(0, 12)
      .map((option) => {
        const match = option.label.match(/^(.*?)\s*\(([^)]+)\)$/);
        return {
          ...option,
          displayLabel: match ? match[1] : option.label,
          apiName: match ? match[2] : option.value
        };
      });
  }

  get resultCountLabel() {
    const visible = this.filteredOptions.length;
    const total = (this.options || []).length;
    return this.query ? `${visible} matches` : `${total} fields`;
  }

  get hasNoResults() {
    return this.filteredOptions.length === 0;
  }

  get isListVisible() {
    return this.isListOpen;
  }

  handleInput(event) {
    this.query = event.target.value;
    this.isListOpen = true;
  }

  handleFocus() {
    this.isListOpen = true;
  }

  /** Delayed so an option's click, which also blurs the input, still registers before the list closes. */
  handleBlur() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- a brief delay lets an option's click register before the list closes on blur; the same combobox pattern oiSearchBar uses.
    setTimeout(() => {
      this.isListOpen = false;
    }, LIST_CLOSE_DELAY_MS);
  }

  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.isListOpen = false;
    }
  }

  handleSelect(event) {
    this.isListOpen = false;
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: event.currentTarget.dataset.value }
      })
    );
  }
}
