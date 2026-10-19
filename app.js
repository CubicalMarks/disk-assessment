'use strict';
const native = Boolean(window.webkit?.messageHandlers?.diskAssessment);
let lastAvailable = false;
function sendNative(type, extra={}) { window.webkit.messageHandlers.diskAssessment.postMessage({type,...extra}); }
let data, stack=[], selected=new Set(), view='map', mapScale='balanced';
const $=id=>document.getElementById(id);
const colors=['#0a84ff','#5e5ce6','#64d2ff','#30b0c7','#30d158','#bf5af2','#ff9f0a','#ff375f'];
const fmt=n=>{if(!n)return '0 B';const u=['B','KiB','MiB','GiB','TiB'];const i=Math.min(4,Math.floor(Math.log(n)/Math.log(1024)));return (n/1024**i).toLocaleString(undefined,{maximumFractionDigits:i?1:0})+' '+u[i]};
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n}
function toast(message){$('toast').textContent=message;$('toast').style.display='block';clearTimeout(toast.timer);toast.timer=setTimeout(()=>$('toast').style.display='none',3500)}
async function copy(text){if(native){sendNative('copy',{text});return}try{await navigator.clipboard.writeText(text);toast('Paths copied to clipboard')}catch{toast('Clipboard unavailable. Select and copy the displayed paths manually.')}}
function parts(node){const children=node.children||[];const other=node.bytes-children.reduce((s,c)=>s+c.bytes,0);return [...children,...(other>0?[{name:'Other entries',path:node.path,bytes:other,kind:'other'}]:[])].filter(c=>c.bytes>0).sort((a,b)=>b.bytes-a.bytes)}
function enter(node){if(node.kind==='directory'){stack.push(node);renderExplorer()}else if(node.kind==='other'){toast('These entries are below the report detail threshold. Rescan with a lower threshold for more detail.')}else copy(node.path)}
function renderExplorer(){const node=stack.at(-1);if(native)sendNative('folder',{path:node.path});$('breadcrumbs').replaceChildren();stack.forEach((n,i)=>{const b=el('button','',i===0?(data.root==='/System/Volumes/Data'?'Data volume':n.name):n.name);b.onclick=()=>{stack=stack.slice(0,i+1);renderExplorer()};$('breadcrumbs').append(b);if(i<stack.length-1)$('breadcrumbs').append(el('span','','›'))});$('folderSize').textContent=fmt(node.bytes)+' · '+node.files.toLocaleString()+' files'+(node.errors?' · incomplete':'');$('map').hidden=view!=='map';$('fileList').hidden=view!=='list';$('scaleControl').hidden=view!=='map';$('scaleNote').textContent=(view==='list'?'Sorted by actual allocated size.':mapScale==='balanced'?'Balanced scale enlarges smaller entries for easier navigation. Areas are adjusted; labels show actual sizes.':'Tile area is proportional to actual allocated size.')+' Small entries are grouped as “Other entries”.';$('map').replaceChildren();$('fileList').replaceChildren();const items=parts(node);if(!items.length){$('map').append(el('p','empty','No measurable accessible files in this folder.'));return}const rect=$('map').getBoundingClientRect();Treemap.layout(Treemap.weightItems(items,mapScale),0,0,rect.width||700,rect.height||520).forEach((n,i)=>{const r=n.rect,b=el('button','tile');b.style.cssText=`left:${r.x}px;top:${r.y}px;width:${r.w}px;height:${r.h}px;--tile:${colors[i%colors.length]}`;b.title=n.path+' · '+fmt(n.bytes)+(node.bytes?' · '+(100*n.bytes/node.bytes).toLocaleString(undefined,{maximumFractionDigits:2})+'% of folder':'')+(n.kind==='directory'?' · Open folder':'');b.setAttribute('aria-label',n.name+', '+fmt(n.bytes));if(r.w<115||r.h<70)b.classList.add('compact');if(r.w>40&&r.h>24){b.append(el('strong','',n.name+(n.kind==='directory'?' ↗':'')));if(r.h>48)b.append(el('span',r.w<100?'tiny':'',fmt(n.bytes)))}b.onclick=()=>enter(n);$('map').append(b)});items.forEach(n=>{const b=el('button','list-entry');b.append(el('span','',n.name+(n.kind==='directory'?' /':'')),el('strong','',fmt(n.bytes)));b.onclick=()=>enter(n);$('fileList').append(b)})}
function renderCandidates(){const category=$('category').value,search=$('search').value.toLowerCase();$('candidates').replaceChildren();const candidates=data.candidates.filter(c=>(category==='all'||c.category===category)&&(c.path+' '+c.label).toLowerCase().includes(search));for(const c of candidates){const row=el('div','candidate'),check=el('input');check.type='checkbox';check.id='candidate-'+data.candidates.indexOf(c);check.checked=selected.has(c.path);check.onchange=()=>{check.checked?selected.add(c.path):selected.delete(c.path);renderSelection()};const body=el('div'),label=el('label','',c.label);label.htmlFor=check.id;body.append(label,el('code','',c.path));body.append(el('span','tag '+c.category,c.category==='rebuildable'?'Rebuildable · review first':'Needs review'));const detail=el('details'),summary=el('summary','','Review guidance');detail.append(summary,el('p','',c.guidance+(c.incomplete?' This path was only partly accessible.':'')));body.append(detail);row.append(check,body,el('span','size',fmt(c.bytes)));$('candidates').append(row)}if(!candidates.length)$('candidates').append(el('p','empty','No candidates match this filter.'));renderSelection()}
function renderSelection(){const chosen=data.candidates.filter(c=>selected.has(c.path));$('selectedSize').textContent=fmt(chosen.reduce((s,c)=>s+c.bytes,0));$('selectedCount').textContent=chosen.length+' selected · footprint only';$('copy').disabled=!chosen.length}
function render(){const total=cat=>data.candidates.filter(c=>c.category===cat).reduce((s,c)=>s+c.bytes,0);$('free').textContent=fmt(data.volume.free);$('capacity').textContent='of '+fmt(data.volume.total)+' shared APFS capacity';$('rebuildable').textContent=fmt(total('rebuildable'));$('review').textContent=fmt(total('review'));$('measured').textContent=fmt(data.tree.bytes);$('coverage').textContent=data.coverage.files.toLocaleString()+' files · '+data.coverage.error_count+' access errors';const date=new Date(data.scanned_at);$('stamp').textContent='Snapshot · '+date.toLocaleString()+'\n'+data.root;$('stamp').style.whiteSpace='pre-line';$('footerTime').textContent='Scan duration: '+data.duration_seconds+' s';$('warning').textContent=(data.coverage.error_count?'Partial coverage: '+data.coverage.error_count+' paths could not be read. ':'')+'Candidate sizes describe current allocated file blocks. APFS sharing, snapshots and inaccessible data mean actual reclaimed space can differ. No files have been changed.';$('threshold').textContent=fmt(data.coverage.tree_minimum_bytes)+' detail threshold';const used=data.volume.used,measured=data.tree.bytes,gap=Math.max(0,used-measured),available=data.volume.free,shared=data.volume.other_shared_usage||0,barTotal=measured+gap+available+shared;$('volumeBar').replaceChildren();for(const [bytes,cls]of[[measured,'measured'],[gap,'gap'],[shared,'shared'],[available,'free']]){const n=el('span',cls);n.style.width=100*bytes/barTotal+'%';n.title=fmt(bytes);$('volumeBar').append(n)}if(measured>used)$('warning').append(' Measured blocks exceed volume-used bytes; the bar shows scan accounting, not unique physical blocks.');$('largeFiles').replaceChildren();const head=el('div','file-row head');head.append(el('span','','PATH · click to copy'),el('span','number','ALLOCATED'),el('span','number','LOGICAL'));$('largeFiles').append(head);data.largest_files.slice(0,12).forEach(f=>{const row=el('div','file-row'),path=el('button','file-path',f.path);path.onclick=()=>copy(f.path);row.append(path,el('strong','number',fmt(f.bytes)),el('span','number',fmt(f.logical_bytes)));$('largeFiles').append(row)});const ul=el('ul');data.method.forEach(m=>ul.append(el('li','',m)));$('method').replaceChildren(ul);$('coverageDetail').textContent=`${data.coverage.directories.toLocaleString()} directories visited. ${data.coverage.symlinks_skipped.toLocaleString()} symlinks and ${data.coverage.mounts_skipped.length} mount points skipped. ${data.coverage.error_count} access errors; first ${data.coverage.errors.length} listed below. The file scan excludes directory metadata and does not measure snapshots. Missing data cannot be assumed to be junk.`;$('errors').replaceChildren();data.coverage.errors.forEach(e=>$('errors').append(el('p','',e.path+' — '+e.error)));stack=[data.tree];const users=data.tree.children?.find(n=>n.path==='/Users');const home=users?.children?.find(n=>n.path===data.home);if(home)stack.push(users,home);renderExplorer();renderCandidates();renderDocker()}
async function load(){try{$('reload').disabled=true;const response=await fetch('report-data.json',{cache:'no-store'});if(!response.ok)throw Error('Snapshot missing. Run python3 scan.py first.');data=await response.json();selected=new Set();render()}catch(error){$('warning').textContent=error.message;$('warning').setAttribute('role','alert')}finally{$('reload').disabled=false}}
$('mapScale').onchange=()=>{mapScale=$('mapScale').value;renderExplorer()};$('reload').onclick=load;$('category').onchange=renderCandidates;$('search').oninput=renderCandidates;$('copy').onclick=()=>copy(data.candidates.filter(c=>selected.has(c.path)).map(c=>c.path).join('\n'));$('mapButton').onclick=()=>setView('map');$('listButton').onclick=()=>setView('list');function setView(v){view=v;for(const [id,name]of[['mapButton','map'],['listButton','list']]){$(id).classList.toggle('active',v===name);$(id).setAttribute('aria-pressed',String(v===name))}renderExplorer()}let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{if(data)renderExplorer()},100)});queueMicrotask(()=>{if(native){initNative()}else{load()}});

