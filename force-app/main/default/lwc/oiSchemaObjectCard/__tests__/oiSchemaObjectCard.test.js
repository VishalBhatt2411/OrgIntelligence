import { createElement } from 'lwc';
import OiSchemaObjectCard from 'c/oiSchemaObjectCard';

function makeFields(count) {
    return Array.from({ length: count }, (_, i) => ({
        nodeKey: `f${i}`,
        label: `Field_${i}__c`,
        iconName: 'standard:text'
    }));
}

describe('c-oi-schema-object-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('dispatches select with the nodeKey when the header is clicked', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        return Promise.resolve().then(() => {
            element.shadowRoot.querySelector('.oi-schema-card-header').click();
            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('n1');
        });
    });

    it('dispatches expandtoggle on the expand button without also triggering select', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        document.body.appendChild(element);
        const selectHandler = jest.fn();
        const expandHandler = jest.fn();
        element.addEventListener('select', selectHandler);
        element.addEventListener('expandtoggle', expandHandler);

        return Promise.resolve().then(() => {
            element.shadowRoot.querySelector('[data-id="expand-toggle-button"]').click();
            expect(expandHandler).toHaveBeenCalledTimes(1);
            expect(expandHandler.mock.calls[0][0].detail.nodeKey).toBe('n1');
            expect(selectHandler).not.toHaveBeenCalled();
        });
    });

    it('renders a plain field-count line instead of individual field rows — field browsing lives in the Detail Panel now, not on the canvas card', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.fields = makeFields(12);
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelectorAll('[data-id="field-row"]')).toHaveLength(0);
            expect(element.shadowRoot.querySelector('[data-id="fields-toggle"]')).toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="field-count"]').textContent).toBe('12 fields');
        });
    });

    it('singularizes the field-count line for exactly one field', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.fields = makeFields(1);
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="field-count"]').textContent).toBe('1 field');
        });
    });

    it('resolves a known registry colorToken to a real CSS color for the accent border, not the raw token name', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.colorToken = 'brand';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const style = element.shadowRoot.querySelector('[data-id="schema-card"]').getAttribute('style');
            expect(style).toContain('#0176d3');
            expect(style).not.toContain('brand');
        });
    });

    it('falls back to a neutral color for an unrecognized colorToken, never a broken style', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.colorToken = 'some-future-token-this-component-has-never-seen';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const style = element.shadowRoot.querySelector('[data-id="schema-card"]').getAttribute('style');
            expect(style).toContain('#706e6b');
        });
    });

    it('applies the is-selected class when isSelected is true', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.isSelected = true;
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="schema-card"]').className).toContain('is-selected');
        });
    });

    it('Enter key on the header triggers select, matching click behavior (keyboard-equivalent parity with oiGraphNode)', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        return Promise.resolve().then(() => {
            const header = element.shadowRoot.querySelector('.oi-schema-card-header');
            header.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
            expect(handler).toHaveBeenCalledTimes(1);
        });
    });

    it('includes field count and expand state in the header aria-label for accessibility', () => {
        const element = createElement('c-oi-schema-object-card', { is: OiSchemaObjectCard });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.fields = makeFields(3);
        element.isExpanded = true;
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const header = element.shadowRoot.querySelector('.oi-schema-card-header');
            expect(header.getAttribute('aria-label')).toContain('Account');
            expect(header.getAttribute('aria-label')).toContain('3 fields');
            expect(header.getAttribute('aria-label')).toContain('expanded');
        });
    });
});
