import { createElement } from 'lwc';
import OiFilterPanel from 'c/oiFilterPanel';

function flushPromises() {
    return Promise.resolve();
}

describe('c-oi-filter-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders nothing but an empty shell when there are no edge type options (nothing loaded yet)', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="edge-type-section"]')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="direction-section"]')).toBeNull();
    });

    it('renders one checkbox per edge type option, reflecting its checked state', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [
            { typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', isChecked: true, swatchClass: 'oi-filter-panel-swatch oi-filter-panel-swatch-dashed' },
            { typeKey: 'SalesforceMetadata.HAS_FIELD', displayLabel: 'Has Field', isChecked: false, swatchClass: 'oi-filter-panel-swatch oi-filter-panel-swatch-solid' }
        ];
        document.body.appendChild(element);
        await flushPromises();

        const checkboxes = element.shadowRoot.querySelectorAll('[data-id="edge-type-checkbox"]');
        expect(checkboxes).toHaveLength(2);
    });

    /** This panel now doubles as the graph's relationship legend (this sprint's requirement) — each entry must teach what the relationship means, not just name it. */
    it('renders a plain-English description under each relationship type, so the panel doubles as the graph legend', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [
            {
                typeKey: 'SalesforceMetadata.EXECUTES_ON',
                displayLabel: 'Executes On',
                description: 'Automation that runs when records of this object change.',
                isChecked: true,
                swatchClass: 'oi-filter-panel-swatch oi-filter-panel-swatch-solid'
            }
        ];
        document.body.appendChild(element);
        await flushPromises();

        const description = element.shadowRoot.querySelector('[data-id="legend-description"]');
        expect(description).not.toBeNull();
        expect(description.textContent).toBe('Automation that runs when records of this object change.');
    });

    it('omits the description line entirely when a relationship type carries none, rather than an empty paragraph', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'SalesforceMetadata.Unknown', displayLabel: 'Unknown', isChecked: true, swatchClass: 'oi-filter-panel-swatch oi-filter-panel-swatch-solid' }];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="legend-description"]')).toBeNull();
    });

    it('toggling an edge type checkbox emits edgetypetoggle with that typeKey', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'SalesforceMetadata.LOOKUP_TO', displayLabel: 'Lookup To', isChecked: true, swatchClass: '' }];
        document.body.appendChild(element);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('edgetypetoggle', handler);
        element.shadowRoot.querySelector('[data-id="edge-type-checkbox"]').dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.typeKey).toBe('SalesforceMetadata.LOOKUP_TO');
    });

    it('defaults direction to both parents and children shown when direction="both"', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'T', displayLabel: 'T', isChecked: true, swatchClass: '' }];
        element.direction = 'both';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="direction-parents-checkbox"]').checked).toBe(true);
        expect(element.shadowRoot.querySelector('[data-id="direction-children-checkbox"]').checked).toBe(true);
    });

    it('unchecking "Parent Objects" emits directiontoggle with showParents false and showChildren unchanged', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'T', displayLabel: 'T', isChecked: true, swatchClass: '' }];
        element.direction = 'both';
        document.body.appendChild(element);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('directiontoggle', handler);
        element.shadowRoot.querySelector('[data-id="direction-parents-checkbox"]').dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(handler.mock.calls[0][0].detail).toEqual({ showParents: false, showChildren: true });
    });

    it('reflects direction="outgoing" as parents-only checked', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'T', displayLabel: 'T', isChecked: true, swatchClass: '' }];
        element.direction = 'outgoing';
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="direction-parents-checkbox"]').checked).toBe(true);
        expect(element.shadowRoot.querySelector('[data-id="direction-children-checkbox"]').checked).toBe(false);
    });

    it('toggling the depth checkbox emits depthtoggle with the inverted restrictToDirectOnly value', async () => {
        const element = createElement('c-oi-filter-panel', { is: OiFilterPanel });
        element.edgeTypeOptions = [{ typeKey: 'T', displayLabel: 'T', isChecked: true, swatchClass: '' }];
        element.restrictToDirectOnly = false;
        document.body.appendChild(element);
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('depthtoggle', handler);
        element.shadowRoot.querySelector('[data-id="depth-direct-only-checkbox"]').dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(handler.mock.calls[0][0].detail).toEqual({ restrictToDirectOnly: true });
    });
});
