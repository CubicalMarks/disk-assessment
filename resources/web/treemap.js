'use strict';

// Areas in balanced mode aid navigation; bytes remain the source of every label.
const Treemap = (() => {
    function weightItems(items, scale = 'balanced') {
        const positive = items.filter(item => Number.isFinite(item.bytes) && item.bytes > 0);
        if (scale === 'actual') return positive.map(item => ({...item, weight: item.bytes}));
        const total = positive.reduce((sum, item) => sum + Math.sqrt(item.bytes), 0);
        // Keep a floor of one third of an equal share so small entries stay clickable.
        const floor = positive.length ? total / (3 * positive.length) : 0;
        return positive.map(item => ({...item, weight: Math.max(floor, Math.sqrt(item.bytes))}));
    }

    function layout(items, x, y, width, height, output = []) {
        if (!items.length) return output;
        if (items.length === 1) {
            output.push({...items[0], rect: {x, y, w: width, h: height}});
            return output;
        }
        const total = items.reduce((sum, item) => sum + item.weight, 0);
        let sum = 0, index = 0;
        while (index < items.length - 1) {
            const next = sum + items[index].weight;
            if (index > 0 && Math.abs(sum - total / 2) < Math.abs(next - total / 2)) break;
            sum = next;
            index++;
        }
        index = Math.max(1, index);
        const first = items.slice(0, index), second = items.slice(index);
        const ratio = first.reduce((sum, item) => sum + item.weight, 0) / total;
        if (width >= height) {
            layout(first, x, y, width * ratio, height, output);
            layout(second, x + width * ratio, y, width * (1 - ratio), height, output);
        } else {
            layout(first, x, y, width, height * ratio, output);
            layout(second, x, y + height * ratio, width, height * (1 - ratio), output);
        }
        return output;
    }
    return {weightItems, layout};
})();

if (typeof module !== 'undefined') module.exports = Treemap;
