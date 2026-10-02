const csvUrl = "assets/data/goes_xrs_cleaned.csv";
let data = [];
let display = [];
let selected = 0;
let playing = true;
let timer = null;

function parseCSV(text){
  const lines = text.trim().split(/\r?\n/);
  const headers = lines[0].split(",");
  return lines.slice(1).map(line=>{
    const parts = line.split(",");
    const obj = {};
    headers.forEach((h,i)=>obj[h]=parts[i] ?? "");
    return obj;
  });
}

function fmtFlux(v){
  const n = Number(v);
  return Number.isFinite(n) ? n.toExponential(3) : "NA";
}
function fmtLog(v){
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(6) : "NA";
}
function shortTime(s){
  return s.replace("+00:00"," UTC").replace("2026-","");
}

function renderRows(){
  const start = Math.max(0, selected-3);
  const end = Math.min(display.length, start+7);
  let sliceStart = Math.max(0, end-7);
  const box = document.getElementById("csvWindow");
  box.innerHTML = display.slice(sliceStart,end).map((r,i)=>{
    const realIndex = sliceStart+i;
    return `<div class="csv-row grid-row ${realIndex===selected?"active":""}">
      <span>${shortTime(r.time_tag)}</span>
      <span>${fmtFlux(r.flux_clean)}</span>
      <span>${fmtLog(r.log10_flux_clean)}</span>
    </div>`;
  }).join("");
  const row = display[selected];
  document.getElementById("rowCounter").textContent = `row ${selected+1} of ${display.length} shown`;
  document.getElementById("currentTime").textContent = row.time_tag.replace("+00:00"," UTC");
  document.getElementById("currentFlux").textContent = `${fmtFlux(row.flux_clean)} W/m²`;
  document.getElementById("currentLog").textContent = `log10 = ${fmtLog(row.log10_flux_clean)}`;
}

function renderChart(){
  const svg = document.getElementById("chart");
  const W=760,H=420,p={l:72,r:24,t:24,b:54};
  const valid = display.map((r,i)=>({i, y:Number(r.log10_flux_clean)})).filter(d=>Number.isFinite(d.y));
  const ys = valid.map(d=>d.y);
  let ymin=Math.min(...ys), ymax=Math.max(...ys);
  const pad=(ymax-ymin)*0.08 || .1; ymin-=pad; ymax+=pad;
  const x=i=>p.l+(i/(display.length-1))*(W-p.l-p.r);
  const y=v=>p.t+(ymax-v)/(ymax-ymin)*(H-p.t-p.b);

  const path = valid.map((d,j)=>`${j?"L":"M"} ${x(d.i).toFixed(2)} ${y(d.y).toFixed(2)}`).join(" ");
  let grid="";
  for(let k=0;k<5;k++){
    const frac=k/4, yy=p.t+frac*(H-p.t-p.b);
    const val=ymax-frac*(ymax-ymin);
    grid+=`<line class="grid-line" x1="${p.l}" x2="${W-p.r}" y1="${yy}" y2="${yy}"/>
      <text class="axis-label" x="${p.l-10}" y="${yy+4}" text-anchor="end">${val.toFixed(2)}</text>`;
  }
  const row=display[selected], sy=Number(row.log10_flux_clean), sx=x(selected), cy=Number.isFinite(sy)?y(sy):H/2;
  svg.innerHTML=`
    <text class="axis-label" x="20" y="20">log10 flux</text>
    ${grid}
    <line class="grid-line" x1="${p.l}" x2="${p.l}" y1="${p.t}" y2="${H-p.b}"/>
    <line class="grid-line" x1="${p.l}" x2="${W-p.r}" y1="${H-p.b}" y2="${H-p.b}"/>
    <path class="signal-muted" d="${path}"/>
    <path class="signal" d="${path}"/>
    <line class="selected-guide" x1="${sx}" x2="${sx}" y1="${p.t}" y2="${H-p.b}"/>
    <circle class="selected-halo" cx="${sx}" cy="${cy}" r="14"/>
    <circle class="selected-dot" cx="${sx}" cy="${cy}" r="6"/>
    <text class="axis-label" x="${p.l}" y="${H-20}">${display[0].time_tag.slice(11,16)} UTC</text>
    <text class="axis-label" x="${W-p.r}" y="${H-20}" text-anchor="end">${display[display.length-1].time_tag.slice(11,16)} UTC</text>
  `;
}

function selectIndex(i){
  selected = Math.max(0, Math.min(display.length-1, i));
  document.getElementById("scrubber").value = selected;
  renderRows();
  renderChart();
}

function startTimer(){
  clearInterval(timer);
  timer=setInterval(()=>{
    if(!playing) return;
    selectIndex((selected+1)%display.length);
  }, 850);
}

fetch(csvUrl)
  .then(r=>r.text())
  .then(text=>{
    data=parseCSV(text).filter(r=>r.energy==="0.1-0.8nm");
    display=data.slice(0,180);
    document.getElementById("datasetWindow").textContent =
      `${data[0].time_tag.slice(0,10)} → ${data[data.length-1].time_tag.slice(0,10)} · ${data.length.toLocaleString()} XRS-B rows`;
    document.getElementById("scrubber").max=display.length-1;
    selectIndex(0);
    startTimer();
  });

document.getElementById("scrubber").addEventListener("input",e=>{
  playing=false;
  document.getElementById("playButton").textContent="Play";
  selectIndex(Number(e.target.value));
});
document.getElementById("playButton").addEventListener("click",()=>{
  playing=!playing;
  document.getElementById("playButton").textContent=playing?"Pause":"Play";
});
