const assert = require('node:assert/strict');
const {weightItems, layout} = require('../resources/web/treemap.js');

const items = [455, 64, 44, 31, 15, 8, 4, 3, 2, 1, .1].map((gib, index) => ({
    name: String(index), path: '/'+index, bytes: gib * 1024**3
}));
const original = structuredClone(items);
const area = node => node.rect.w * node.rect.h;
const actual = layout(weightItems(items, 'actual'), 0, 0, 700, 520);
const balanced = layout(weightItems(items, 'balanced'), 0, 0, 700, 520);
assert.deepEqual(items, original, 'Scaling must not alter measured data');
const sum = items.reduce((total, item) => total + item.bytes, 0);
for (const node of actual) {
    assert.ok(Math.abs(area(node)/(700*520) - node.bytes/sum) < 1e-10, 'Actual mode must be proportional to bytes');
}
assert.ok(area(balanced.at(-1)) > area(actual.at(-1))*20, 'Small entries need a meaningful visibility improvement');
for (const nodes of [actual, balanced]) {
    assert.ok(Math.abs(nodes.reduce((total, node) => total + area(node), 0)-700*520)<1e-6);
    for (const node of nodes) {
        const r = node.rect;
        assert.ok(r.w > 0 && r.h > 0 && r.x >= 0 && r.y >= 0 && r.x+r.w <= 700+1e-8 && r.y+r.h <= 520+1e-8);
        assert.equal(node.bytes, original.find(item=>item.path===node.path).bytes);
    }
    for(let i=0; i<nodes.length; i++) for(let j=i+1; j<nodes.length; j++) {
        const a=nodes[i].rect, b=nodes[j].rect;
        const overlapX=Math.min(a.x+a.w,b.x+b.w)-Math.max(a.x,b.x);
        const overlapY=Math.min(a.y+a.h,b.y+b.h)-Math.max(a.y,b.y);
        assert.ok(overlapX < 1e-8 || overlapY < 1e-8, 'Tiles must not overlap');
    }
}
assert.deepEqual(layout(weightItems([]),0,0,700,520), []);
assert.equal(weightItems([{bytes:0},{bytes:-1},{bytes:NaN}]).length,0);
const extreme=layout(weightItems([{bytes:1e15},{bytes:1}]),0,0,700,520);
assert.ok(area(extreme[1])/(700*520) >= 1/8, 'The navigation floor must hold even for an extreme size gap');
console.log('Treemap: truthful actual areas, visible small entries, unchanged byte values, bounds, coverage and overlap checks passed.');
