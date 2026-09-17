import { api, LightningElement } from "lwc";

export default class OiFieldPicker extends LightningElement {
  @api options = [];
  query = "";

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

  handleInput(event) {
    this.query = event.target.value;
  }

  handleSelect(event) {
    this.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: event.currentTarget.dataset.value }
      })
    );
  }
}
