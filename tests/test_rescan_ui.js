const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the actual bridge event handlers with a minimal DOM: no browser,
// real scanning, private report, or native filesystem access is required.
const nodes = new Map(), messages = [], renders = [], scrolls = [];
function element() {
    return {hidden:false, disabled:false, textContent:'', dataset:{}, style:{},
        classList:{add(){},toggle(){}}, setAttribute(key,value){this[key]=value}, append(){}};
}
function get(id) { if(!nodes.has(id))nodes.set(id,element()); return nodes.get(id); }
const document = {body:element(), getElementById:get, createElementNS:element, addEventListener(){}};
const window = {webkit:{messageHandlers:{diskAssessment:{postMessage:message=>messages.push(message)}}},
    addEventListener(){},scrollTo:(...args)=>scrolls.push(args)};
const context = vm.createContext({document,window,console,Set,Map,queueMicrotask(){},
    requestAnimationFrame(){},setTimeout(){return 1},clearTimeout(){},
    recordRender:preserve=>renders.push(preserve)});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../resources/web/app.js'),'utf8'),context);
vm.runInContext('initNative()',context);
scrolls.length=0;
vm.runInContext(`
    data={id:'old'};stack=[{path:'/demo',name:'demo',kind:'directory'}];
    render=preserve=>recordRender(preserve);renderExplorer=()=>{};
    document.body.dataset.screen='report';
`,context);
get('appProgress').hidden=true;
get('navBack').disabled=true;
get('folderRescan').onclick();
assert.equal(messages.at(-1).type,'rescan');
assert.equal(messages.at(-1).path,'/demo');
assert.equal(get('folderProgress').hidden,false);
assert.equal(get('map').inert,true);
assert.equal(get('folderRescan').disabled,true);
window.nativeEvent('scanning','/demo');
window.nativeEvent('progress',{files:3,directories:2,path:'/demo/child'});
assert.equal(document.body.dataset.screen,'report','Rescans must not switch to the full-screen progress view');
assert.equal(get('appProgress').hidden,true);
assert.equal(get('folderScanCount').textContent,'3 files · 2 folders');
assert.equal(get('folderScanPath').textContent,'/demo/child');
get('folderCancel').onclick();
assert.equal(messages.at(-1).type,'cancel');
window.nativeEvent('cancelled',true);
assert.equal(get('folderProgress').hidden,true);
assert.equal(get('map').inert,false);
assert.equal(get('navBack').disabled,true,'Originally disabled navigation must stay disabled');
assert.equal(get('folderRescan').disabled,false);
assert.equal(vm.runInContext('data.id',context),'old');

get('folderRescan').onclick();
window.nativeEvent('rescanError','Folder moved');
assert.equal(document.body.dataset.screen,'report');
assert.equal(get('folderProgress').hidden,true);
assert.equal(get('toast').textContent,'Folder moved');
get('folderRescan').onclick();
window.receiveSnapshot({id:'new'});
assert.equal(vm.runInContext('data.id',context),'new');
assert.equal(renders.at(-1),true,'Successful refresh must preserve navigation');
assert.equal(get('folderProgress').hidden,true);
assert.equal(document.body.dataset.screen,'report');
assert.equal(scrolls.length,0,'Rescan completion, failure and cancellation must preserve scroll position');
window.nativeEvent('scanning','/new-scan');
assert.equal(document.body.dataset.screen,'scanning','New scans retain the normal full-screen scan view');
assert.equal(get('appProgress').hidden,false);
console.log('Inline rescan UI: local progress, bridge requests, cancellation, errors, preserved report/navigation/scroll and full-scan behavior passed.');