function renderDocker(){const d=data.docker;$('dockerNote').hidden=!d;if(!d)return;if(d.error){$('dockerNote').textContent='Docker storage inspection unavailable: '+d.error;return}const text=d.rows.map(r=>r.Type+': '+r.Size+' total, '+r.Reclaimable+' reported reclaimable').join(' · ');$('dockerNote').textContent='Docker’s own estimate · '+text+'. These figures describe storage inside the disk image and overlap its footprint above; they are not additional savings. No pruning was run. Inspected '+new Date(d.captured_at).toLocaleString()+'.'}

function showScreen(screen) {
    document.body.dataset.screen=screen;
    $('appStart').hidden=screen!=='start';
    $('appProgress').hidden=screen!=='scanning';
    $('reportMain').hidden=screen!=='report';
    $('viewLast').hidden=!lastAvailable;
    if(screen==='report'&&data) requestAnimationFrame(renderExplorer);
    window.scrollTo(0,0);
}

function initNative() {
    document.body.classList.add('native');
    $('reload').hidden=true;
    ['newScan','revealFolder','exportSnapshot'].forEach(id=>$(id).hidden=false);
    $('newScan').onclick=()=>showScreen('start');
    $('scanMac').onclick=()=>sendNative('scanMac');
    $('chooseFolder').onclick=()=>sendNative('chooseFolder');
    $('viewLast').onclick=()=>sendNative('viewLast');
    $('cancelScan').onclick=()=>{sendNative('cancel');$('cancelScan').disabled=true;$('cancelScan').textContent='Cancelling…'};
    $('revealFolder').onclick=()=>sendNative('reveal');
    $('exportSnapshot').onclick=()=>sendNative('export');
    showScreen('start');
    sendNative('ready');
}

window.receiveSnapshot = function(snapshot) {
    data=snapshot;
    selected=new Set();
    lastAvailable=true;
    showScreen('report');
    render();
};

window.nativeEvent = function(name,value) {
    switch(name) {
        case 'ready': lastAvailable=value;showScreen('start');break;
        case 'scanning':
            $('scanRoot').textContent=value;
            $('scanCount').textContent='Starting scan…';
            $('scanPath').textContent='';
            $('cancelScan').disabled=false;
            $('cancelScan').textContent='Cancel Scan';
            $('startMessage').textContent='';
            showScreen('scanning');break;
        case 'progress':
            $('scanCount').textContent=value.files.toLocaleString()+' files · '+value.directories.toLocaleString()+' folders';
            $('scanPath').textContent=value.path;break;
        case 'cancelled':
            lastAvailable=value;
            $('startMessage').textContent='Scan cancelled. Your previous report is unchanged.';
            showScreen('start');break;
        case 'error': $('startMessage').textContent=value;showScreen('start');break;
        case 'saveWarning': toast(value);break;
        case 'copied': toast('Paths copied to clipboard');break;
    }
};
