import { createElement } from 'lwc';
import OiGraphNode from 'c/oiGraphNode';

describe('c-oi-graph-node', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('dispatches select with the nodeKey on click', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.typeKey = 'SalesforceMetadata.CustomObject';
        element.label = 'Account';
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        return Promise.resolve().then(() => {
            element.shadowRoot.querySelector('[data-id="graph-node"]').click();
            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('n1');
        });
    });

    it('dispatches expandtoggle on the toggle button without also triggering select', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
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
            expect(selectHandler).not.toHaveBeenCalled();
        });
    });

    it('renders successfully for a synthetic, never-registered typeKey with the generic fallback props — the required unknown-type render mandate', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.typeKey = 'SalesforceMetadata.NeverRegisteredByAnyone';
        element.label = 'Mystery Node';
        element.iconName = 'standard:custom';
        element.colorToken = 'neutral';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="graph-node"]')).not.toBeNull();
        });
    });

    it('resolves a known registry colorToken to a real CSS color for its accent stripe, not the raw token name', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.colorToken = 'brand';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const style = element.shadowRoot.querySelector('[data-id="graph-node"]').getAttribute('style');
            expect(style).toContain('#0176d3');
            expect(style).not.toContain('brand');
        });
    });

    it('falls back to a neutral color for an unrecognized colorToken, never a broken style', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.label = 'Account';
        element.colorToken = 'some-future-token-this-component-has-never-seen';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const style = element.shadowRoot.querySelector('[data-id="graph-node"]').getAttribute('style');
            expect(style).toContain('#706e6b');
        });
    });

    it('applies the is-cluster class when isCluster is true, distinguishing a cluster card from a real node', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = '__cluster__::root::T';
        element.label = '12 Field';
        element.isCluster = true;
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="graph-node"]').className).toContain('is-cluster');
        });
    });

    it('renders the secondaryKey as a visible caption line so the record/field\'s Object or qualified identity is visible on the node itself, not just on hover', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'Record::Contact::003x1';
        element.typeKey = 'SalesforceRecord.Contact';
        element.label = 'John Doe';
        element.secondaryKey = 'Contact 003x1';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const secondary = element.shadowRoot.querySelector('[data-id="node-secondary"]');
            expect(secondary).not.toBeNull();
            expect(secondary.textContent).toBe('Contact 003x1');
            expect(element.shadowRoot.querySelector('[data-id="graph-node"]').getAttribute('aria-label')).toContain('Contact 003x1');
        });
    });

    it('omits the secondary caption line entirely when a node has no secondaryKey, rather than rendering an empty line', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.label = 'Account';
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="node-secondary"]')).toBeNull();
        });
    });

    it('Enter key on the node triggers select, matching click behavior (keyboard-equivalent, GraphUI.md §28)', () => {
        const element = createElement('c-oi-graph-node', { is: OiGraphNode });
        element.nodeKey = 'n1';
        element.label = 'Account';
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        return Promise.resolve().then(() => {
            const div = element.shadowRoot.querySelector('[data-id="graph-node"]');
            div.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
            expect(handler).toHaveBeenCalledTimes(1);
        });
    });
});
