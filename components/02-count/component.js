const metaUrl="assets/data/dataset_meta.json";
let meta=null;
let canvas,ctx,animCount=0,targetCount=0,startTs=null;

function niceDate(iso){
  const d=new Date(iso);
  return d.toLocaleDateString("en-GB",{day:"2-digit",month:"short",year:"numeric",timeZone:"UTC"});
}
function niceTime(iso){
  const d=new Date(iso);
  return d.toLocaleTimeString("en-GB",{hour:"2-digit",minute:"2-digit",timeZone:"UTC",hour12:false})+" UTC";
}

function renderMeta(){
  document.getElementById("windowText").textContent=`${niceDate(meta.start)} → ${niceDate(meta.end)}`;
  document.getElementById("daysText").textContent=`${meta.elapsed_days.toFixed(2)} elapsed days`;
  document.getElementById("rowCount").textContent=meta.row_count.toLocaleString();
  document.getElementById("startDate").textContent=niceDate(meta.start);
  document.getElementById("startTime").textContent=niceTime(meta.start);
  document.getElementById("endDate").textContent=niceDate(meta.end);
  document.getElementById("endTime").textContent=niceTime(meta.end);
  document.getElementById("actualEquation").textContent=`${meta.row_count.toLocaleString()} actual XRS-B rows`;
  document.getElementById("coverageText").textContent=`≈ ${(meta.coverage_ratio*100).toFixed(2)}% of minute positions represented`;

  document.getElementById("dayMarkers").innerHTML=meta.dates.map(d=>`<span>${d.slice(5)}</span>`).join("");

  const max=Math.max(...Object.values(meta.rows_per_date));
  document.getElementById("dayBars").innerHTML=Object.entries(meta.rows_per_date).map(([d,n])=>`
    <div class="day-bar">
      <div class="bar" style="height:${Math.max(12,n/max*230)}px"><strong>${n.toLocaleString()}</strong></div>
      <span>${d.slice(5)}</span>
    </div>
  `).join("");

  setTimeout(()=>document.getElementById("timelineFill").style.width="100%",250);
}

function drawDensityProgress(progress){
  const W=canvas.width,H=canvas.height,pad=28,cols=140,rows=Math.ceil(meta.row_count/cols);
  ctx.clearRect(0,0,W,H);
  const maxPoints=Math.floor(meta.row_count*progress);
  const cellW=(W-pad*2)/(cols-1);
  const cellH=(H-pad*2)/(rows-1);

  for(let i=0;i<maxPoints;i++){
    const c=i%cols,r=Math.floor(i/cols);
    const x=pad+c*cellW,y=pad+r*cellH;
    const dayFrac=i/meta.row_count;
    const red=Math.round(53+(255-53)*Math.max(0,1-dayFrac*2)*0.1);
    ctx.fillStyle = i%233===0 ? "rgba(255,139,61,.95)" : "rgba(83,199,238,.72)";
    ctx.fillRect(x,y,2.2,2.2);
  }
  document.getElementById("densityCounter").textContent=`${maxPoints.toLocaleString()} / ${meta.row_count.toLocaleString()}`;
}

function animateDensity(ts){
  if(!startTs) startTs=ts;
  const t=Math.min(1,(ts-startTs)/2600);
  const eased=1-Math.pow(1-t,3);
  drawDensityProgress(eased);
  if(t<1) requestAnimationFrame(animateDensity);
}

fetch(metaUrl).then(r=>r.json()).then(m=>{
  meta=m;
  renderMeta();
  canvas=document.getElementById("densityCanvas");
  ctx=canvas.getContext("2d");
  requestAnimationFrame(animateDensity);
});
