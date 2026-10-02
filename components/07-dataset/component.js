let meta=null;
let currentStep=0;

function makeObservationField(){
  // 1,400 visible dots stand in for all 10,078 rows; label makes scale explicit.
  const n=1400;
  return `<div class="dot-field">${Array.from({length:n},()=>'<i class="obs-dot"></i>').join('')}</div>`;
}
function makeEventField(){
  return `<div class="event-field">${Array.from({length:115},(_,i)=>`<i class="event-pill" title="Detected event ${i+1}"></i>`).join('')}</div>`;
}
function makeAlignment(){
  const detPos=Array.from({length:18},(_,i)=>6+i*5.1);
  const noaaPos=[8,17,25,31,39,47,56,64,73,81,89];
  const connections=[1,3,5,7,9,11,13,15,17];
  return `
    <div class="alignment-wrap">
      <div class="timeline">
        <span class="timeline-label">OUR DETECTOR · representative subset</span>
        ${detPos.map((p,i)=>`<i class="marker detect ${connections.includes(i)?'matched':''}" style="left:${p}%"></i>`).join('')}
      </div>
      <div class="connection-layer">
        ${connections.map((i,j)=>`<i class="conn" style="left:${detPos[i]}%"></i>`).join('')}
      </div>
      <div class="timeline">
        <span class="timeline-label">NOAA REFERENCE · representative subset</span>
        ${noaaPos.map((p,i)=>`<i class="marker noaa ${i<9?'matched':''}" style="left:${p}%"></i>`).join('')}
      </div>
    </div>`;
}
function makeDedup(){
  return `
    <div class="dedup-stage">
      <div class="duplicate-row">
        <div><div class="det-token">Detection A</div><div class="det-token" style="margin-top:8px">Detection B</div></div>
        <div class="merge-arrow">⟶</div>
        <div class="noaa-token">one NOAA physical flare</div>
      </div>
      <div class="duplicate-row">
        <div class="det-token">35 labeled detector rows</div>
        <div class="merge-arrow">⟶</div>
        <div class="noaa-token">32 independent physical events</div>
      </div>
    </div>`;
}
function makeClasses(showFiltered=false){
  const classes=[...Array(13).fill("B"),...Array(17).fill("C"),"M","U"];
  return `<div class="class-field">${classes.map((c,i)=>`<div class="class-token ${c} ${showFiltered&&c==="U"?"fade":""}">${c}</div>`).join('')}</div>`;
}
function makeML(){
  const rows=[...Array(13).fill("B"),...Array(18).fill("C+")];
  return `<div class="ml-field">${rows.map((c,i)=>`<div class="ml-token ${c==="B"?"B":""}"><b>${c}</b><small>event ${i+1}</small></div>`).join('')}</div>`;
}

function render(step){
  currentStep=step;
  const canvas=document.getElementById("visualCanvas");
  const label=document.getElementById("stageLabel");
  const title=document.getElementById("stageTitle");
  const counter=document.getElementById("mainCounter");
  const unit=document.getElementById("counterUnit");
  const cap=document.getElementById("stageCaption");

  if(step===0){
    label.textContent="STAGE 1 · OBSERVATIONS";
    title.textContent="10,078 minute-level measurements";
    counter.textContent="10,078"; unit.textContent="observations";
    canvas.innerHTML=makeObservationField();
    cap.textContent="A representative field of cyan marks stands in for all 10,078 timestamps. The unit is one minute-level measurement.";
  } else if(step===1){
    label.textContent="STAGE 2 · DETECTION";
    title.textContent="Minutes are grouped into event intervals";
    counter.textContent="115"; unit.textContent="detected events";
    canvas.innerHTML=makeEventField();
    cap.textContent="Each orange pill is one detected interval created from persistent unusual behavior. The unit has changed from minutes to events.";
  } else if(step===2){
    label.textContent="STAGE 3 · NOAA ALIGNMENT";
    title.textContent="Detector events are compared with an external reference";
    counter.textContent="32"; unit.textContent="matched detections";
    canvas.innerHTML=makeAlignment();
    cap.textContent="This is a representative alignment visual, not a one-to-one rendering of every event. Frozen totals: 32 matched detections, 80 unmatched detections, 3 unmatched NOAA events.";
  } else if(step===3){
    label.textContent="STAGE 4 · DEDUPLICATION";
    title.textContent="One physical flare must equal one independent example";
    counter.textContent="35 → 32"; unit.textContent="labeled rows → physical events";
    canvas.innerHTML=makeDedup();
    cap.textContent="Three NOAA flares had two detector segments each. Deduplication keeps one primary segment per physical flare.";
  } else if(step===4){
    label.textContent="STAGE 5 · CLASS ELIGIBILITY";
    title.textContent="B, C and M are usable; U is not";
    counter.textContent="32 → 31"; unit.textContent="physical events → ML-eligible events";
    canvas.innerHTML=makeClasses(true);
    cap.textContent="After deduplication: 13 B, 17 C, 1 M, 1 U. The target is B vs C+, so C and M combine while U is excluded.";
  } else {
    label.textContent="STAGE 6 · FINAL ML DATASET";
    title.textContent="31 independent labeled physical events";
    counter.textContent="31"; unit.textContent="ML rows";
    canvas.innerHTML=makeML();
    cap.textContent="Final target counts: 13 B and 18 C+. Each token now represents one physical event, not one minute.";
  }
}

fetch("assets/data/reduction_meta.json").then(r=>r.json()).then(m=>{meta=m;render(0)});

const steps=[...document.querySelectorAll(".step")];
const obs=new IntersectionObserver(entries=>{
  entries.forEach(entry=>{
    if(entry.isIntersecting){
      steps.forEach(s=>s.classList.remove("active"));
      entry.target.classList.add("active");
      render(Number(entry.target.dataset.step));
    }
  })
},{threshold:.55});
steps.forEach(s=>obs.observe(s));
