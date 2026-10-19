'use strict';

const ReportModel = (() => {
    const palette = ['#22738f','#6555b7','#20757e','#4f56c8','#8150ad','#257476','#8e4f8a','#375f9e'];
    function color(path) {
        let hash = 0;
        for (const char of path) hash = (hash * 31 + char.codePointAt(0)) | 0;
        return palette[(hash >>> 0) % palette.length];
    }
    function index(snapshot) {
        const nodes = new Map(), parents = new Map();
        function visit(node, parent) {
            nodes.set(node.path, node);
            if (parent) parents.set(node.path, parent.path);
            for (const child of node.children || []) visit(child, node);
        }
        visit(snapshot.tree, null);
        function chain(path) {
            if (!nodes.has(path)) return null;
            const result = [];
            for (let current = path; current; current = parents.get(current)) result.unshift(nodes.get(current));
            return result;
        }
        return {nodes, parents, chain};
    }
    class Navigation {
        constructor(initial) { this.entries = [initial.slice()]; this.position = 0; }
        get current() { return this.entries[this.position].slice(); }
        get canBack() { return this.position > 0; }
        get canForward() { return this.position < this.entries.length - 1; }
        visit(chain) {
            if (!chain.length || chain.at(-1).path === this.current.at(-1).path) return;
            this.entries = this.entries.slice(0, this.position + 1);
            this.entries.push(chain.slice());
            this.position++;
        }
        rebase(model) {
            this.entries=this.entries.map(chain=>{
                for(const node of chain.slice().reverse()){
                    const fresh=model.chain(node.path);
                    if(fresh)return fresh;
                }
                return [model.nodes.values().next().value];
            });
        }
        back() { if (this.canBack) this.position--; return this.current; }
        forward() { if (this.canForward) this.position++; return this.current; }
    }
    return {color, index, Navigation};
})();
if (typeof module !== 'undefined') module.exports = ReportModel;
