// Presentation gallery: 20 slides rendered from Solar_Activity.pptx (LibreOffice render; fonts may differ slightly from PowerPoint).
export const SLIDES = ["Title slide", "What Exactly Are We Trying to Do?", "Why Solar X-Rays Matter", "How Do We Observe Solar Activity?", "What Does the Time Series Actually Represent?", "Before “Unusual,” We Need “Normal”", "Center, Spread and Robustness", "Why Statistics Must Move With Time", "How Unusual Is This Measurement?", "From Unusual Observations to an Event", "An Event Has a Shape", "Did Our Statistical Detector Find a Real NOAA Event?", "What Did the Detection Stage Produce?", "Why Event Shape Matters", "The Five Primary Predictors", "What Is the Model Allowed to Know?", "Impulsive-Phase Flare Severity Nowcasting", "How Did We Test the Classification Experiment?", "What Did the Models Actually Show?", "What Did This Project Actually Demonstrate?"].map((title, i) => ({ n: i + 1, title, src: `assets/presentation/slide-${String(i + 1).padStart(2, "0")}.jpg`, thumb: `assets/presentation/thumbs/slide-${String(i + 1).padStart(2, "0")}.jpg` }));

export function init() {
  const host = document.getElementById("gallery"); if (!host) return;
  host.replaceChildren();
  const grid = document.createElement("div"); grid.className = "slides";
  const lb = document.createElement("div"); lb.className = "lightbox"; lb.hidden = true; lb.setAttribute("role", "dialog"); lb.setAttribute("aria-modal", "true"); lb.setAttribute("aria-label", "Presentation slide viewer");
  lb.innerHTML = '<button class="lb-x btn" type="button" aria-label="Close">Close</button><button class="lb-p btn" type="button" aria-label="Previous slide">Previous</button><figure><img alt=""><figcaption></figcaption></figure><button class="lb-n btn" type="button" aria-label="Next slide">Next</button>';
  document.body.append(lb);
  const img = lb.querySelector("img"), cap = lb.querySelector("figcaption"); let cur = 0, opener = null;
  const show = i => { cur = (i + SLIDES.length) % SLIDES.length; const s = SLIDES[cur]; img.src = s.src; img.alt = `Slide ${s.n}: ${s.title}`; cap.textContent = `${s.n} / ${SLIDES.length}  ${s.title}`; };
  const open = (i, el) => { opener = el; show(i); lb.hidden = false; document.body.style.overflow = "hidden"; lb.querySelector(".lb-x").focus(); };
  const close = () => { lb.hidden = true; document.body.style.overflow = ""; opener && opener.focus(); };
  SLIDES.forEach((s, i) => {
    const b = document.createElement("button"); b.type = "button"; b.className = "slide"; b.setAttribute("aria-label", `Open slide ${s.n}: ${s.title}`);
    b.innerHTML = `<img src="${s.thumb}" alt="" loading="lazy" width="520" height="293"><span>${String(s.n).padStart(2, "0")}  ${s.title}</span>`;
    b.addEventListener("click", () => open(i, b)); grid.append(b);
  });
  const dl = document.createElement("p"); dl.className = "note";
  dl.innerHTML = 'Slides are rendered images of the deck. <a href="assets/presentation/Solar_Activity.pptx" download>Download the PowerPoint file (.pptx, 4 MB)</a>. The file includes the presenter notes.';
  host.append(grid, dl);
  lb.querySelector(".lb-x").addEventListener("click", close); lb.querySelector(".lb-p").addEventListener("click", () => show(cur - 1)); lb.querySelector(".lb-n").addEventListener("click", () => show(cur + 1));
  lb.addEventListener("click", e => { if (e.target === lb) close(); });
  document.addEventListener("keydown", e => { if (lb.hidden) return; if (e.key === "Escape") close(); else if (e.key === "ArrowLeft") show(cur - 1); else if (e.key === "ArrowRight") show(cur + 1); });
}
