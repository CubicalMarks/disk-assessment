'use strict';
const native = Boolean(window.webkit?.messageHandlers?.diskAssessment);
const $ = id => document.getElementById(id);
let data, model, navigation, stack = [], activeItem;
let selected = new Set(), view = 'map', mapScale = 'balanced', lastAvailable = false;
let currentTab = 'review';
const fmt = n => {
    if (!n) return '0 B';
    const units = ['B','KiB','MiB','GiB','TiB'];
    const i = Math.min(4, Math.floor(Math.log(n) / Math.log(1024)));
    return (n / 1024**i).toLocaleString(undefined, {maximumFractionDigits:i ? 1 : 0}) + ' ' + units[i];
};
function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
}
function icon(name) {
    const paths = {
        folder:'M3 6.5h6l2 2h10v10.5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6.5Z M3 9h18',
        file:'M6 3h8l4 4v14H6V3Z M14 3v5h4 M9 12h6 M9 16h6',
        finder:'M3 4h18v16H3V4Z M12 4l-2 9h4v7 M7 9h.01 M17 9h.01 M7 15c2 2 8 2 10 0',
        back:'m14 6-6 6 6 6', forward:'m10 6 6 6-6 6', up:'m6 14 6-6 6 6',
        arrow:'M5 12h14 m-6-6 6 6-6 6', copy:'M8 8h12v13H8V8Z M16 8V3H3v13h5',
        check:'m5 12 4 4 10-10'
    };
    const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
    for (const [key,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.6','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true'})) svg.setAttribute(key,value);
    const path = document.createElementNS('http://www.w3.org/2000/svg','path');
    path.setAttribute('d',paths[name] || paths.file);
    svg.append(path);
    return svg;
}
function sendNative(type, extra={}) { window.webkit.messageHandlers.diskAssessment.postMessage({type,...extra}); }
function toast(message) {
    $('toast').textContent = message;
    $('toast').style.display = 'block';
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => $('toast').style.display='none', 3500);
}
async function copy(text) {
    if (native) return sendNative('copy',{text});
    try { await navigator.clipboard.writeText(text); toast('Path copied'); }
    catch { toast('Clipboard unavailable. Select and copy the displayed path.'); }
}
function finder(item, openFolder=true) {
    if (!item || item.kind === 'other') return;
    if (native) sendNative('finder',{path:item.path,openFolder});
    else toast('Finder actions are available in the macOS app.');
}
function finderButton(item, cls='icon-button') {
    const button = el('button',cls);
    const label = (item.kind === 'directory' ? 'Open in Finder: ' : 'Show in Finder: ') + item.name;
    button.title = label;
    button.setAttribute('aria-label',label);
    button.append(icon('finder'));
    button.onclick = event => { event.stopPropagation(); finder(item); };
    return button;
}
function contextMenu(event, item) {
    if (!native || item.kind === 'other') return;
    event.preventDefault();
    selectItem(item);
    sendNative('contextMenu',{path:item.path,x:event.clientX,y:event.clientY});
}
function candidateFor(item) { return data?.candidates.find(candidate => candidate.path === item.path); }
function selectItem(item) {
    activeItem = item;
    if (native && item.kind !== 'other') sendNative('selection',{path:item.path});
    document.querySelectorAll('[data-item-path]').forEach(node => {
        const active = node.dataset.itemPath === item.path;
        node.classList.toggle('item-selected',active);
        const control = node.querySelector('.tile-content');
        if (control) control.setAttribute('aria-pressed',String(active));
    });
    renderInspector();
}
function renderInspector() {
    const item = activeItem || stack.at(-1);
    if (!item) return;
    const inspector = $('inspector');
    inspector.replaceChildren();
    const heading = el('div','inspector-heading');
    const symbol = el('div','item-symbol');
    symbol.style.setProperty('--item-color',ReportModel.color(item.path));
    symbol.append(icon(item.kind === 'directory' ? 'folder' : 'file'));
    const info = el('div','inspector-info');
    info.append(el('strong','',item.name || item.path),el('code','',item.path));
    const size = el('div','inspector-size');
    size.append(el('strong','',fmt(item.bytes)));
    const parent = stack.at(-1);
    const share = parent?.bytes ? 100*item.bytes/parent.bytes : 0;
    const withinCurrent = item.path === parent?.path || item.path.startsWith(parent?.path+'/');
    size.append(el('span','',withinCurrent ? share.toLocaleString(undefined,{maximumFractionDigits:2})+'% of this folder' : 'Allocated on disk'));
    heading.append(symbol,info,size);
    inspector.append(heading);
    if (item.kind === 'other') {
        inspector.append(el('p','inspector-guidance','A group of entries below the report detail threshold. It has no single Finder location.'));
        return;
    }
    const actions = el('div','inspector-actions');
    if (native) {
        const open = finderButton(item,'finder-primary');
        open.append(document.createTextNode(item.kind === 'directory' ? 'Open in Finder' : 'Show in Finder'));
        actions.append(open);
    }
    if (item.kind === 'directory' && model.nodes.has(item.path) && item.path !== parent.path) {
        const explore = el('button','','Explore Folder');
        explore.append(icon('arrow'));
        explore.onclick = () => navigate(model.chain(item.path));
        actions.append(explore);
    }
    const copyButton = el('button','quiet-button','Copy Path');
    copyButton.onclick = () => copy(item.path);
    actions.append(copyButton);
    if(native){const more=el('button','quiet-button','More…');more.setAttribute('aria-label','More actions for '+item.name);more.onclick=()=>{const rect=more.getBoundingClientRect();sendNative('contextMenu',{path:item.path,x:rect.left,y:rect.bottom})};actions.append(more)}
    inspector.append(actions);
    const candidate = candidateFor(item);
    if (candidate) inspector.append(el('p','inspector-guidance',candidate.guidance));
}
function parts(node) {
    const children = node.children || [];
    const other = node.bytes - children.reduce((sum,child) => sum+child.bytes,0);
    return [...children,...(other>0 ? [{name:'Other entries',path:node.path+'#other',bytes:other,kind:'other'}] : [])]
        .filter(child => child.bytes>0).sort((a,b) => b.bytes-a.bytes);
}
function navigate(chain, record=true) {
    if (!chain?.length) return;
    if (record) navigation.visit(chain);
    stack = chain.slice();
    $('folderFilter').value = '';
    activeItem = stack.at(-1);
    renderExplorer();
}
function activate(item) {
    if (item.kind === 'directory') navigate(model.chain(item.path));
    else if (item.kind !== 'other') finder(item);
}
function renderExplorer() {
    const node = stack.at(-1);
    if (!node) return;
    if (native) sendNative('folder',{path:node.path});
    $('navBack').disabled = !navigation.canBack;
    $('navForward').disabled = !navigation.canForward;
    $('navUp').disabled = stack.length < 2;
    $('breadcrumbs').replaceChildren();
    stack.forEach((entry,index) => {
        const name = index===0 && data.root==='/System/Volumes/Data' ? 'Data volume' : entry.name;
        const button = el('button','',name);
        button.onclick = () => navigate(stack.slice(0,index+1));
        $('breadcrumbs').append(button);
        if (index < stack.length-1) $('breadcrumbs').append(el('span','','›'));
    });
    $('folderSize').textContent = fmt(node.bytes)+' · '+node.files.toLocaleString()+' files'+(node.errors?' · incomplete':'');
    $('threshold').textContent = fmt(data.coverage.tree_minimum_bytes)+' detail';
    $('map').hidden = view!=='map';
    $('fileList').hidden = view!=='list';
    $('scaleControl').hidden = view!=='map';
    $('scaleNote').textContent = view==='list' ? 'Sorted by actual allocated size. Select an item to see its details.' : mapScale==='balanced' ? 'Balanced areas keep small items visible. Labels and percentages show actual sizes.' : 'Tile areas are proportional to actual allocated size.';
    $('map').replaceChildren();
    $('fileList').replaceChildren();
    const search = $('folderFilter').value.toLowerCase();
    const items = parts(node).filter(item => item.name.toLowerCase().includes(search));
    if (!items.length) {
        $('map').append(el('p','empty',search?'No items match this filter.':'No measurable accessible files in this folder.'));
        $('fileList').append(el('p','empty','No items to display.'));
        renderInspector();
        return;
    }
    const rect = $('map').getBoundingClientRect();
    const tiles = Treemap.layout(Treemap.weightItems(items,mapScale),0,0,rect.width||700,rect.height||490);
    tiles.forEach(item => {
        const r = item.rect, tile = el('div','tile');
        tile.dataset.itemPath = item.path;
        tile.classList.toggle('item-selected',activeItem?.path===item.path);
        tile.style.cssText = `left:${r.x}px;top:${r.y}px;width:${r.w}px;height:${r.h}px;--tile:${ReportModel.color(item.path)}`;
        const control = el('button','tile-content');
        control.title = item.name+' · '+fmt(item.bytes)+' · '+(100*item.bytes/node.bytes).toLocaleString(undefined,{maximumFractionDigits:2})+'% of folder';
        control.setAttribute('aria-label',item.name+', '+fmt(item.bytes));
        control.setAttribute('aria-pressed',String(activeItem?.path===item.path));
        if (r.w<115 || r.h<70) tile.classList.add('compact');
        if (r.w>40 && r.h>24) {
            control.append(el('strong','',item.name));
            if (r.h>48) control.append(el('span',r.w<100?'tiny':'',fmt(item.bytes)));
        }
        control.onclick = () => selectItem(item);
        control.ondblclick = () => activate(item);
        control.onkeydown = event => {
            if (event.key==='Enter') { event.preventDefault(); activate(item); }
        };
        tile.oncontextmenu = event => contextMenu(event,item);
        tile.append(control);
        if (native && item.kind!=='other' && r.w>75 && r.h>52) tile.append(finderButton(item,'tile-finder'));
        $('map').append(tile);
    });
    items.forEach(item => {
        const row = el('div','explorer-row');
        row.dataset.itemPath = item.path;
        row.classList.toggle('item-selected',activeItem?.path===item.path);
        const button = el('button','list-entry');
        button.append(icon(item.kind==='directory'?'folder':'file'),el('span','',item.name),el('strong','',fmt(item.bytes)));
        button.onclick = () => selectItem(item);
        button.ondblclick = () => activate(item);
        row.oncontextmenu = event => contextMenu(event,item);
        row.append(button);
        if (native && item.kind!=='other') row.append(finderButton(item));
        $('fileList').append(row);
    });
    renderInspector();
}
function itemForPath(path, fallback={}) {
    return model.nodes.get(path) || {name:path.split('/').at(-1),path,kind:'directory',...fallback};
}
function renderCandidates() {
    const category=$('category').value, search=$('search').value.toLowerCase();
    $('candidates').replaceChildren();
    const candidates=data.candidates.filter(item => (category==='all'||item.category===category) && (item.path+' '+item.label).toLowerCase().includes(search));
    for (const candidate of candidates) {
        const item=itemForPath(candidate.path,candidate);
        const row=el('div','candidate');
        row.dataset.itemPath=item.path;
        row.classList.toggle('item-selected',activeItem?.path===item.path);
        const check=el('input');
        check.type='checkbox';
        check.setAttribute('aria-label','Add '+candidate.label+' to review selection');
        check.checked=selected.has(candidate.path);
        check.onchange=()=>{check.checked?selected.add(candidate.path):selected.delete(candidate.path);renderSelection()};
        const body=el('div','candidate-body');
        const title=el('button','item-title',candidate.label);
        title.onclick=()=>selectItem(item);
        body.append(title,el('code','',candidate.path),el('span','tag '+candidate.category,candidate.category==='rebuildable'?'Rebuildable · review first':'Needs review'));
        const details=el('details'), summary=el('summary','','Review guidance');
        details.append(summary,el('p','',candidate.guidance+(candidate.incomplete?' This path was only partly accessible.':'')));
        body.append(details);
        const end=el('div','candidate-end');
        end.append(el('span','size',fmt(candidate.bytes)));
        if(native)end.append(finderButton(item));
        row.append(check,body,end);
        row.oncontextmenu=event=>contextMenu(event,item);
        $('candidates').append(row);
    }
    if(!candidates.length)$('candidates').append(el('p','empty','No candidates match this filter.'));
    $('reviewCount').textContent=data.candidates.length;
    renderSelection();
}
function renderSelection() {
    const chosen=data.candidates.filter(item=>selected.has(item.path));
    $('selectedSize').textContent=fmt(chosen.reduce((sum,item)=>sum+item.bytes,0));
    $('selectedCount').textContent=chosen.length+' in review selection · footprint only';
    $('copy').disabled=!chosen.length;
}
function renderLargeFiles() {
    $('largeFiles').replaceChildren();
    data.largest_files.slice(0,40).forEach(file=>{
        const item=itemForPath(file.path,{...file,kind:'file'});
        const row=el('div','large-file');
        row.dataset.itemPath=item.path;
        const symbol=el('span','file-symbol');symbol.append(icon('file'));
        const body=el('div','large-file-body');
        const title=el('button','item-title',item.name);
        title.onclick=()=>selectItem(item);
        body.append(title,el('code','',item.path),el('span','file-logical','Logical size '+fmt(item.logical_bytes)));
        const end=el('div','candidate-end');end.append(el('strong','size',fmt(item.bytes)));
        if(native)end.append(finderButton(item));
        row.append(symbol,body,end);
        row.oncontextmenu=event=>contextMenu(event,item);
        $('largeFiles').append(row);
    });
}
function setTab(tab) {
    currentTab=tab;
    $('reviewPanel').hidden=tab!=='review';$('largePanel').hidden=tab!=='large';
    $('reviewTab').setAttribute('aria-selected',String(tab==='review'));
    $('largeTab').setAttribute('aria-selected',String(tab==='large'));
}
function render() {
    model=ReportModel.index(data);
    stack=[data.tree];
    const home=model.chain(data.home);
    if(home)stack=home;
    navigation=new ReportModel.Navigation(stack);
    activeItem=stack.at(-1);
    const total=category=>data.candidates.filter(item=>item.category===category).reduce((sum,item)=>sum+item.bytes,0);
    $('free').textContent=fmt(data.volume.free);
    $('capacity').textContent='of '+fmt(data.volume.total)+' shared APFS capacity';
    $('capacityRing').style.setProperty('--free-angle',360*data.volume.free/data.volume.total+'deg');
    $('rebuildable').textContent=fmt(total('rebuildable'));$('review').textContent=fmt(total('review'));
    $('measured').textContent=fmt(data.tree.bytes);
    $('coverage').textContent=data.coverage.files.toLocaleString()+' files · '+data.coverage.error_count+' access errors';
    const date=new Date(data.scanned_at);
    $('stamp').textContent='Scanned '+date.toLocaleString()+'\n'+data.root;$('stamp').style.whiteSpace='pre-line';
    $('footerTime').textContent='Scan duration: '+data.duration_seconds+' s';
    $('warning').textContent=(data.coverage.error_count?'Partial coverage: '+data.coverage.error_count+' paths could not be read. ':'')+'Candidate footprints require review. APFS sharing and inaccessible data affect actual space recovered.';
    const measured=data.tree.bytes, gap=Math.max(0,data.volume.used-measured), available=data.volume.free, shared=data.volume.other_shared_usage||0;
    const barTotal=measured+gap+available+shared;
    $('volumeBar').replaceChildren();
    for(const [bytes,cls]of[[measured,'measured'],[gap,'gap'],[shared,'shared'],[available,'free']]){
        const segment=el('span',cls);segment.style.width=100*bytes/barTotal+'%';segment.title=fmt(bytes);$('volumeBar').append(segment);
    }
    if(measured>data.volume.used)$('warning').append(' Measured blocks exceed volume-used bytes; the bar shows scan accounting.');
    const ul=el('ul');data.method.forEach(method=>ul.append(el('li','',method)));$('method').replaceChildren(ul);
    $('coverageDetail').textContent=`${data.coverage.directories.toLocaleString()} directories visited. ${data.coverage.symlinks_skipped.toLocaleString()} symlinks and ${data.coverage.mounts_skipped.length} mount points skipped. ${data.coverage.error_count} access errors; first ${data.coverage.errors.length} below. Missing data cannot be assumed to be junk.`;
    $('errors').replaceChildren();data.coverage.errors.forEach(error=>$('errors').append(el('p','',error.path+' — '+error.error)));
    $('folderFilter').value='';
    renderExplorer();renderCandidates();renderLargeFiles();renderDocker();setTab(currentTab);
}
function renderDocker() {
    const diagnostic=data.docker;$('dockerNote').hidden=!diagnostic;
    if(!diagnostic)return;
    $('dockerNote').textContent=diagnostic.error?'Docker inspection unavailable: '+diagnostic.error:'Docker’s estimate · '+diagnostic.rows.map(row=>row.Type+': '+row.Reclaimable+' reclaimable').join(' · ')+'. These figures overlap the disk image footprint; they are not additional savings. No pruning was run.';
}
async function load() {
    try {
        $('reload').disabled=true;
        const response=await fetch('report-data.json',{cache:'no-store'});
        if(!response.ok)throw Error('Snapshot missing. Run python3 scan.py first.');
        data=await response.json();selected=new Set();render();
    } catch(error) { $('warning').textContent=error.message;$('warning').setAttribute('role','alert'); }
    finally { $('reload').disabled=false; }
}
function setView(next) {
    view=next;
    for(const[id,name]of[['mapButton','map'],['listButton','list']]){
        $(id).classList.toggle('active',view===name);$(id).setAttribute('aria-pressed',String(view===name));
    }
    renderExplorer();
}
function showScreen(screen) {
    document.body.dataset.screen=screen;
    $('appStart').hidden=screen!=='start';$('appProgress').hidden=screen!=='scanning';$('reportMain').hidden=screen!=='report';
    $('viewLast').hidden=!lastAvailable;
    if(screen==='report'&&data)requestAnimationFrame(renderExplorer);
    window.scrollTo(0,0);
}
function initNative() {
    document.body.classList.add('native');$('reload').hidden=true;
    ['newScan','exportSnapshot','folderFinder'].forEach(id=>$(id).hidden=false);
    $('newScan').onclick=()=>showScreen('start');$('scanMac').onclick=()=>sendNative('scanMac');$('chooseFolder').onclick=()=>sendNative('chooseFolder');
    $('viewLast').onclick=()=>sendNative('viewLast');
    $('cancelScan').onclick=()=>{sendNative('cancel');$('cancelScan').disabled=true;$('cancelScan').textContent='Cancelling…'};
    $('exportSnapshot').onclick=()=>sendNative('export');
    showScreen('start');sendNative('ready');
}
window.receiveSnapshot=snapshot=>{data=snapshot;selected=new Set();lastAvailable=true;showScreen('report');render()};
window.nativeEvent=(name,value)=>{
    switch(name){
        case'ready':lastAvailable=value;showScreen('start');break;
        case'scanning':$('scanRoot').textContent=value;$('scanCount').textContent='Starting scan…';$('scanPath').textContent='';$('cancelScan').disabled=false;$('cancelScan').textContent='Cancel Scan';$('startMessage').textContent='';showScreen('scanning');break;
        case'progress':$('scanCount').textContent=value.files.toLocaleString()+' files · '+value.directories.toLocaleString()+' folders';$('scanPath').textContent=value.path;break;
        case'cancelled':lastAvailable=value;$('startMessage').textContent='Scan cancelled. Your previous report is unchanged.';showScreen('start');break;
        case'error':$('startMessage').textContent=value;showScreen('start');break;
        case'actionError':case'saveWarning':toast(value);break;
        case'copied':toast('Path copied');break;
    }
};
$('mapScale').onchange=()=>{mapScale=$('mapScale').value;renderExplorer()};
$('folderFilter').oninput=renderExplorer;
$('reload').onclick=load;$('category').onchange=renderCandidates;$('search').oninput=renderCandidates;
$('copy').onclick=()=>copy(data.candidates.filter(item=>selected.has(item.path)).map(item=>item.path).join('\n'));
$('mapButton').onclick=()=>setView('map');$('listButton').onclick=()=>setView('list');
$('reviewTab').onclick=()=>setTab('review');$('largeTab').onclick=()=>setTab('large');
$('navBack').append(icon('back'));$('navForward').append(icon('forward'));$('navUp').append(icon('up'));$('folderFinder').append(icon('finder'));
$('navBack').onclick=()=>navigate(navigation.back(),false);$('navForward').onclick=()=>navigate(navigation.forward(),false);
$('navUp').onclick=()=>{if(stack.length>1)navigate(stack.slice(0,-1))};$('folderFinder').onclick=()=>finder(stack.at(-1));
document.addEventListener('keydown',event=>{
    if(event.target.closest('input,select,textarea'))return;
    if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='r'&&native&&data){event.preventDefault();finder(activeItem||stack.at(-1),false)}
    if(event.altKey&&event.key==='ArrowLeft'&&navigation?.canBack){event.preventDefault();navigate(navigation.back(),false)}
    if(event.altKey&&event.key==='ArrowRight'&&navigation?.canForward){event.preventDefault();navigate(navigation.forward(),false)}
});
let resizeTimer;
window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{if(data)renderExplorer()},100)});
queueMicrotask(()=>{if(native)initNative();else load()});
