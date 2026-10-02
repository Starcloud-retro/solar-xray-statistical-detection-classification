let data=null;
function fmt(v){return v==null?"MISSING":Number(v).toExponential(3)}
function tm(s){return s.slice(11,16)+" UTC"}

function renderRows(rows, mode){
  document.getElementById("rowStrip").innerHTML=rows.map(r=>{
    const cls = mode==="imputed" && r.was_imputed ? "imputed" : r.raw_flux==null ? "missing" : "";
    const val = mode==="imputed" ? r.clean_flux : r.raw_flux;
    return `<div class="row-token ${cls}"><b>${tm(r.time_tag)}</b><span>${val==null?"raw missing":fmt(val)+" W/m²"}</span>${r.was_imputed&&mode==="imputed"?"<span>was_imputed = TRUE</span>":""}</div>`;
  }).join("");
}

function drawChart(rows, mode, longGap=false, segmentMode=false){
  const svg=document.getElementById("gapChart"),W=900,H=440,p={l:72,r:35,t:40,b:70};
  const access=r=>mode==="imputed"?r.clean_log10:r.raw_log10;
  const vals=rows.map(access).filter(v=>v!=null&&Number.isFinite(v));
  let ymin=Math.min(...vals),ymax=Math.max(...vals),pad=(ymax-ymin)*.35||.02;ymin-=pad;ymax+=pad;
  const x=i=>p.l+(i/(rows.length-1))*(W-p.l-p.r);
  const y=v=>p.t+(ymax-v)/(ymax-ymin)*(H-p.t-p.b);
  let html="";
  for(let k=0;k<4;k++){let yy=p.t+k/3*(H-p.t-p.b);html+=`<line class="grid" x1="${p.l}" x2="${W-p.r}" y1="${yy}" y2="${yy}"/>`}

  if(longGap){
    const mids=rows.map((r,i)=>r.is_long_gap?i:null).filter(i=>i!=null);
    if(mids.length){
      const x1=x(mids[0])-14,x2=x(mids.at(-1))+14;
      html+=`<rect class="gap-band" x="${x1}" y="${p.t+4}" width="${x2-x1}" height="${H-p.t-p.b-8}" rx="12"/>`;
      html+=`<text class="annotation" x="${(x1+x2)/2}" y="${p.t+28}" text-anchor="middle">6 minutes unobserved</text>`;
    }
  }

  let seg=[],groups=[];
  rows.forEach((r,i)=>{
    const v=access(r);
    if(v==null){if(seg.length)groups.push(seg);seg=[]}
    else seg.push({i,v});
  });
  if(seg.length)groups.push(seg);
  groups.forEach(g=>{
    const d=g.map((q,j)=>`${j?"L":"M"} ${x(q.i)} ${y(q.v)}`).join(" ");
    html+=`<path class="${longGap?"signal-segment":"signal"}" d="${d}"/>`;
  });

  rows.forEach((r,i)=>{
    const v=access(r);
    if(v!=null&&Number.isFinite(v)){
      const cls=mode==="imputed"&&r.was_imputed?"point-imputed":"point";
      html+=`<circle class="${cls}" cx="${x(i)}" cy="${y(v)}" r="${r.was_imputed?7:5}"/>`;
    }else{
      html+=`<circle class="point-missing" cx="${x(i)}" cy="${(p.t+H-p.b)/2}" r="8"/>`;
    }
    html+=`<text class="axis-text" x="${x(i)}" y="${H-38}" text-anchor="middle">${r.time_tag.slice(11,16)}</text>`;
  });

  if(mode==="imputed"){
    const idx=rows.findIndex(r=>r.was_imputed);
    if(idx>=0){
      const r=rows[idx],cy=y(r.clean_log10);
      html+=`<text class="annotation" x="${x(idx)}" y="${cy-28}" text-anchor="middle">imputed</text>`;
      html+=`<text class="subannotation" x="${x(idx)}" y="${cy-12}" text-anchor="middle">${fmt(r.clean_flux)} W/m²</text>`;
    }
  }

  if(segmentMode){
    const beforeIdx=rows.findIndex(r=>r.raw_flux!=null&&r.segment_id===data.segment_before_long_gap);
    const afterIdx=rows.findIndex(r=>r.raw_flux!=null&&r.segment_id===data.segment_after_long_gap);
    if(beforeIdx>=0) html+=`<text class="annotation" x="${x(beforeIdx)}" y="${p.t+24}">segment ${data.segment_before_long_gap}</text>`;
    if(afterIdx>=0) html+=`<text class="annotation" x="${x(afterIdx)}" y="${p.t+24}">segment ${data.segment_after_long_gap}</text>`;
  }
  html+=`<text class="axis-text" x="18" y="24">log10 flux</text>`;
  svg.innerHTML=html;
}

