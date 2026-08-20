import { createElement } from 'lwc';
import OiGraphCanvas from 'c/oiGraphCanvas';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Reads a node's rendered center from its <foreignObject> x/y/width/height attributes — the DOM-observable equivalent of the internal layout's cx/cy, without reaching into component internals. */
function nodeCenter(element, nodeKey) {
    const foreignObject = element.shadowRoot.querySelector(`[data-node-key="${nodeKey}"]`);
    const x = Number(foreignObject.getAttribute('x'));
    const y = Number(foreignObject.getAttribute('y'));
    const width = Number(foreignObject.getAttribute('width'));
    const height = Number(foreignObject.getAttribute('height'));
    return { cx: x + width / 2, cy: y + height / 2 };
}

describe('c-oi-graph-canvas', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the empty state when there are no nodes', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.nodes = [];
        element.edges = [];
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('[data-id="canvas-empty"]')).not.toBeNull();
            expect(element.shadowRoot.querySelector('[data-id="canvas-svg"]')).toBeNull();
        });
    });

    it('renders one oiGraphNode per visible node and never fetches data itself (no Apex import in this module)', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const nodeElements = element.shadowRoot.querySelectorAll('c-oi-graph-node');
            expect(nodeElements).toHaveLength(2);
            expect(element.shadowRoot.querySelectorAll('.oi-graph-edge')).toHaveLength(1);
        });
    });

    it('renders a dashed edge with its own modifier class and a title tooltip carrying the display label (G4)', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' }
        ];
        element.edges = [
            { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: 'child', lineStyle: 'dashed', displayLabel: 'Lookup To' }
        ];
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const edgePath = element.shadowRoot.querySelector('.oi-graph-edge-dashed');
            expect(edgePath).not.toBeNull();
            expect(edgePath.querySelector('title').textContent).toBe('Lookup To');
        });
    });

    it('renders a dotted edge with its own modifier class (SalesforceMetadata.REFERENCES) — the registry documents solid/dashed/dotted, and dotted must actually render as dotted, not silently fall back to solid', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active', iconName: 'standard:custom', colorToken: 'neutral' }
        ];
        element.edges = [
            { edgeKey: 'e1', typeKey: 'SalesforceMetadata.REFERENCES', sourceNodeKey: 'root', targetNodeKey: 'child', lineStyle: 'dotted', displayLabel: 'References' }
        ];
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('.oi-graph-edge-dotted')).not.toBeNull();
            expect(element.shadowRoot.querySelector('.oi-graph-edge-dashed')).toBeNull();
        });
    });

    it('re-dispatches a child select event as its own select event', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        const handler = jest.fn();
        element.addEventListener('select', handler);

        return Promise.resolve().then(async () => {
            const childNode = element.shadowRoot.querySelector('c-oi-graph-node');
            childNode.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'root' } }));
            await flushPromises();
            expect(handler).toHaveBeenCalledTimes(1);
            expect(handler.mock.calls[0][0].detail.nodeKey).toBe('root');
        });
    });

    it('groups a hub node\'s large same-typeKey neighbor set into one collapsed cluster card instead of rendering every neighbor individually (G4/§26)', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        const fieldNodes = Array.from({ length: 12 }, (_, i) => ({
            nodeKey: `field${i}`,
            typeKey: 'SalesforceMetadata.CustomField',
            typeLabel: 'Field',
            label: `Field ${i}`,
            secondaryKey: `Field ${i}`,
            state: 'Active'
        }));
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }, ...fieldNodes];
        element.edges = fieldNodes.map((n, i) => ({ edgeKey: `e${i}`, typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: n.nodeKey }));
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const nodeElements = element.shadowRoot.querySelectorAll('c-oi-graph-node');
            expect(nodeElements).toHaveLength(2);
            expect(nodeElements[1].label).toBe('12 Field');
            expect(element.shadowRoot.querySelectorAll('.oi-graph-edge-cluster')).toHaveLength(1);
        });
    });

    it('expanding a cluster card reveals its real member nodes without any new fetch, and collapsing re-clusters them', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        const fieldNodes = Array.from({ length: 12 }, (_, i) => ({
            nodeKey: `field${i}`,
            typeKey: 'SalesforceMetadata.CustomField',
            typeLabel: 'Field',
            label: `Field ${i}`,
            secondaryKey: `Field ${i}`,
            state: 'Active'
        }));
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }, ...fieldNodes];
        element.edges = fieldNodes.map((n, i) => ({ edgeKey: `e${i}`, typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'root', targetNodeKey: n.nodeKey }));
        document.body.appendChild(element);
        await flushPromises();

        const clusterNode = element.shadowRoot.querySelectorAll('c-oi-graph-node')[1];
        clusterNode.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: clusterNode.nodeKey } }));
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(13);

        clusterNode.dispatchEvent(new CustomEvent('expandtoggle', { detail: { nodeKey: clusterNode.nodeKey } }));
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(2);
    });

    it('does not overlap same-ring nodes when a ring has more members than fit at the default radius', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        const objectNodes = Array.from({ length: 4 }, (_, i) => ({
            nodeKey: `obj${i}`,
            typeKey: `SalesforceMetadata.CustomObject.${i}`,
            typeLabel: `Object${i}`,
            label: `Object ${i}`,
            secondaryKey: `Object ${i}`,
            state: 'Active'
        }));
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }, ...objectNodes];
        element.edges = objectNodes.map((n, i) => ({ edgeKey: `e${i}`, typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: n.nodeKey }));
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const centers = objectNodes.map((n) => nodeCenter(element, n.nodeKey));
            for (let i = 0; i < centers.length; i++) {
                for (let j = i + 1; j < centers.length; j++) {
                    const distance = Math.hypot(centers[i].cx - centers[j].cx, centers[i].cy - centers[j].cy);
                    expect(distance).toBeGreaterThanOrEqual(150);
                }
            }
        });
    });

    it('relaxes a multi-parent hub node toward the angular midpoint of its real connections instead of an arbitrary slot (GraphUI.md §17/§18 force-relaxation pass, UI-16)', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'a', typeKey: 'T', label: 'A', secondaryKey: 'A', state: 'Active' },
            { nodeKey: 'b', typeKey: 'T', label: 'B', secondaryKey: 'B', state: 'Active' },
            { nodeKey: 'hub', typeKey: 'T', label: 'Hub', secondaryKey: 'Hub', state: 'Active' }
        ];
        element.edges = [
            { edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'a' },
            { edgeKey: 'e2', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'b' },
            { edgeKey: 'e3', typeKey: 'T', sourceNodeKey: 'a', targetNodeKey: 'hub' },
            { edgeKey: 'e4', typeKey: 'T', sourceNodeKey: 'b', targetNodeKey: 'hub' }
        ];
        document.body.appendChild(element);

        return Promise.resolve().then(() => {
            const rootCenter = nodeCenter(element, 'root');
            const angleOf = (key) => {
                const p = nodeCenter(element, key);
                return Math.atan2(p.cy - rootCenter.cy, p.cx - rootCenter.cx);
            };
            const shortestDelta = (from, to) => {
                let delta = (to - from) % (2 * Math.PI);
                if (delta > Math.PI) delta -= 2 * Math.PI;
                if (delta < -Math.PI) delta += 2 * Math.PI;
                return delta;
            };
            const angleA = angleOf('a');
            const angleB = angleOf('b');
            const angleHub = angleOf('hub');

            // Angular betweenness: if hub sits exactly between A and B, the two hops from hub
            // to each parent sum to exactly the A-to-B span; landing outside that span (an
            // arbitrary slot unrelated to either real connection) makes the sum strictly
            // larger. A small tolerance covers floating-point/discretization slack only.
            const spanAB = Math.abs(shortestDelta(angleA, angleB));
            const hubToA = Math.abs(shortestDelta(angleHub, angleA));
            const hubToB = Math.abs(shortestDelta(angleHub, angleB));
            expect(hubToA + hubToB).toBeLessThanOrEqual(spanAB + 0.05);
        });
    });

    describe('"Why is this node here?" — relationship chip and hop distance (this sprint\'s central requirement)', () => {
        function findGraphNode(element, nodeKey) {
            return [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((node) => node.nodeKey === nodeKey);
        }

        it('stamps the neighbour\'s role and its parent\'s label onto a direct child, resolved from the edge\'s registry-provided role labels', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', state: 'Active' },
                { nodeKey: 'trigger1', typeKey: 'SalesforceMetadata.ApexTrigger', typeLabel: 'Apex Trigger', label: 'AccountTrigger', secondaryKey: 'AccountTrigger', state: 'Active' }
            ];
            // EXECUTES_ON travels Trigger -> Object (source=trigger, target=object) — the real
            // scanner convention — with role labels the container would have already resolved
            // from the registry (sourceRoleLabel/targetRoleLabel), exactly as oiGraphExplorer's
            // allCanvasEdges now supplies them.
            element.edges = [
                {
                    edgeKey: 'e1',
                    typeKey: 'SalesforceMetadata.EXECUTES_ON',
                    sourceNodeKey: 'trigger1',
                    targetNodeKey: 'root',
                    sourceRoleLabel: 'Executes On',
                    targetRoleLabel: 'Runs On'
                }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                const triggerNode = findGraphNode(element, 'trigger1');
                expect(triggerNode.relationshipRole).toBe('Executes On');
                expect(triggerNode.relationshipContext).toBe('Account');
                expect(triggerNode.hopDistance).toBe(1);
            });
        });

        it('gives the neighbour the OTHER role when the anchor is on the other side of the edge — proves direction is resolved per edge, not hardcoded', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'trigger1';
            element.nodes = [
                { nodeKey: 'trigger1', typeKey: 'SalesforceMetadata.ApexTrigger', label: 'AccountTrigger', secondaryKey: 'AccountTrigger', state: 'Active' },
                { nodeKey: 'root', typeKey: 'SalesforceMetadata.CustomObject', typeLabel: 'Object', label: 'Account', secondaryKey: 'Account', state: 'Active' }
            ];
            element.edges = [
                {
                    edgeKey: 'e1',
                    typeKey: 'SalesforceMetadata.EXECUTES_ON',
                    sourceNodeKey: 'trigger1',
                    targetNodeKey: 'root',
                    sourceRoleLabel: 'Executes On',
                    targetRoleLabel: 'Runs On'
                }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                const objectNode = findGraphNode(element, 'root');
                expect(objectNode.relationshipRole).toBe('Runs On');
                expect(objectNode.relationshipContext).toBe('AccountTrigger');
            });
        });

        it('derives the relationship field\'s own API name for a field-sourced edge (LOOKUP_TO) from the absorbed field\'s own identity, never from a guess', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'opportunity';
            element.nodes = [
                {
                    nodeKey: 'opportunity',
                    typeKey: 'SalesforceMetadata.CustomObject',
                    label: 'Opportunity',
                    secondaryKey: 'Opportunity',
                    state: 'Active',
                    showFieldList: true
                },
                { nodeKey: 'opportunity.accountid', typeKey: 'SalesforceMetadata.CustomField', label: 'Account Name', secondaryKey: 'Opportunity.AccountId', state: 'Active' },
                {
                    nodeKey: 'account',
                    typeKey: 'SalesforceMetadata.CustomObject',
                    typeLabel: 'Object',
                    label: 'Account',
                    secondaryKey: 'Account',
                    state: 'Active',
                    showFieldList: true
                }
            ];
            element.edges = [
                // Field membership: absorbs opportunity.accountid into the Opportunity card.
                { edgeKey: 'e-field', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'opportunity', targetNodeKey: 'opportunity.accountid', isFieldMembership: true },
                // LOOKUP_TO travels FIELD -> referenced object (source=field), per OI_FieldScanner's real convention.
                {
                    edgeKey: 'e-lookup',
                    typeKey: 'SalesforceMetadata.LOOKUP_TO',
                    sourceNodeKey: 'opportunity.accountid',
                    targetNodeKey: 'account',
                    sourceRoleLabel: 'References',
                    targetRoleLabel: 'Referenced By'
                }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                const accountCard = [...element.shadowRoot.querySelectorAll('c-oi-schema-object-card')].find((card) => card.nodeKey === 'account');
                expect(accountCard.relationshipRole).toBe('Referenced By');
                expect(accountCard.relationshipContext).toBe('Opportunity');
                expect(accountCard.relationshipVia).toBe('AccountId');
            });
        });

        it('marks a node beyond one hop with its real distance, so it never reads as if directly related to the centre', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'mid', typeKey: 'T', label: 'Mid', secondaryKey: 'Mid', state: 'Active' },
                { nodeKey: 'far', typeKey: 'T', label: 'Far', secondaryKey: 'Far', state: 'Active' }
            ];
            element.edges = [
                { edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'mid', sourceRoleLabel: 'Related To', targetRoleLabel: 'Related To' },
                { edgeKey: 'e2', typeKey: 'T', sourceNodeKey: 'mid', targetNodeKey: 'far', sourceRoleLabel: 'Related To', targetRoleLabel: 'Related To' }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                expect(findGraphNode(element, 'mid').hopDistance).toBe(1);
                expect(findGraphNode(element, 'far').hopDistance).toBe(2);
            });
        });
    });

    describe('Visible edge labels and primary/secondary hierarchy', () => {
        it('shows a concise, registry-resolved label on a direct/primary edge — never the raw typeKey', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [
                { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: 'child', displayLabel: 'Lookup' }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                const label = element.shadowRoot.querySelector('[data-id="graph-edge-label"]');
                expect(label.textContent).toBe('Lookup');
                expect(label.textContent).not.toContain('SalesforceMetadata.');
            });
        });

        it('includes the via-field in the label when one is known ("AccountId · Lookup")', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [
                { edgeKey: 'e1', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'root', targetNodeKey: 'child', displayLabel: 'Lookup', viaFieldApiName: 'AccountId' }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                expect(element.shadowRoot.querySelector('[data-id="graph-edge-label"]').textContent).toBe('AccountId · Lookup');
            });
        });

        it('renders no visible label on a secondary (non-tree) edge by default, keeping the primary structure the visually dominant thing', () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'a', typeKey: 'T', label: 'A', secondaryKey: 'A', state: 'Active' },
                { nodeKey: 'b', typeKey: 'T', label: 'B', secondaryKey: 'B', state: 'Active' },
                { nodeKey: 'hub', typeKey: 'T', label: 'Hub', secondaryKey: 'Hub', state: 'Active' }
            ];
            element.edges = [
                { edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'a', displayLabel: 'Rel' },
                { edgeKey: 'e2', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'b', displayLabel: 'Rel' },
                { edgeKey: 'e3', typeKey: 'T', sourceNodeKey: 'a', targetNodeKey: 'hub', displayLabel: 'Rel' },
                { edgeKey: 'e4', typeKey: 'T', sourceNodeKey: 'b', targetNodeKey: 'hub', displayLabel: 'Rel' }
            ];
            document.body.appendChild(element);

            return Promise.resolve().then(() => {
                const labels = [...element.shadowRoot.querySelectorAll('[data-id="graph-edge-label"]')].map((el) => el.textContent);
                // Exactly one of the two edges into "hub" is the BFS tree edge (primary); the
                // other is secondary and must render with empty label text by default.
                const nonEmpty = labels.filter((text) => text);
                expect(nonEmpty.length).toBeLessThan(labels.length);
            });
        });
    });

    describe('Path-to-centre highlight (hover/selection)', () => {
        function buildChain(element) {
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'mid', typeKey: 'T', label: 'Mid', secondaryKey: 'Mid', state: 'Active' },
                { nodeKey: 'far', typeKey: 'T', label: 'Far', secondaryKey: 'Far', state: 'Active' },
                { nodeKey: 'unrelated', typeKey: 'T', label: 'Unrelated', secondaryKey: 'Unrelated', state: 'Active' }
            ];
            element.edges = [
                { edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'mid' },
                { edgeKey: 'e2', typeKey: 'T', sourceNodeKey: 'mid', targetNodeKey: 'far' },
                { edgeKey: 'e3', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'unrelated' }
            ];
        }

        it('highlights the full path back to the centre on hover and dims everything off that path', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            buildChain(element);
            document.body.appendChild(element);
            await Promise.resolve();

            const farForeignObject = element.shadowRoot.querySelector('[data-node-key="far"]');
            farForeignObject.dispatchEvent(new CustomEvent('mouseenter'));
            await Promise.resolve();

            const onPath = ['root', 'mid', 'far'];
            for (const key of onPath) {
                const node = [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((n) => n.nodeKey === key);
                expect(node.isOnActivePath).toBe(true);
                expect(node.isDimmed).toBe(false);
            }
            const unrelated = [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((n) => n.nodeKey === 'unrelated');
            expect(unrelated.isOnActivePath).toBe(false);
            expect(unrelated.isDimmed).toBe(true);
        });

        it('clears the highlight back to no dimming once the pointer leaves and nothing is selected', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            buildChain(element);
            document.body.appendChild(element);
            await Promise.resolve();

            const farForeignObject = element.shadowRoot.querySelector('[data-node-key="far"]');
            farForeignObject.dispatchEvent(new CustomEvent('mouseenter'));
            await Promise.resolve();
            farForeignObject.dispatchEvent(new CustomEvent('mouseleave'));
            await Promise.resolve();

            /** No highlight active means renderableNodes returns nodes unchanged — isDimmed is undefined, not an explicit false. Either reads as "not dimmed" to the rendering component, so falsy is the correct assertion. */
            const unrelated = [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((n) => n.nodeKey === 'unrelated');
            expect(unrelated.isDimmed).toBeFalsy();
        });

        it('keeps the highlight on the selected node\'s path after the pointer leaves, rather than clearing to nothing', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            buildChain(element);
            element.selectedNodeKey = 'far';
            document.body.appendChild(element);
            await Promise.resolve();

            const unrelated = [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((n) => n.nodeKey === 'unrelated');
            expect(unrelated.isDimmed).toBe(true);
            const mid = [...element.shadowRoot.querySelectorAll('c-oi-graph-node')].find((n) => n.nodeKey === 'mid');
            expect(mid.isOnActivePath).toBe(true);
        });
    });

    it('dragging a node moves it and suppresses the resulting click-to-select', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);
        await flushPromises();

        const before = nodeCenter(element, 'child');
        const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
        const selectHandler = jest.fn();
        element.addEventListener('select', selectHandler);

        foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 100, clientY: 100 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 140, clientY: 100 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
        await flushPromises();

        const after = nodeCenter(element, 'child');
        expect(after.cx).toBeCloseTo(before.cx + 40, 0);

        const childNode = element.shadowRoot.querySelectorAll('c-oi-graph-node')[1];
        childNode.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'child' } }));
        await flushPromises();
        expect(selectHandler).not.toHaveBeenCalled();
    });

    it('coalesces many rapid pointermove events during a pan into a single update per animation frame, rather than one per event (the fix for canvas lag on large graphs)', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        await flushPromises();

        const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
        const before = svg.getAttribute('viewBox');

        svg.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
        // Ten rapid moves in the same synchronous tick — a real fast mouse gesture easily fires this many before a single frame paints.
        for (let i = 1; i <= 10; i++) {
            svg.dispatchEvent(new MouseEvent('pointermove', { clientX: i * 5, clientY: 0 }));
        }

        // Nothing should have applied yet — only a single frame flush is scheduled, and no frame has ticked.
        expect(svg.getAttribute('viewBox')).toBe(before);

        await wait(50);

        // Once the frame ticks, the cumulative movement (50px total, matching the sum of all ten 5px deltas) must be reflected in one shot.
        const [afterX] = svg.getAttribute('viewBox').split(' ').map(Number);
        const [beforeX] = before.split(' ').map(Number);
        expect(beforeX - afterX).toBeCloseTo(50, 0);

        svg.dispatchEvent(new MouseEvent('pointerup', {}));
    });

    it('translates a child expandtoggle into expand when the node is not yet expanded, and collapse when it is', () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active', isExpanded: false }];
        element.edges = [];
        document.body.appendChild(element);
        const expandHandler = jest.fn();
        const collapseHandler = jest.fn();
        element.addEventListener('expand', expandHandler);
        element.addEventListener('collapse', collapseHandler);

        return Promise.resolve().then(async () => {
            const childNode = element.shadowRoot.querySelector('c-oi-graph-node');
            childNode.dispatchEvent(new CustomEvent('expandtoggle', { detail: { nodeKey: 'root' } }));
            await flushPromises();
            expect(expandHandler).toHaveBeenCalledTimes(1);
            expect(collapseHandler).not.toHaveBeenCalled();
        });
    });

    it('the zoom-in control smoothly animates to a higher zoom percentage, and zoom-out to a lower one', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent).toBe('100%');

        element.shadowRoot.querySelector('[data-id="zoom-in-button"]').click();
        await wait(300);
        const afterZoomIn = element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent;
        expect(afterZoomIn).not.toBe('100%');
        expect(parseInt(afterZoomIn, 10)).toBeGreaterThan(100);

        element.shadowRoot.querySelector('[data-id="zoom-out-button"]').click();
        element.shadowRoot.querySelector('[data-id="zoom-out-button"]').click();
        await wait(300);
        const afterZoomOut = element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent;
        expect(parseInt(afterZoomOut, 10)).toBeLessThan(parseInt(afterZoomIn, 10));
    });

    it('the reset-view control animates back to 100% zoom', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="zoom-in-button"]').click();
        await wait(300);
        element.shadowRoot.querySelector('[data-id="reset-view-button"]').click();
        await wait(300);

        expect(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent).toBe('100%');
    });

    it('fit-to-screen zooms out to bring every currently-loaded node into view', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);
        await flushPromises();

        // Drag the child far away so the bounding box of everything currently loaded becomes much wider than the default viewport — fit-to-screen must zoom out to compensate.
        const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
        foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 2000, clientY: 0 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
        await flushPromises();

        element.shadowRoot.querySelector('[data-id="fit-to-screen-button"]').click();
        await wait(300);

        const zoomAfter = parseInt(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent, 10);
        expect(zoomAfter).toBeLessThan(100);
    });

    it('center-on-selected-node recenters the viewport on the selected node without changing zoom, and is disabled when nothing is selected', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="center-on-selected-button"]').disabled).toBe(true);

        element.selectedNodeKey = 'child';
        await flushPromises();
        expect(element.shadowRoot.querySelector('[data-id="center-on-selected-button"]').disabled).toBe(false);

        const childCenterBefore = nodeCenter(element, 'child');
        element.shadowRoot.querySelector('[data-id="center-on-selected-button"]').click();
        await wait(300);

        const [x, y, width, height] = element.shadowRoot.querySelector('[data-id="canvas-svg"]').getAttribute('viewBox').split(' ').map(Number);
        expect(x + width / 2).toBeCloseTo(childCenterBefore.cx, 0);
        expect(y + height / 2).toBeCloseTo(childCenterBefore.cy, 0);
        expect(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent).toBe('100%');
    });

    it('reset-layout is disabled until a node has been manually dragged, then discards every manual drag and snaps back to the computed position', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="reset-layout-button"]').disabled).toBe(true);

        const before = nodeCenter(element, 'child');
        const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
        foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 50, clientY: 0 }));
        element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
        await flushPromises();

        const dragged = nodeCenter(element, 'child');
        expect(dragged.cx).toBeCloseTo(before.cx + 50, 0);
        expect(element.shadowRoot.querySelector('[data-id="reset-layout-button"]').disabled).toBe(false);

        element.shadowRoot.querySelector('[data-id="reset-layout-button"]').click();
        await flushPromises();

        const afterReset = nodeCenter(element, 'child');
        expect(afterReset.cx).toBeCloseTo(before.cx, 0);
        expect(element.shadowRoot.querySelector('[data-id="reset-layout-button"]').disabled).toBe(true);
    });

    it('scrolling the wheel over a specific point keeps that same world point under the cursor after the zoom changes (cursor-anchored zoom)', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        await flushPromises();

        const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
        svg.getBoundingClientRect = jest.fn().mockReturnValue({ left: 0, top: 0, width: 900, height: 600 });

        // Cursor near the right edge (fracX ≈ 0.944, fracY = 0.5) — a naive center-anchored
        // zoom would leave viewBox.x ≈ 48.2 (900/2 shrinking symmetrically); cursor-anchored
        // zoom must instead pull viewBox.x toward the cursor side, landing around 91.
        svg.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, clientX: 850, clientY: 300 }));
        await flushPromises();

        const [viewBoxX, , viewBoxWidth] = svg.getAttribute('viewBox').split(' ').map(Number);
        expect(viewBoxWidth).toBeLessThan(900);
        expect(viewBoxX).toBeGreaterThan(70);
        expect(viewBoxX).toBeLessThan(110);
    });

    it('renders a mini-map overview once more than one node is positioned, with a viewport rectangle', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [
            { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
            { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
        ];
        element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="minimap"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="minimap-viewport-rect"]')).not.toBeNull();
        expect(element.shadowRoot.querySelectorAll('[data-id="minimap-dot"]')).toHaveLength(2);
    });

    it('does not render a mini-map for a single-node graph (nothing meaningful to overview)', async () => {
        const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
        element.centerNodeKey = 'root';
        element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
        element.edges = [];
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="minimap"]')).toBeNull();
    });

    describe('Google-Maps-style background glide, momentum panning, and double-click zoom', () => {
        it('sets the real SVG viewBox attribute (not a hyphenated view-box lookalike the browser ignores) — the actual root cause behind "nothing moves except the background dots"', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            // LWC's template compiler only camelCases an SVG attribute (viewBox, markerWidth, refX, ...)
            // when the template spells it as one lowercase word with no hyphen; `view-box` compiles to a
            // literal, meaningless attribute the SVG renderer never reads. Guard both directions at once.
            expect(svg.hasAttribute('view-box')).toBe(false);
            expect(svg.getAttribute('viewBox')).toMatch(/^-?\d+(\.\d+)? -?\d+(\.\d+)? \d+(\.\d+)? \d+(\.\d+)?$/);

            const before = svg.getAttribute('viewBox');
            svg.dispatchEvent(new WheelEvent('wheel', { deltaY: -100, clientX: 450, clientY: 300 }));
            await flushPromises();
            expect(svg.getAttribute('viewBox')).not.toBe(before);
        });

        it('sets the arrow marker\'s real markerWidth/markerHeight/refX/refY attributes (not hyphenated lookalikes), so the arrowhead renders at its intended size and anchor instead of the SVG default 3x3/0,0', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const marker = element.shadowRoot.querySelector('[data-id="canvas-arrow-marker"]');
            expect(marker.hasAttribute('marker-width')).toBe(false);
            expect(marker.getAttribute('markerWidth')).toBe('8');
            expect(marker.getAttribute('markerHeight')).toBe('8');
            expect(marker.getAttribute('refX')).toBe('6');
            expect(marker.getAttribute('refY')).toBe('4');
        });

        it('the grid backdrop actually paints (LWC synthetic-shadow id-scoping bug fixed) — its fill references whatever id the pattern element actually has, not a stale hardcoded string', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const pattern = element.shadowRoot.querySelector('[data-id="canvas-grid-pattern"]');
            const gridRect = element.shadowRoot.querySelector('[data-id="canvas-grid-rect"]');
            expect(pattern.id).toBeTruthy();
            expect(gridRect.getAttribute('fill')).toBe(`url(#${pattern.id})`);
        });

        it('every rendered edge\'s arrowhead references whatever id the marker element actually has, not a stale hardcoded string', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
            document.body.appendChild(element);
            await flushPromises();

            const marker = element.shadowRoot.querySelector('[data-id="canvas-arrow-marker"]');
            const edgePath = element.shadowRoot.querySelector('[data-id="graph-edge-path"]');
            expect(marker.id).toBeTruthy();
            expect(edgePath.getAttribute('marker-end')).toBe(`url(#${marker.id})`);
        });

        it('the grid tile shrinks in world-units as you zoom in, and grows as you zoom out — keeping its ON-SCREEN size constant instead of becoming sub-pixel and invisible at low zoom (the actual root cause behind "the background looks like it never moves" when zoomed far out)', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const pattern = element.shadowRoot.querySelector('[data-id="canvas-grid-pattern"]');
            const tileSizeAtDefaultZoom = Number(pattern.getAttribute('width'));

            element.shadowRoot.querySelector('[data-id="zoom-in-button"]').click();
            await wait(300);
            const tileSizeZoomedIn = Number(element.shadowRoot.querySelector('[data-id="canvas-grid-pattern"]').getAttribute('width'));
            expect(tileSizeZoomedIn).toBeLessThan(tileSizeAtDefaultZoom);

            // Back-to-back clicks each read `this.zoom` before the prior click's animation has applied (the same reason the existing zoom-button test only asserts a relative, not exact, decrement) — reset to a known baseline first so this zoom-out's target is unambiguous.
            element.shadowRoot.querySelector('[data-id="reset-view-button"]').click();
            await wait(300);
            element.shadowRoot.querySelector('[data-id="zoom-out-button"]').click();
            await wait(300);
            const tileSizeZoomedOut = Number(element.shadowRoot.querySelector('[data-id="canvas-grid-pattern"]').getAttribute('width'));
            expect(tileSizeZoomedOut).toBeGreaterThan(tileSizeAtDefaultZoom);
        });

        it('a fast drag-release ("flick") keeps gliding after pointerup instead of stopping dead, then settles to a stop on its own', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            svg.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            await wait(20);
            svg.dispatchEvent(new MouseEvent('pointermove', { clientX: 10, clientY: 0 }));
            const viewBoxAtRelease = svg.getAttribute('viewBox');
            svg.dispatchEvent(new MouseEvent('pointerup', {}));

            // Immediately after release the flick's own delta has already been flushed; momentum only shows up on subsequent frames.
            await wait(30);
            const viewBoxMidCoast = svg.getAttribute('viewBox');
            expect(viewBoxMidCoast).not.toBe(viewBoxAtRelease);

            // The constant-deceleration coast is tuned to settle within ~150ms for this test's release speed — well past that, it must have stopped moving.
            await wait(300);
            const viewBoxA = svg.getAttribute('viewBox');
            await wait(100);
            const viewBoxB = svg.getAttribute('viewBox');
            expect(viewBoxB).toBe(viewBoxA);
        });

        it('a slow, deliberate drag-release does not glide at all — momentum is reserved for genuine flicks, not every pan', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            svg.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            await wait(100);
            svg.dispatchEvent(new MouseEvent('pointermove', { clientX: 2, clientY: 0 }));
            svg.dispatchEvent(new MouseEvent('pointerup', {}));

            // The drag's own final flush is synchronous in JS, but the resulting DOM re-render is async — let it land before taking the "settled" baseline, or this would mistake that render lag for momentum.
            await flushPromises();
            const viewBoxAtRelease = svg.getAttribute('viewBox');
            await wait(80);
            expect(svg.getAttribute('viewBox')).toBe(viewBoxAtRelease);
        });

        it('starting a new zoom action cancels an in-flight momentum coast, rather than fighting it for control of the viewport', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            svg.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            await wait(20);
            svg.dispatchEvent(new MouseEvent('pointermove', { clientX: 10, clientY: 0 }));
            svg.dispatchEvent(new MouseEvent('pointerup', {}));
            await wait(10);

            // A pure zoom-to-center leaves the viewport's world-space center (x + width/2) exactly fixed — if momentum were still fighting it, panX would keep drifting underneath the zoom and the center would shift.
            const [xBefore, , widthBefore] = svg.getAttribute('viewBox').split(' ').map(Number);
            const centerBefore = xBefore + widthBefore / 2;

            element.shadowRoot.querySelector('[data-id="zoom-in-button"]').click();
            await wait(300);

            const [xAfter, , widthAfter] = svg.getAttribute('viewBox').split(' ').map(Number);
            const centerAfter = xAfter + widthAfter / 2;
            expect(centerAfter).toBeCloseTo(centerBefore, 0);
        });

        it('double-clicking the empty canvas smoothly zooms in anchored at the click point', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            svg.getBoundingClientRect = jest.fn().mockReturnValue({ left: 0, top: 0, width: 900, height: 600 });

            expect(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent).toBe('100%');
            svg.dispatchEvent(new MouseEvent('dblclick', { clientX: 450, clientY: 300, bubbles: true }));
            await wait(300);

            const zoomAfter = parseInt(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent, 10);
            expect(zoomAfter).toBeGreaterThan(100);
        });

        it('double-clicking a node itself does not trigger the canvas double-click-to-zoom (it is a node interaction target, not "zoom here")', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const foreignObject = element.shadowRoot.querySelector('[data-node-key="root"]');
            foreignObject.dispatchEvent(new MouseEvent('dblclick', { clientX: 10, clientY: 10, bubbles: true }));
            await wait(300);

            expect(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent).toBe('100%');
        });
    });

    describe('Schema Builder field absorption (GraphUI.md §20 addendum)', () => {
        function accountWithFields(fieldCount) {
            const account = { nodeKey: 'account', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', showFieldList: true };
            const fields = Array.from({ length: fieldCount }, (_, i) => ({
                nodeKey: `f${i}`,
                typeKey: 'SalesforceMetadata.CustomField',
                typeLabel: 'Field',
                label: `Field_${i}__c`,
                secondaryKey: `Field_${i}__c`,
                iconName: 'standard:text'
            }));
            const membershipEdges = fields.map((f, i) => ({
                edgeKey: `hf${i}`,
                typeKey: 'SalesforceMetadata.HAS_FIELD',
                sourceNodeKey: 'account',
                targetNodeKey: f.nodeKey,
                isFieldMembership: true
            }));
            return { account, fields, membershipEdges };
        }

        it('absorbs field nodes into their owning object\'s schema card instead of rendering them as separate pills, when the owner\'s showFieldList and the edge\'s isFieldMembership both opt in', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'account';
            const { account, fields, membershipEdges } = accountWithFields(3);
            element.nodes = [account, ...fields];
            element.edges = membershipEdges;
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelectorAll('c-oi-schema-object-card')).toHaveLength(1);
            expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(0);
            const card = element.shadowRoot.querySelector('c-oi-schema-object-card');
            expect(card.fields).toHaveLength(3);
            expect(card.fields.map((f) => f.nodeKey).sort()).toEqual(['f0', 'f1', 'f2']);
        });

        it('does NOT absorb a field whose owner lacks showFieldList — legacy/unregistered fixtures render exactly as before this feature existed', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'account';
            const account = { nodeKey: 'account', typeKey: 'T', label: 'Account', secondaryKey: 'Account' };
            const field = { nodeKey: 'f0', typeKey: 'SalesforceMetadata.CustomField', label: 'Field_0__c', secondaryKey: 'Field_0__c' };
            element.nodes = [account, field];
            element.edges = [{ edgeKey: 'hf0', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'account', targetNodeKey: 'f0', isFieldMembership: true }];
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelectorAll('c-oi-schema-object-card')).toHaveLength(0);
            expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(2);
        });

        it('re-anchors a relationship edge whose source is an absorbed field onto the field\'s owning object, so the line connects card-to-card like native Schema Builder', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'account';
            const account = { nodeKey: 'account', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', showFieldList: true };
            const field = { nodeKey: 'ownerId', typeKey: 'SalesforceMetadata.CustomField', label: 'OwnerId', secondaryKey: 'OwnerId' };
            const contact = { nodeKey: 'contact', typeKey: 'SalesforceMetadata.CustomObject', label: 'Contact', secondaryKey: 'Contact' };
            element.nodes = [account, field, contact];
            element.edges = [
                { edgeKey: 'hf0', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'account', targetNodeKey: 'ownerId', isFieldMembership: true },
                { edgeKey: 'lookup0', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'ownerId', targetNodeKey: 'contact', lineStyle: 'dashed' }
            ];
            document.body.appendChild(element);
            await flushPromises();

            // Exactly one line: the membership edge is absorbed (never drawn), the lookup is re-anchored account->contact.
            const edgePaths = element.shadowRoot.querySelectorAll('.oi-graph-edge');
            expect(edgePaths).toHaveLength(1);

            const accountCenter = nodeCenter(element, 'account');
            const contactCenter = nodeCenter(element, 'contact');
            const d = edgePaths[0].getAttribute('d');
            const match = d.match(/^M([-\d.]+),([-\d.]+) Q[-\d.,]+ ([-\d.]+),([-\d.]+)$/);
            expect(match).not.toBeNull();
            const [, x1, y1, x2, y2] = match.map(Number);
            expect(x1).toBeCloseTo(accountCenter.cx, 0);
            expect(y1).toBeCloseTo(accountCenter.cy, 0);
            expect(x2).toBeCloseTo(contactCenter.cx, 0);
            expect(y2).toBeCloseTo(contactCenter.cy, 0);
        });

        it('drops a field\'s relationship edge entirely when it self-references its own owning object, rather than rendering a degenerate zero-length line', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'account';
            const account = { nodeKey: 'account', typeKey: 'SalesforceMetadata.CustomObject', label: 'Account', secondaryKey: 'Account', showFieldList: true };
            const parentField = { nodeKey: 'parentId', typeKey: 'SalesforceMetadata.CustomField', label: 'ParentId', secondaryKey: 'ParentId' };
            element.nodes = [account, parentField];
            element.edges = [
                { edgeKey: 'hf0', typeKey: 'SalesforceMetadata.HAS_FIELD', sourceNodeKey: 'account', targetNodeKey: 'parentId', isFieldMembership: true },
                { edgeKey: 'lookup0', typeKey: 'SalesforceMetadata.LOOKUP_TO', sourceNodeKey: 'parentId', targetNodeKey: 'account', lineStyle: 'dashed' }
            ];
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelectorAll('.oi-graph-edge')).toHaveLength(0);
            expect(element.shadowRoot.querySelectorAll('c-oi-schema-object-card')).toHaveLength(1);
        });

        it('propagates the schema card\'s own select event and expand toggle exactly like any other node (a field click no longer exists as a separate row — see oiSchemaObjectCard\'s own tests)', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'account';
            const { account, fields, membershipEdges } = accountWithFields(1);
            element.nodes = [{ ...account, isExpanded: false }, ...fields];
            element.edges = membershipEdges;
            document.body.appendChild(element);
            await flushPromises();

            const selectHandler = jest.fn();
            const expandHandler = jest.fn();
            element.addEventListener('select', selectHandler);
            element.addEventListener('expand', expandHandler);

            const card = element.shadowRoot.querySelector('c-oi-schema-object-card');
            card.dispatchEvent(new CustomEvent('select', { detail: { nodeKey: 'account' } }));
            card.dispatchEvent(new CustomEvent('expandtoggle', { detail: { nodeKey: 'account' } }));
            await flushPromises();

            expect(selectHandler).toHaveBeenCalledTimes(1);
            expect(selectHandler.mock.calls[0][0].detail.nodeKey).toBe('account');
            expect(expandHandler).toHaveBeenCalledTimes(1);
            expect(expandHandler.mock.calls[0][0].detail.nodeKey).toBe('account');
        });

        it('a schema card\'s footprint is fixed regardless of how many fields the object has — it no longer grows with field count (Hierarchy Visualizer field-browser sprint)', async () => {
            const smallElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            smallElement.centerNodeKey = 'account';
            const small = accountWithFields(1);
            smallElement.nodes = [small.account, ...small.fields];
            smallElement.edges = small.membershipEdges;
            document.body.appendChild(smallElement);
            await flushPromises();
            const smallHeight = Number(smallElement.shadowRoot.querySelector('[data-node-key="account"]').getAttribute('height'));

            const largeElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            largeElement.centerNodeKey = 'account';
            const large = accountWithFields(40);
            largeElement.nodes = [large.account, ...large.fields];
            largeElement.edges = large.membershipEdges;
            document.body.appendChild(largeElement);
            await flushPromises();
            const largeHeight = Number(largeElement.shadowRoot.querySelector('[data-node-key="account"]').getAttribute('height'));

            expect(largeHeight).toBe(smallHeight);
        });

        it('centering directly on an absorbed field routes the ring-0 (dead-center) position to its owning object\'s card, matching Schema Builder\'s object-is-the-atomic-node model', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'f0';
            const { account, fields, membershipEdges } = accountWithFields(1);
            element.nodes = [account, ...fields];
            element.edges = membershipEdges;
            document.body.appendChild(element);
            await flushPromises();

            const card = element.shadowRoot.querySelector('c-oi-schema-object-card');
            expect(card).not.toBeNull();
            expect(card.nodeKey).toBe('account');
            const center = nodeCenter(element, 'account');
            expect(center.cx).toBeCloseTo(450, 0);
            expect(center.cy).toBeCloseTo(300, 0);
        });
    });

    describe('Dynamic node sizing (label-length-aware footprint, not a single fixed box for every node)', () => {
        it('a short label gets a narrower box than a long label — width scales with the label, not a single fixed constant for every plain node', async () => {
            const shortElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            shortElement.centerNodeKey = 'root';
            shortElement.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'A', secondaryKey: 'A', state: 'Active' }];
            shortElement.edges = [];
            document.body.appendChild(shortElement);
            await flushPromises();
            const shortWidth = Number(shortElement.shadowRoot.querySelector('[data-node-key="root"]').getAttribute('width'));

            const longElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            longElement.centerNodeKey = 'root';
            longElement.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'A Much Longer Node Label Than The Other One', secondaryKey: 'Long', state: 'Active' }];
            longElement.edges = [];
            document.body.appendChild(longElement);
            await flushPromises();
            const longWidth = Number(longElement.shadowRoot.querySelector('[data-node-key="root"]').getAttribute('width'));

            expect(longWidth).toBeGreaterThan(shortWidth);
        });

        it('an extremely long label is clamped to a maximum width rather than growing unbounded — CSS ellipsis (oiGraphNode.css) remains the backstop beyond that point', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'X'.repeat(200), secondaryKey: 'Root', state: 'Active' }];
            element.edges = [];
            document.body.appendChild(element);
            await flushPromises();

            const width = Number(element.shadowRoot.querySelector('[data-node-key="root"]').getAttribute('width'));
            expect(width).toBeLessThanOrEqual(360);
        });

        it('a secondaryKey longer than the label still widens the box — a record node\'s "Contact 003xx..." caption must not be forced to truncate just because the record Name itself happens to be short', async () => {
            const shortBothElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            shortBothElement.centerNodeKey = 'root';
            shortBothElement.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Jo', secondaryKey: 'Jo', state: 'Active' }];
            shortBothElement.edges = [];
            document.body.appendChild(shortBothElement);
            await flushPromises();
            const narrowWidth = Number(shortBothElement.shadowRoot.querySelector('[data-node-key="root"]').getAttribute('width'));

            const longSecondaryElement = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            longSecondaryElement.centerNodeKey = 'root';
            longSecondaryElement.nodes = [{ nodeKey: 'root', typeKey: 'T', label: 'Jo', secondaryKey: 'Contact 003xxxxxxxxxxxxxAB', state: 'Active' }];
            longSecondaryElement.edges = [];
            document.body.appendChild(longSecondaryElement);
            await flushPromises();
            const widerWidth = Number(longSecondaryElement.shadowRoot.querySelector('[data-node-key="root"]').getAttribute('width'));

            expect(widerWidth).toBeGreaterThan(narrowWidth);
        });
    });

    describe('Viewport virtualization (ADR-0020, GraphUI.md §4/§26)', () => {
        it('unmounts a node\'s real DOM element once dragged far outside the viewport-plus-margin window, while its edge to the still-visible root keeps rendering', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
            document.body.appendChild(element);
            await flushPromises();

            expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(2);
            expect(element.shadowRoot.querySelectorAll('.oi-graph-edge')).toHaveLength(1);

            // At zoom 1 the virtualization window is the 900x600 viewport plus one full
            // viewport-width/height of margin on every side (2700x1800 total) — 5000 world
            // units away is well outside it in either direction.
            const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
            foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 5000, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
            await flushPromises();

            // The far-off child is unmounted (no longer a rendered child component at all), not just visually hidden.
            expect(element.shadowRoot.querySelectorAll('c-oi-graph-node')).toHaveLength(1);
            expect(element.shadowRoot.querySelector('[data-node-key="child"]')).toBeNull();

            // The edge toward it still renders — one endpoint (root) remains on screen, so per the
            // "either endpoint" rule the line stays visible right up to the margin rather than
            // vanishing mid-canvas the instant its own node is culled.
            expect(element.shadowRoot.querySelectorAll('.oi-graph-edge')).toHaveLength(1);
        });

        it('does not shrink the mini-map or fit-to-screen bounds when a node is virtualized out of the DOM — those consumers reason over the full working set, not just what is currently rendered', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
            document.body.appendChild(element);
            await flushPromises();

            const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
            foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 5000, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-node-key="child"]')).toBeNull();

            // The mini-map still shows both dots even though one of them has no real DOM element right now.
            expect(element.shadowRoot.querySelectorAll('[data-id="minimap-dot"]')).toHaveLength(2);

            // Fit-to-screen still has to zoom out dramatically to fit a node 5000 world units away.
            element.shadowRoot.querySelector('[data-id="fit-to-screen-button"]').click();
            await wait(300);
            const zoomAfter = parseInt(element.shadowRoot.querySelector('[data-id="zoom-percent"]').textContent, 10);
            expect(zoomAfter).toBeLessThan(50);
        });

        it('remounts a node once panning brings its world position back inside the viewport-plus-margin window', async () => {
            const element = createElement('c-oi-graph-canvas', { is: OiGraphCanvas });
            element.centerNodeKey = 'root';
            element.nodes = [
                { nodeKey: 'root', typeKey: 'T', label: 'Root', secondaryKey: 'Root', state: 'Active' },
                { nodeKey: 'child', typeKey: 'T', label: 'Child', secondaryKey: 'Child', state: 'Active' }
            ];
            element.edges = [{ edgeKey: 'e1', typeKey: 'T', sourceNodeKey: 'root', targetNodeKey: 'child' }];
            document.body.appendChild(element);
            await flushPromises();

            const foreignObject = element.shadowRoot.querySelector('[data-node-key="child"]');
            foreignObject.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointermove', { clientX: 5000, clientY: 0 }));
            element.shadowRoot.querySelector('[data-id="canvas-svg"]').dispatchEvent(new MouseEvent('pointerup', {}));
            await flushPromises();
            expect(element.shadowRoot.querySelector('[data-node-key="child"]')).toBeNull();

            // Pan the viewport itself toward where the child now sits — dragging the background
            // left (negative clientX delta) shifts the visible world-space window to the right,
            // the same direction the child was dragged, until it falls back inside the window.
            const svg = element.shadowRoot.querySelector('[data-id="canvas-svg"]');
            svg.dispatchEvent(new MouseEvent('pointerdown', { clientX: 0, clientY: 0 }));
            svg.dispatchEvent(new MouseEvent('pointermove', { clientX: -5000, clientY: 0 }));
            svg.dispatchEvent(new MouseEvent('pointerup', {}));
            await flushPromises();

            expect(element.shadowRoot.querySelector('[data-node-key="child"]')).not.toBeNull();
        });
    });
});