function render(step){
  const title=document.getElementById("stageTitle"),label=document.getElementById("stageLabel"),badge=document.getElementById("statusBadge"),cap=document.getElementById("caption");
  if(step===0){
    label.textContent="REAL EXAMPLE A · 6 SEP 2026";title.textContent="One missing minute inside an otherwise continuous signal";badge.textContent="RAW GAP";
    renderRows(data.short_gap,"raw");drawChart(data.short_gap,"raw");cap.textContent="19:34 UTC has no direct raw measurement. The surrounding minutes remain observed.";
  }else if(step===1){
    label.textContent="REAL EXAMPLE A · GAP SIZE = 1";title.textContent="The missing interval is short enough to qualify for interpolation";badge.textContent="≤ 3 MIN RULE";
    renderRows(data.short_gap,"raw");drawChart(data.short_gap,"raw");cap.textContent="The frozen preprocessing rule permits only gaps of three minutes or less to be reconstructed.";
  }else if(step===2){
    label.textContent="REAL EXAMPLE A · CLEANED SIGNAL";title.textContent="The 19:34 minute is reconstructed, but not disguised as observed";badge.textContent="IMPUTED";
    renderRows(data.short_gap,"imputed");drawChart(data.short_gap,"imputed");cap.textContent=`Actual cleaned value: ${data.short_gap_clean_flux.toExponential(6)} W/m²; was_imputed = TRUE.`;
  }else if(step===3){
    label.textContent="REAL EXAMPLE B · 4 SEP 2026";title.textContent="Six consecutive minutes are genuinely unobserved";badge.textContent="LONG GAP";
    renderRows(data.long_gap,"raw");drawChart(data.long_gap,"raw",true);cap.textContent="16:31–16:36 UTC remains missing because a six-minute interval exceeds the short-gap interpolation limit.";
  }else if(step===4){
    label.textContent="REAL EXAMPLE B · DO NOT BRIDGE";title.textContent="The cleaned signal stays broken across the long gap";badge.textContent="PRESERVE MISSING";
    renderRows(data.long_gap,"raw");drawChart(data.long_gap,"raw",true);cap.textContent="No artificial line is drawn between the observations before and after the six-minute gap.";
  }else{
    label.textContent="REAL EXAMPLE B · SEGMENT BOUNDARY";title.textContent="Later calculations restart in a new continuous segment";badge.textContent="NEW SEGMENT";
    renderRows(data.long_gap,"raw");drawChart(data.long_gap,"raw",true,true);cap.textContent=`Valid rows before the gap use segment ${data.segment_before_long_gap}; after the break the usable series resumes with segment ${data.segment_after_long_gap}.`;
  }
}

fetch("assets/data/preprocessing_examples.json").then(r=>r.json()).then(d=>{data=d;render(0)});
const steps=[...document.querySelectorAll(".step")];
const obs=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){steps.forEach(s=>s.classList.remove("active"));e.target.classList.add("active");render(Number(e.target.dataset.step));}}),{threshold:.55});
steps.forEach(s=>obs.observe(s));
