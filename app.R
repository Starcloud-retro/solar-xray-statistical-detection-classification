# ==============================================================================
# app.R
# Final Academic Demonstration GUI
# Statistical Detection and Classification of Solar Activity Using Real-Time
# X-Ray Time-Series Data
#
# IMPORTANT SCIENTIFIC CONTRACT
# - Visualization/demo layer only.
# - Does NOT retrain models or change Stage 8 methodology.
# - Does NOT change target, predictors, split, detector, alignment, or t_pred.
# - Loads frozen Stage 8 artifacts when present.
# - Never fabricates missing scientific results.
# ==============================================================================

options(stringsAsFactors = FALSE)

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop("The 'shiny' package is required. Install it before launching app.R.")
}
library(shiny)

# Reuse the current rolling-statistics implementation for READ-ONLY display
# because no frozen rolling-statistics CSV is stored in this snapshot.
if (file.exists("R/03_rolling_statistics.R")) {
  source("R/03_rolling_statistics.R", local = TRUE)
}

PRIMARY_PREDICTORS <- c(
  "rise_slope",
  "max_roc",
  "mean_pos_roc",
  "rise_duration_min",
  "bg_flux"
)

# -----------------------------------------------------------------------------
# Safe data helpers
# -----------------------------------------------------------------------------
read_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(
    read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
}

fmt_num <- function(x, digits = 3) {
  if (length(x) == 0 || is.na(x) || !is.finite(x)) return("—")
  formatC(x, format = "f", digits = digits)
}

fmt_sci <- function(x, digits = 3) {
  if (length(x) == 0 || is.na(x) || !is.finite(x)) return("—")
  formatC(x, format = "e", digits = digits)
}

fmt_time <- function(x) {
  if (length(x) == 0 || is.na(x)) return("—")
  format(as.POSIXct(x, tz = "UTC"), "%Y-%m-%d %H:%M UTC")
}

artifact_notice <- function(path, label = basename(path)) {
  div(
    class = "artifact-missing",
    tags$strong("Saved scientific artifact not available in this project snapshot"),
    tags$br(),
    tags$code(label),
    tags$br(),
    span("The GUI will use it automatically when the authoritative Stage 8 runner output is present. No fallback score is fabricated.")
  )
}

metric_card <- function(value, label, note = NULL, class = "") {
  div(
    class = paste("metric-card", class),
    div(class = "metric-value", value),
    div(class = "metric-label", label),
    if (!is.null(note)) div(class = "metric-note", note)
  )
}


story_step <- function(icon, title, text) {
  div(
    class = "story-step",
    div(class = "story-icon", icon),
    div(
      class = "story-step-copy",
      div(class = "story-step-title", title),
      div(class = "story-step-text", text)
    )
  )
}

story_arrow <- function() {
  div(class = "story-arrow", "↓")
}

explain_card <- function(what, why, sml, technical = NULL) {
  div(
    class = "explain-card",
    div(class = "explain-kicker", "WHAT IS HAPPENING?"),
    p(what),
    div(class = "explain-kicker", "WHY DO WE NEED IT?"),
    p(why),
    div(class = "explain-kicker", "SML CONNECTION"),
    p(sml),
    if (!is.null(technical)) {
      tags$details(
        class = "technical-details",
        tags$summary("Technical details"),
        div(class = "details-body", technical)
      )
    }
  )
}

math_concept <- function(title, question, formula, project_use, technical = NULL) {
  div(
    class = "math-box teaching-math",
    div(class = "formula-title", title),
    div(class = "plain-question", question),
    div(class = "formula-eq", formula),
    div(class = "project-use", tags$strong("In this project: "), project_use),
    if (!is.null(technical)) div(class = "formula-desc", technical)
  )
}

flow_row <- function(items) {
  tags$div(
    class = "flow-row",
    lapply(seq_along(items), function(i) {
      tagList(
        div(class = "flow-node", items[[i]]),
        if (i < length(items)) div(class = "flow-arrow-inline", "→")
      )
    })
  )
}

# -----------------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------------
ui <- fluidPage(
  tags$head(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$style(HTML("
      :root {
        --bg: #f6fbff;
        --panel: #ffffff;
        --panel2: #eef7ff;
        --line: #d6e6f2;
        --text: #173047;
        --muted: #657c8f;
        --accent: #0f6fc6;
        --accent2: #27856e;
        --warn: #e3a12b;
        --danger: #c9604d;
        --soft: #edf7ff;
        --navy: #08265f;
      }
      body { background: linear-gradient(180deg,#ffffff 0%,#f5faff 100%); color: var(--text); font-family: 'Segoe UI', Arial, sans-serif; }
      .container-fluid { max-width: 1600px; padding: 0 24px 42px; }
      h1,h2,h3,h4 { color: var(--navy); }
      h2,h3 { font-family: Georgia,'Times New Roman',serif; }
      p, li, label { color: var(--text); line-height: 1.58; }
      code, pre { background: #edf6fc; color: #17577f; border: 1px solid var(--line); }
      .nav-tabs { border-color: var(--line); position: sticky; top: 0; z-index: 20; background: rgba(246,251,255,.96); padding-top: 8px; }
      .nav-tabs > li > a { color: #41627d; background: #ffffff; border-color: var(--line); font-size: 12px; font-weight: 700; }
      .nav-tabs > li.active > a, .nav-tabs > li.active > a:focus, .nav-tabs > li.active > a:hover { color: white; background: var(--accent); border-color: var(--accent); }
      .app-title { margin: 24px 0 4px; font-weight: 700; letter-spacing: .1px; color: var(--navy); }
      .subtitle { color: #4f687d; margin-bottom: 4px; font-size: 16px; }
      .technical-subtitle { color: var(--accent); text-transform: uppercase; letter-spacing: 1px; font-size: 11px; font-weight: 800; margin-top: 2px; margin-bottom: 16px; }
      .presentation-strip { background:#fff; border:1px solid var(--line); border-left:4px solid var(--warn); border-radius:10px; padding:10px 14px; margin:0 0 16px; color:#4e6274; }
      .hero-card, .section-card, .math-box, .metric-card, .artifact-missing, .scientific-note, .warning-note, .explain-card, .syllabus-card {
        background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px; margin-bottom: 14px;
        box-shadow: 0 8px 24px rgba(24,79,122,.05);
      }
      .hero-card { background: linear-gradient(135deg,#ffffff 0%,#edf7ff 100%); border-color:#bcd8ec; padding:22px; }
      .hero-lead { font-size: 18px; line-height:1.65; color:#24455e; max-width:1000px; }
      .section-card { min-height:100%; }
      .metric-card { text-align:center; min-height:108px; }
      .metric-value { color:var(--accent); font-size:24px; font-weight:800; line-height:1.25; }
      .metric-label { color:#425e73; font-size:11px; font-weight:800; text-transform:uppercase; letter-spacing:.5px; }
      .metric-note { color:var(--muted); font-size:11px; margin-top:6px; }
      .math-box { border-left:4px solid var(--accent); }
      .teaching-math { min-height:190px; }
      .formula-title { color:var(--accent); font-weight:800; font-size:16px; }
      .plain-question { color:#27465e; margin:8px 0 2px; font-size:14px; font-weight:600; }
      .formula-eq { color:var(--navy); font-family:'Cambria Math','Times New Roman',serif; font-size:18px; margin:9px 0; white-space:pre-wrap; }
      .formula-desc,.project-use { color:#557086; font-size:13px; margin-top:8px; }
      .artifact-missing { border-left:4px solid var(--warn); color:#7a5514; background:#fff8e8; }
      .scientific-note { border-left:4px solid var(--accent2); background:#f1fbf8; }
      .warning-note { border-left:4px solid var(--warn); background:#fff8e8; }
      .danger-note { border-left:4px solid var(--danger); background:#fff2ef; }
      .big-idea { border-left:4px solid var(--accent); background:#eef7ff; }
      .small-muted { color:var(--muted); font-size:12px; }
      .read-only-config td:first-child { font-weight:700; color:#225f8b; }
      table { color:#173047; background:white; }
      .dataTables_wrapper { color:var(--text); }
      .form-control, .selectize-input { background:#fff; color:#173047; border-color:#b8d0e2; }
      .selectize-dropdown { color:#17212b; }
      .shiny-output-error-validation { color:#9a6510; }
      hr { border-color:var(--line); }
      .story-stack { max-width:760px; margin:12px auto 18px; }
      .story-step { display:flex; align-items:center; gap:14px; background:var(--soft); border:1px solid var(--line); border-radius:10px; padding:11px 14px; }
      .story-icon { width:42px; text-align:center; font-size:23px; }
      .story-step-title { font-weight:800; color:var(--navy); }
      .story-step-text { font-size:12px; color:var(--muted); }
      .story-arrow { text-align:center; color:var(--accent); font-size:21px; line-height:1.1; padding:3px; }
      .flow-row { display:flex; flex-wrap:wrap; align-items:center; justify-content:center; gap:8px; margin:16px 0; }
      .flow-node { background:#edf7ff; border:1px solid #bcd8ec; border-radius:8px; padding:10px 13px; font-weight:800; color:#195b89; text-align:center; }
      .flow-arrow-inline { color:var(--warn); font-size:20px; font-weight:700; }
      .explain-card { border-top:3px solid var(--accent2); background:#fff; }
      .explain-kicker { color:var(--accent2); font-size:10px; font-weight:900; letter-spacing:.8px; margin-top:8px; }
      .technical-details { margin-top:11px; border-top:1px solid var(--line); padding-top:8px; }
      .technical-details summary { cursor:pointer; color:#195f91; font-weight:800; }
      .details-body { padding:10px 4px 0; color:#4f687d; }
      .unit-heading { border-bottom:1px solid var(--line); padding-bottom:7px; margin-top:24px; color:var(--navy); }
      .syllabus-card { background:#eef7ff; border-color:#bcd8ec; }
      .syllabus-unit { border-left:3px solid var(--accent); padding-left:11px; margin:10px 0; }
      .feature-name { color:var(--accent); font-weight:800; font-family:Consolas,monospace; }
      .feature-question { color:#294c67; font-size:15px; }
      .warning-banner { padding:16px; border-radius:10px; border:1px solid #ebce94; border-left:5px solid var(--warn); background:#fff8e8; margin:14px 0; color:#684914; }
      .mini-definition { color:#4c667b; background:#f5faff; border:1px solid var(--line); border-radius:8px; padding:10px 12px; margin:9px 0; }
      .success-list li { margin-bottom:9px; }
      .cannot-list li { margin-bottom:7px; color:#8c4438; }
      @media (max-width:900px) {
        .flow-arrow-inline { display:none; }
        .flow-row { align-items:stretch; }
        .flow-node { width:100%; }
      }
    "))
  ),

  h2(class = "app-title", "Statistical Detection and Classification of Solar Activity"),
  div(class = "subtitle",
      "A guided scientific investigation using NOAA/GOES soft X-ray time-series data"),
  div(class = "technical-subtitle",
      "Statistical event detection · NOAA alignment · Impulsive-phase B vs C+ severity nowcasting"),

  div(class = "presentation-strip",
      tags$strong("Presentation mode: "),
      "follow tabs 1 → 9 as one scientific story. Each tab explains the idea first and then shows the project evidence."
  ),

  tabsetPanel(
    id = "main_tabs",

    # -------------------------------------------------------------------------
    # TAB 1 — MEET THE SUN
    # -------------------------------------------------------------------------
    tabPanel("1. ☀ Meet the Sun",
      h3("☀ Meet the Sun"),
      div(class = "technical-subtitle", "Project Overview · Research Question · Scientific Scope"),
      div(class = "hero-card",
        p(class = "hero-lead",
          "The Sun is constantly changing. One way we observe that activity is through soft X-rays measured by GOES satellites. ",
          "This project follows those measurements from raw time-series data to statistical event detection and, finally, a small B-versus-C+ severity-classification experiment."
        )
      ),
      div(class = "story-stack",
        story_step("☀", "THE SUN", "The physical source of changing solar X-ray emission."),
        story_arrow(),
        story_step("≈", "SOFT X-RAYS", "Energy emitted by the Sun and measured as flux."),
        story_arrow(),
        story_step("🛰", "GOES SATELLITE", "Records repeated X-ray measurements over time."),
        story_arrow(),
        story_step("〽", "TIME-SERIES DATA", "Measurements arranged in time order."),
        story_arrow(),
        story_step("Σ", "STATISTICAL ANALYSIS", "Estimate normal background and measure unusual behavior."),
        story_arrow(),
        story_step("!", "SOLAR EVENTS", "Sustained unusual observations are grouped into events."),
        story_arrow(),
        story_step("B/C+", "SEVERITY CLASSIFICATION", "At the observed peak, classify the event as B or C+.")
      ),
      fluidRow(
        column(7,
          div(class = "section-card",
            h4("Central research question"),
            p(style="font-size:17px;",
              "Can statistical methods help us identify unusual solar X-ray activity and distinguish B-class events from C-or-above events?"
            ),
            div(class = "scientific-note",
              tags$strong("Scientific scope"), tags$br(),
              "This project performs impulsive-phase severity nowcasting at ",
              tags$code("t_pred = t_peak"),
              ". It is NOT a forecasting system."
            )
          )
        ),
        column(5,
          div(class = "section-card big-idea",
            h4("THE BIG IDEA"),
            p("Learn what normal looks like → detect what is unusual → describe the event → test whether its shape contains information about severity."),
            hr(),
            tags$strong("Course connection"),
            p("Units I–III provide the statistical foundation. Classification is a project extension.")
          )
        )
      ),
      explain_card(
        "GOES gives us a sequence of X-ray measurements from the Sun.",
        "A sequence lets us compare the current observation with recent background behavior.",
        "Random variables, time-ordered observations, mean, variance and standard deviation.",
        tags$p("The frozen scientific pipeline is: preprocessing → rolling statistics → anomaly detection → event segmentation → NOAA alignment → feature extraction → B vs C+ nowcasting → evaluation.")
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 2 — MATHEMATICS
    # -------------------------------------------------------------------------
    tabPanel("2. 📚 Mathematics Behind It",
      h3("📚 Mathematics Behind It"),
      div(class = "technical-subtitle", "Statistical Foundation · Units I–III · Classical ML Extension"),
      div(class = "hero-card",
        p(class = "hero-lead",
          "The formulas are not separate decorations. Each one answers a specific question in the solar X-ray problem: ",
          "Where is the recent background? How much does it vary? How unusual is the current point? How quickly is the signal rising?"
        )
      ),

      h3(class = "unit-heading", "SECTION A — WHAT WE LEARNED IN CLASS"),
      h4("UNIT I — Random Variables & Basic Statistics"),
      fluidRow(
        column(6,
          math_concept(
            "X-ray flux as a random variable",
            "What is one observation?",
            "X = measured soft X-ray flux",
            "Each one-minute measurement is one observed value of the changing solar X-ray signal.",
            "Across time, the observed values form a time series rather than independent repeated trials."
          ),
          math_concept(
            "MEAN",
            "Where is the recent X-ray background centered?",
            "x̄ = (1/n) Σ xᵢ",
            "Estimate the recent background level."
          ),
          math_concept(
            "VARIANCE",
            "How spread out are recent observations around their mean?",
            "s² = (1/(n−1)) Σ(xᵢ−x̄)²",
            "Quantify recent variability before converting it to standard deviation."
          )
        ),
        column(6,
          math_concept(
            "STANDARD DEVIATION",
            "How much does the recent background normally vary?",
            "s = √[(1/(n−1)) Σ(xᵢ−x̄)²]",
            "Measure typical spread around the local background."
          ),
          math_concept(
            "MEDIAN",
            "What is the middle background value if a few observations are extreme?",
            "median(x)",
            "Provide a center that is less affected by large flare values."
          ),
          math_concept(
            "MAD — Median Absolute Deviation",
            "Can we measure spread without letting extreme flare values dominate?",
            "MAD_raw = median(|xᵢ−median(x)|)\nMAD_scaled = 1.4826 × MAD_raw",
            "Provide a robust local spread estimate. The scale factor is applied exactly once."
          )
        )
      ),

      h4("UNIT II — Statistical Reasoning"),
      div(class = "section-card",
        p("The Sun's background changes with time, so we repeatedly calculate statistics using recent observations."),
        div(class = "scientific-note",
          tags$strong("Plain-language idea: "),
          "estimate the recent background using only earlier observations. This moving calculation is called a ",
          tags$strong("rolling statistic"), "."
        )
      ),
      fluidRow(
        column(6,
          math_concept(
            "ROLLING STATISTICS",
            "How do we adapt when the background changes over time?",
            "baseline(t) uses recent observations before t",
            "Recalculate the local center and spread as time moves forward.",
            "The current point is excluded from its own trailing baseline."
          ),
          math_concept(
            "STANDARD Z-SCORE",
            "How unusual is this observation relative to recent background?",
            "z = (x − μ) / σ",
            "Express distance from the recent background in standard-deviation units.",
            "z ≈ 0: near background; z ≈ 1: somewhat above; z ≈ 2: noticeably above; z ≈ 3: strongly unusual."
          )
        ),
        column(6,
          math_concept(
            "ROBUST Z-SCORE",
            "How unusual is this point if extreme values might distort mean and SD?",
            "zᵣ = (x − median) / MAD_scaled",
            "Measure unusual behavior using median/MAD, which is less affected by extremes."
          ),
          math_concept(
            "RATE OF CHANGE & LOCAL SLOPE",
            "Is the X-ray signal rising quickly and consistently?",
            "ROCₜ = (xₜ−xₜ₋₁)/Δt\nx = β₀ + β₁t + ε",
            "Measure sudden change (ROC) and sustained directional rise (local slope)."
          )
        )
      ),
      div(class = "warning-note",
        tags$strong("Important statistical distinction: "),
        "our detector uses the idea of statistical standardization. It is not itself a formal Z-test with a p-value."
      ),

      h4("UNIT III — Estimation & Statistical Inference"),
      fluidRow(
        column(7,
          div(class = "section-card",
            p("Only the inference ideas genuinely used by the project are connected here:"),
            tags$ul(
              tags$li(tags$strong("Local mean / median → "), "an estimate of current background level."),
              tags$li(tags$strong("Local SD / MAD → "), "an estimate of current background variability."),
              tags$li(tags$strong("Standardization → "), "a common scale for comparing the current observation with its recent background."),
              tags$li(tags$strong("Held-out evaluation → "), "an empirical check on classification behavior using events not used to train the model.")
            )
          )
        ),
        column(5,
          div(class = "section-card",
            h4("Why don't we use every syllabus topic?"),
            p("Statistical methods were selected according to the structure of the solar X-ray problem. Not every syllabus method is necessary for this particular experiment."),
            p(class="small-muted",
              "We do not pretend that Bayes theorem, t-tests, chi-square tests, F-tests, MLE, or Bayesian estimation were used when they were not."
            )
          )
        )
      ),

      h3(class = "unit-heading", "SECTION B — PROJECT EXTENSION"),
      p("After the statistical event pipeline converts each event into numerical features, classical classifiers are used as a project extension."),
      fluidRow(
        column(4,
          math_concept(
            "LOGISTIC REGRESSION",
            "What is the estimated probability that an observed event is C+?",
            "P(C+|X) = 1 / [1 + exp(−(β₀ + βᵀX))]",
            "Primary frozen Stage 8 classifier. Complete separation makes ordinary coefficient inference unstable in this small sample."
          )
        ),
        column(4,
          math_concept(
            "DECISION TREE",
            "Can a sequence of if-then splits separate the classes?",
            "Gini = 1 − Σ pₖ²",
            "Provide an interpretable nonlinear comparison model."
          )
        ),
        column(4,
          math_concept(
            "RANDOM FOREST",
            "What if many decision trees vote together?",
            "ŷ = mode(ŷ¹, …, ŷᴮ)",
            "Provide an ensemble comparison model. Importance is descriptive, not causal."
          )
        )
      ),
      fluidRow(
        column(6,
          math_concept(
            "PRECISION / RECALL / F1",
            "How do we evaluate class-specific mistakes rather than accuracy alone?",
            "Precision = TP/(TP+FP)\nRecall = TP/(TP+FN)\nF1 = 2PR/(P+R)",
            "Evaluate B and C+ prediction behavior."
          )
        ),
        column(6,
          math_concept(
            "BALANCED ACCURACY",
            "How do we give both classes equal importance despite unequal support?",
            "BA = (Sensitivity + Specificity)/2",
            "Complement Macro-F1 in the frozen evaluation."
          )
        )
      ),

      div(class = "syllabus-card",
        h3("COURSE SYLLABUS → PROJECT"),
        fluidRow(
          column(3, div(class="syllabus-unit", h4("UNIT I"), p("Random variables\nMean\nVariance\nStandard deviation\nDistributions", style="white-space:pre-line;"))),
          column(3, div(class="syllabus-unit", h4("UNIT II"), p("Statistical variation\nStandardization\nRandom/data reasoning", style="white-space:pre-line;"))),
          column(3, div(class="syllabus-unit", h4("UNIT III"), p("Parameter estimation\nStatistical inference concepts", style="white-space:pre-line;"))),
          column(3, div(class="syllabus-unit", h4("PROJECT EXTENSION"), p("Logistic Regression\nDecision Tree\nRandom Forest", style="white-space:pre-line;")))
        ),
        p(class="small-muted", "Classification extends beyond the currently covered Units I–III; the earlier units provide the statistical foundation for the time-series and anomaly-analysis stages.")
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 3 — EXPLORE GOES DATA
    # -------------------------------------------------------------------------
    tabPanel("3. 📡 Explore GOES Data",
      h3("📡 Explore GOES Data"),
      div(class = "technical-subtitle", "GOES XRS-B · Cleaned Soft X-Ray Time Series · Data Provenance"),
      div(class = "hero-card",
        p(class="hero-lead",
          "Imagine measuring the Sun's X-ray intensity repeatedly over time. One observation is one measured flux value. ",
          "Many observations arranged by time form a time series."
        )
      ),
      uiOutput("goes_metric_cards"),
      fluidRow(
        column(4,
          div(class="section-card",
            h4("WHAT SHOULD I LOOK FOR?"),
            p("Most observations form the changing background. Sharp increases may indicate solar activity."),
            hr(),
            h4("Visualization window"),
            dateRangeInput("goes_dates", "UTC date range", start = Sys.Date()-7, end = Sys.Date()),
            checkboxInput("show_class_levels", "Show B/C/M/X reference levels", value = TRUE),
            p(class="small-muted", "These controls change visualization only. They do not alter preprocessing, detection, or model inputs.")
          ),
          explain_card(
            "GOES gives repeated X-ray flux measurements.",
            "We need an observed signal before statistics can tell us what is usual or unusual.",
            "Observed random variable + time-series data."
          )
        ),
        column(8,
          div(class="section-card",
            h4("Real GOES XRS-B signal"),
            plotOutput("goes_plot", height="520px"),
            p(class="small-muted", "The Y-axis is logarithmic because solar X-ray flux spans several orders of magnitude.")
          )
        )
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 4 — WHAT IS NORMAL?
    # -------------------------------------------------------------------------
    tabPanel("4. 📊 What Is \"Normal\"?",
      h3("📊 What Is \"Normal\"?"),
      div(class = "technical-subtitle", "Statistical Baseline · Rolling Statistics · Standardization"),
      div(class = "hero-card",
        p(class="hero-lead",
          "Before detecting something unusual, we need to know what usual looks like. ",
          "Because the solar background changes with time, the project estimates a moving local baseline from recent earlier observations."
        )
      ),
      fluidRow(
        column(9,
          div(class="section-card",
            h4("A. FIND THE CENTER"),
            p("Mean / median = where the recent background is centered."),
            h4("B. MEASURE THE SPREAD"),
            p("Standard deviation / MAD = how much the recent background normally varies."),
            h4("C. MEASURE HOW UNUSUAL"),
            p("Standard Z / robust Z = how far the current point sits above its local background."),
            h4("D. MEASURE HOW FAST IT CHANGES"),
            p("ROC / local slope = how quickly and consistently the signal is changing."),
            plotOutput("rolling_panels", height="850px")
          )
        ),
        column(3,
          div(class="section-card",
            h4("Read-only detector configuration"),
            tableOutput("detector_config_table"),
            div(class="scientific-note",
              tags$strong("Why read-only?"), tags$br(),
              "These values belong to the frozen scientific pipeline. The GUI explains them; it does not tune them."
            )
          ),
          explain_card(
            "The app repeatedly summarizes recent earlier observations.",
            "A fixed global average would not represent a background that changes with time.",
            "Rolling mean/median, rolling spread, Z-score and robust statistics.",
            tags$p("The official detector settings are displayed but cannot be changed from this GUI.")
          )
        )
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 5 — DETECT AN UNUSUAL EVENT
    # -------------------------------------------------------------------------
    tabPanel("5. 🚨 Detect an Unusual Event",
      h3("🚨 Detect an Unusual Event"),
      div(class = "technical-subtitle", "Statistical Event Detection & NOAA Alignment"),
      div(class = "hero-card",
        p(class="hero-lead",
          "One unusual point may be noise. A sustained sequence of unusual observations may represent an event."
        ),
        flow_row(c("NORMAL", "UNUSUAL OBSERVATIONS", "GROUP THEM", "SOLAR EVENT"))
      ),
      fluidRow(
        column(4,
          div(class="section-card",
            selectInput("event_id", "Select aligned physical event", choices = character(0)),
            uiOutput("event_details"),
            hr(),
            h4("OUR DETECTOR → NOAA RECORD"),
            uiOutput("alignment_details"),
            div(class="mini-definition",
              tags$strong("Why NOAA? "),
              "NOAA provides an external reference for checking whether our detected event corresponds to an officially recorded solar flare."
            )
          )
        ),
        column(8,
          div(class="section-card",
            h4("Selected event: START → PEAK → END"),
            plotOutput("event_plot", height="520px"),
            p(class="small-muted", "Peak flux is shown here as a descriptive property of the event, not as a primary ML predictor.")
          )
        )
      ),
      div(class="section-card",
        h4("Event-level detector / alignment summary"),
        uiOutput("detector_summary_ui"),
        p(class="small-muted", "The GUI never reconstructs a missing NOAA peak timestamp or fabricates unmatched-event metrics.")
      ),
      explain_card(
        "Statistically unusual observations are grouped into a physical event interval.",
        "Persistence helps distinguish an event from a single noisy point; NOAA alignment gives an external reference.",
        "Anomaly detection, persistence, event segmentation and validation against reference labels."
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 6 — DESCRIBE THE EVENT
    # -------------------------------------------------------------------------
    tabPanel("6. 🔥 Describe the Event",
      h3("🔥 Describe the Event"),
      div(class = "technical-subtitle", "Event Morphology · Feature Engineering · B vs C+ Descriptive Analysis"),
      div(class = "hero-card",
        p(class="hero-lead", "Every event has a shape. We convert that shape into numbers."),
        flow_row(c("START", "RISE", "PEAK", "DECAY", "END"))
      ),
      fluidRow(
        column(4,
          div(class="section-card",
            div(class="feature-name", "1. rise_slope"),
            p(class="feature-question", "How quickly is the signal rising?"),
            div(class="feature-name", "2. max_roc"),
            p(class="feature-question", "What's the fastest observed rise?"),
            div(class="feature-name", "3. mean_pos_roc"),
            p(class="feature-question", "How strongly does it rise on average?"),
            div(class="feature-name", "4. rise_duration_min"),
            p(class="feature-question", "How long does the rise take?"),
            div(class="feature-name", "5. bg_flux"),
            p(class="feature-question", "What was the background level?")
          ),
          div(class="warning-banner",
            tags$strong("PEAK FLUX IS DESCRIPTIVE ONLY."), tags$br(),
            "Peak flux is not used as a primary predictor because NOAA flare class is defined from peak X-ray flux."
          )
        ),
        column(4,
          div(class="section-card",
            h4("B vs C+ morphology"),
            selectInput("morph_feature", "Choose one primary predictor", choices = PRIMARY_PREDICTORS, selected = "rise_slope"),
            plotOutput("morph_boxplot", height="420px"),
            p(class="small-muted", "These plots describe the observed sample. They do not imply causation.")
          )
        ),
        column(4,
          div(class="section-card",
            h4("Overlapping information"),
            plotOutput("rise_corr_plot", height="370px"),
            p("The three rise-rate variables are strongly correlated, so they carry overlapping statistical information."),
            p(class="small-muted", "This is why multicollinearity is reported later as a diagnostic limitation."),
            uiOutput("morph_support_cards")
          )
        )
      ),
      div(class="section-card",
        h4("Deduplicated physical-event table"),
        p("Descriptive event variables and the five primary predictors are shown together for inspection. Descriptive appearance does not make a variable a model predictor."),
        tableOutput("event_table")
      ),
      explain_card(
        "The curve from START to PEAK is summarized into numerical measurements.",
        "A classifier cannot directly reason about a plotted curve; it needs consistent numerical descriptors.",
        "Feature engineering: convert observed event morphology into measurements while respecting t_pred = t_peak.",
        tags$p("The corrected ROC-derived predictors use START→PEAK observations only.")
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 7 — CLASSIFY
    # -------------------------------------------------------------------------
    tabPanel("7. 🤖 Can We Classify It?",
      h3("🤖 Can We Classify It?"),
      div(class = "technical-subtitle", "Impulsive-Phase Flare Severity Nowcasting · Frozen Stage 8 Model"),
      div(class = "hero-card",
        p(class="hero-lead",
          "We now have a numerical description of each event. Can these measurements distinguish weaker B-class events from C-or-above events?"
        ),
        flow_row(c("EVENT", "FIVE FEATURES", "CLASSIFIER", "B OR C+"))
      ),
      fluidRow(
        column(4,
          div(class="section-card",
            tags$strong("Prediction point"), p(tags$code("t_pred = t_peak")),
            tags$strong("Target"), p("B vs C+"),
            tags$strong("Five primary predictors"), tags$ol(lapply(PRIMARY_PREDICTORS, tags$li)),
            div(class="scientific-note", "ROC-derived predictors use only START→PEAK observations."),
            div(class="warning-note", "This is nowcasting, not forecasting."),
            div(class="warning-banner",
              "Peak flux is not used as a primary ML predictor because NOAA flare class is defined from peak X-ray flux."
            )
          )
        ),
        column(8,
          div(class="section-card",
            h4("The three model ideas — in plain language"),
            fluidRow(
              column(4, div(class="mini-definition", tags$strong("LOGISTIC REGRESSION"), tags$br(), "Estimates the probability of C+.")),
              column(4, div(class="mini-definition", tags$strong("DECISION TREE"), tags$br(), "Uses a sequence of if-then decisions.")),
              column(4, div(class="mini-definition", tags$strong("RANDOM FOREST"), tags$br(), "Combines many decision trees."))
            ),
            tags$details(
              class="technical-details",
              tags$summary("Show technical detail"),
              div(class="details-body",
                p("Logistic: P(C+|X) = 1 / [1 + exp(−(β₀ + βᵀX))]"),
                p("Decision Tree: chooses splits that reduce class impurity such as Gini impurity."),
                p("Random Forest: aggregates predictions from many trees. The frozen project does not treat feature importance as causation.")
              )
            ),
            hr(),
            h4("Frozen final-test prediction"),
            uiOutput("nowcast_selector_ui"),
            uiOutput("nowcast_details")
          )
        )
      ),
      explain_card(
        "The frozen classifier receives five numbers describing an event through its observed peak.",
        "The experiment asks whether those measurements carry enough class information to distinguish B from C+ in this sample.",
        "Binary classification, probability, decision rules and held-out evaluation.",
        tags$p("The GUI displays saved Stage 8 predictions only. It does not fit a model.")
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 8 — TEST THE EXPERIMENT
    # -------------------------------------------------------------------------
    tabPanel("8. 🧪 Test the Experiment",
      h3("🧪 Test the Experiment"),
      div(class = "technical-subtitle", "Chronological Evaluation · Final Holdout · Robustness Diagnostics"),
      div(class = "hero-card",
        p(class="hero-lead", "Now we test whether our experiment worked."),
        flow_row(c("31 EVENTS", "18 TRAIN", "6 DEVELOPMENT", "7 FINAL TEST")),
        fluidRow(
          column(4, div(class="mini-definition", tags$strong("TRAINING"), tags$br(), "Teaches the model from the earliest events.")),
          column(4, div(class="mini-definition", tags$strong("DEVELOPMENT"), tags$br(), "Helps compare the predefined model candidates.")),
          column(4, div(class="mini-definition", tags$strong("FINAL TEST"), tags$br(), "Used only after the model-selection decision."))
        )
      ),
      div(class="warning-note",
        "Development comparison and final-test evaluation are shown separately. The final test is not used for model selection."
      ),
      h4("A. DEVELOPMENT RESULTS"),
      p("These results compare the predefined Logistic Regression, Decision Tree and Random Forest on the six-event development period."),
      uiOutput("dev_results_ui"),
      plotOutput("dev_metric_plot", height="360px"),
      hr(),
      h4("B. FINAL CHRONOLOGICAL TEST"),
      uiOutput("final_split_cards"),
      fluidRow(
        column(5, div(class="section-card", h4("Confusion matrix"), tableOutput("final_cm_table"))),
        column(7, div(class="section-card", h4("Seven-event prediction table"), tableOutput("final_prediction_table")))
      ),
      div(class="warning-banner",
        tags$strong("Interpret carefully: "),
        "the frozen final test contains only seven events. Its observed 7/7 correctness does not establish generalization."
      ),
      hr(),
      h4("C. ROBUSTNESS — HOW FRAGILE IS THE RESULT?"),
      fluidRow(
        column(4, div(class="mini-definition", tags$strong("LOOCV"), tags$br(), "Repeat training while leaving out one event at a time.")),
        column(4, div(class="mini-definition", tags$strong("MULTICOLLINEARITY"), tags$br(), "Some predictors carry very similar information.")),
        column(4, div(class="mini-definition", tags$strong("SEPARATION / CONVERGENCE"), tags$br(), "The classes are completely separated by predictors in this small training sample, making ordinary Logistic coefficients unstable."))
      ),
      uiOutput("robustness_ui"),
      fluidRow(
        column(6, div(class="section-card", h4("Training VIF"), tableOutput("vif_table"),
                      p(class="small-muted","Large VIF values indicate predictor redundancy and unstable coefficient interpretation."))),
        column(6, div(class="section-card", h4("Separation / convergence"), uiOutput("separation_ui")))
      ),
      explain_card(
        "The experiment is evaluated on events that occur later in time than the training data.",
        "Keeping the final test separate reduces the chance of reporting a score that influenced model choice.",
        "Train/development/test design, confusion matrix, Macro-F1, balanced accuracy and robustness checks."
      )
    ),

    # -------------------------------------------------------------------------
    # TAB 9 — WHAT DID WE LEARN?
    # -------------------------------------------------------------------------
    tabPanel("9. 🧠 What Did We Learn?",
      h3("🧠 What Did We Learn?"),
      div(class = "technical-subtitle", "Scientific Conclusions · Limitations · Scope of Evidence"),
      div(class = "hero-card",
        p(class="hero-lead",
          "The final step is not to celebrate a score. It is to state clearly what the experiment demonstrates and what the evidence is too small to support."
        )
      ),
      fluidRow(
        column(6,
          div(class="section-card",
            h3("WHAT WE DEMONSTRATED"),
            tags$ul(class="success-list",
              tags$li("☀ Real GOES X-ray data can be analyzed as a time series."),
              tags$li("📊 Basic statistics can describe changing background behavior."),
              tags$li("🚨 Statistical standardization can identify unusual observations."),
              tags$li("🔥 Sustained unusual observations can be grouped into events."),
              tags$li("🛰 Events can be compared with NOAA records."),
              tags$li("📐 Event morphology can be converted into numerical features."),
              tags$li("🤖 Those features can support a B vs C+ classification experiment.")
            )
          )
        ),
        column(6,
          div(class="section-card",
            h3("WHAT WE CANNOT CLAIM"),
            tags$ul(class="cannot-list",
              tags$li("Operational forecasting or early warning"),
              tags$li("Production readiness"),
              tags$li("Broad population generalization"),
              tags$li("Superiority of one algorithm"),
              tags$li("Causal interpretation of individual features")
            )
          )
        )
      ),
      div(class="section-card",
        h3("Actual limitations that remain"),
        fluidRow(
          column(6,
            tags$ul(
              tags$li(tags$strong("N = 31"), " ML-eligible independent physical events."),
              tags$li(tags$strong("Final test N = 7"), "; 7/7 is an observed holdout result, not a population guarantee."),
              tags$li("Ordinary Logistic Regression exhibits complete separation and convergence warnings."),
              tags$li("rise_slope, max_roc and mean_pos_roc have high multicollinearity.")
            )
          ),
          column(6,
            tags$ul(
              tags$li("Detector selection and NOAA matching influence the event population."),
              tags$li("A target-proxy interpretation concern remains at the observed peak."),
              tags$li("External temporal / instrument / solar-cycle validation is absent."),
              tags$li("This remains an undergraduate proof-of-concept.")
            )
          )
        )
      ),
      div(class="scientific-note",
        style="font-size:17px;",
        "This project is an undergraduate statistical proof-of-concept showing how concepts from statistical analysis can be extended toward solar-event detection and severity classification."
      ),
      div(class="story-stack",
        story_step("☀", "SUN", "Physical source"),
        story_arrow(),
        story_step("≈", "X-RAYS", "Measured signal"),
        story_arrow(),
        story_step("〽", "DATA", "Time series"),
        story_arrow(),
        story_step("μ", "NORMAL", "Local statistical background"),
        story_arrow(),
        story_step("z", "UNUSUAL", "Standardized anomaly"),
        story_arrow(),
        story_step("!", "EVENT", "Persistent observations grouped"),
        story_arrow(),
        story_step("🛰", "NOAA", "External event reference"),
        story_arrow(),
        story_step("∿", "EVENT SHAPE", "Rise-phase morphology"),
        story_arrow(),
        story_step("X", "FEATURES", "Numerical event description"),
        story_arrow(),
        story_step("B/C+", "CLASSIFICATION", "Frozen nowcasting experiment"),
        story_arrow(),
        story_step("✓", "TEST", "Chronological holdout and robustness"),
        story_arrow(),
        story_step("⚠", "LIMITATIONS", "What the evidence cannot support")
      )
    )
  )
)


# -----------------------------------------------------------------------------
# SERVER
# -----------------------------------------------------------------------------
server <- function(input, output, session) {

  # ---------------------------------------------------------------------------
  # Authoritative scientific data loaders
  # ---------------------------------------------------------------------------
  clean_data_all <- reactive({
    df <- read_csv_if_exists("data/processed/goes_xrs_cleaned.csv")
    validate(need(!is.null(df), "Cleaned GOES dataset is unavailable."))
    df$time_tag <- as.POSIXct(df$time_tag, tz = "UTC")
    df
  })

  xrs_b <- reactive({
    df <- clean_data_all()
    out <- df[df$energy == "0.1-0.8nm", , drop = FALSE]
    out[order(out$time_tag), , drop = FALSE]
  })

  events <- reactive({
    df <- read_csv_if_exists("data/processed/labeled_events_deduplicated.csv")
    validate(need(!is.null(df), "Deduplicated labeled-event dataset is unavailable."))
    for (nm in intersect(c("start_time", "peak_time", "end_time"), names(df))) {
      df[[nm]] <- as.POSIXct(df[[nm]], tz = "UTC")
    }
    df$severity_class <- ifelse(
      df$noaa_class_letter == "B", "B",
      ifelse(df$noaa_class_letter %in% c("C", "M"), "C_plus", NA_character_)
    )
    df
  })

  # Authoritative Stage 8 artifacts generated by R/run_stage8_ml.R.
  stage8_train <- reactive(read_csv_if_exists("data/processed/stage8_train.csv"))
  stage8_dev <- reactive(read_csv_if_exists("data/processed/stage8_development.csv"))
  stage8_test <- reactive(read_csv_if_exists("data/processed/stage8_final_test.csv"))
  dev_results <- reactive(read_csv_if_exists("reports/STAGE8_MODEL_COMPARISON.csv"))
  final_results <- reactive(read_csv_if_exists("reports/STAGE8_ML_RESULTS.csv"))
  final_predictions <- reactive(read_csv_if_exists("reports/STAGE8_FINAL_TEST_PREDICTIONS.csv"))
  final_cm <- reactive(read_csv_if_exists("reports/STAGE8_CONFUSION_MATRICES.csv"))
  loocv_primary <- reactive(read_csv_if_exists("reports/STAGE8_ROBUSTNESS.csv"))
  vif_current <- reactive({
    x <- read_csv_if_exists("reports/STAGE8_TRAIN_VIF.csv")
    if (is.null(x)) x <- read_csv_if_exists("reports/STAGE8_TRAIN_VIF_CURRENT.csv")
    x
  })
  separation_current <- reactive(read_csv_if_exists("reports/STAGE8_SEPARATION_DIAGNOSTIC.csv"))
  loocv_all <- reactive(read_csv_if_exists("reports/STAGE8_LOOCV_RESULTS.csv"))
  sensitivity_results <- reactive(read_csv_if_exists("reports/STAGE8_SENSITIVITY_RESULTS.csv"))
  reproducibility_result <- reactive(read_csv_if_exists("reports/STAGE8_REPRODUCIBILITY_CHECK.csv"))

  # ---------------------------------------------------------------------------
  # GOES DATA TAB
  # ---------------------------------------------------------------------------
  observeEvent(xrs_b(), {
    df <- xrs_b()
    updateDateRangeInput(
      session, "goes_dates",
      start = as.Date(min(df$time_tag, na.rm = TRUE)),
      end = as.Date(max(df$time_tag, na.rm = TRUE)),
      min = as.Date(min(df$time_tag, na.rm = TRUE)),
      max = as.Date(max(df$time_tag, na.rm = TRUE))
    )
  }, ignoreInit = FALSE)

  output$goes_metric_cards <- renderUI({
    df <- xrs_b()
    ts <- sort(unique(df$time_tag[!is.na(df$time_tag)]))
    cadence <- if (length(ts) > 1) median(diff(as.numeric(ts)), na.rm = TRUE) else NA_real_
    dup_n <- sum(duplicated(df$time_tag))
    miss_n <- if ("is_missing_raw" %in% names(df)) sum(df$is_missing_raw %in% TRUE, na.rm = TRUE) else NA_integer_
    imp_n <- if ("was_imputed" %in% names(df)) sum(df$was_imputed %in% TRUE, na.rm = TRUE) else NA_integer_
    sat <- paste(sort(unique(na.omit(df$satellite))), collapse = ", ")
    energy <- paste(sort(unique(na.omit(df$energy))), collapse = ", ")
    duration_days <- as.numeric(difftime(max(df$time_tag, na.rm=TRUE), min(df$time_tag, na.rm=TRUE), units="days"))

    fluidRow(
      column(2, metric_card(format(nrow(df), big.mark=","), "XRS-B observations")),
      column(2, metric_card(fmt_num(duration_days, 2), "Coverage (days)")),
      column(2, metric_card(paste0(fmt_num(cadence, 0), " s"), "Median cadence")),
      column(2, metric_card(as.character(dup_n), "Duplicate timestamps")),
      column(2, metric_card(ifelse(is.na(miss_n), "—", miss_n), "Raw missing flags", ifelse(is.na(imp_n), NULL, paste("Imputed:", imp_n)))),
      column(2, metric_card(ifelse(nchar(sat)>0, paste("GOES", sat), "—"), energy))
    )
  })

  goes_window <- reactive({
    df <- xrs_b()
    req(input$goes_dates)
    lo <- as.POSIXct(input$goes_dates[1], tz="UTC")
    hi <- as.POSIXct(input$goes_dates[2] + 1, tz="UTC")
    sub <- df[df$time_tag >= lo & df$time_tag < hi, , drop=FALSE]
    validate(need(nrow(sub) > 0, "No observations in the selected visualization window."))
    sub
  })

  output$goes_plot <- renderPlot({
    df <- goes_window()
    plot(df$time_tag, df$flux_clean, type="l", log="y", lwd=1,
         xlab="UTC time", ylab="0.1–0.8 nm flux (W/m², log scale)",
         main="GOES XRS-B cleaned soft X-ray flux")
    grid()
    if (isTRUE(input$show_class_levels)) {
      lev <- c(B=1e-7, C=1e-6, M=1e-5, X=1e-4)
      abline(h=lev, lty=2)
      legend("topright", legend=names(lev), lty=2, bty="n", title="Reference level")
    }
  })

  # ---------------------------------------------------------------------------
  # STATISTICAL BASELINE TAB
  # ---------------------------------------------------------------------------
  rolling_view <- reactive({
    df <- xrs_b()
    validate(need(exists("compute_rolling_statistics_r"), "R/03_rolling_statistics.R is unavailable."))
    compute_rolling_statistics_r(
      df,
      window_mins = 30,
      min_periods = 5,
      uncontaminated = TRUE,
      slope_window_mins = 5
    )
  })

  output$rolling_panels <- renderPlot({
    df <- rolling_view()
    # Use a 24-hour region centered on the strongest finite peak for an informative static demo.
    valid_idx <- which(is.finite(df$flux_clean) & df$flux_clean > 0)
    validate(need(length(valid_idx)>0, "No finite flux observations available."))
    peak_idx <- valid_idx[which.max(df$flux_clean[valid_idx])]
    half <- 12*60
    ix <- max(1, peak_idx-half):min(nrow(df), peak_idx+half)
    s <- df[ix, , drop=FALSE]

    old <- par(no.readonly=TRUE); on.exit(par(old))
    par(mfrow=c(4,1), mar=c(3.2,4.5,2.3,1), oma=c(1,0,1,0))

    plot(s$time_tag, s$flux_clean, type="l", log="y", xlab="", ylab="Flux (W/m²)", main="A. Flux + trailing mean / median")
    if ("rolling_mean_30m" %in% names(s)) lines(s$time_tag, 10^s$rolling_mean_30m, lwd=1.4, lty=2)
    if ("rolling_median_30m" %in% names(s)) lines(s$time_tag, 10^s$rolling_median_30m, lwd=1.4, lty=3)
    legend("topright", c("Flux","Rolling mean","Rolling median"), lty=c(1,2,3), bty="n", cex=.8); grid()

    plot(s$time_tag, s$rolling_std_30m, type="l", xlab="", ylab="log10 spread", main="B. Rolling SD + scaled MAD")
    lines(s$time_tag, s$rolling_mad_scaled_30m, lty=2)
    legend("topright", c("Rolling SD","Scaled MAD"), lty=c(1,2), bty="n", cex=.8); grid()

    z_mean <- (s$log10_flux_clean - s$rolling_mean_30m) / s$rolling_std_30m
    z_mad <- (s$log10_flux_clean - s$rolling_median_30m) / s$rolling_mad_scaled_30m
    plot(s$time_tag, z_mean, type="l", xlab="", ylab="Z score", main="C. Standard Z vs robust Z")
    lines(s$time_tag, z_mad, lty=2); abline(h=3, lty=3)
    legend("topright", c("Standard Z","Robust Z","Reference threshold 3"), lty=c(1,2,3), bty="n", cex=.8); grid()

    plot(s$time_tag, s$roc_log, type="l", xlab="UTC time", ylab="dex/min", main="D. ROC + local slope")
    lines(s$time_tag, s$local_slope_5m, lty=2)
    abline(h=0.05, lty=3)
    legend("topright", c("ROC (log flux)","5-min local slope","Reference ROC threshold 0.05"), lty=c(1,2,3), bty="n", cex=.8); grid()
  })

  output$detector_config_table <- renderTable({
    data.frame(
      Parameter = c("Rolling window", "Baseline rule", "Standard Z threshold", "Robust Z threshold", "ROC threshold", "Minimum persistence", "Local slope window"),
      Value = c("30 min", "prior observations only", "3.0", "3.0", "0.05 dex/min", "3 points", "5 min"),
      stringsAsFactors=FALSE
    )
  }, rownames=FALSE)

  # ---------------------------------------------------------------------------
  # EVENT DETECTION / ALIGNMENT TAB
  # ---------------------------------------------------------------------------
  observeEvent(events(), {
    ev <- events()
    labels <- paste(ev$event_id, "·", ev$noaa_class, "·", format(ev$peak_time, "%m-%d %H:%M"))
    updateSelectInput(session, "event_id", choices=setNames(ev$event_id, labels), selected=ev$event_id[1])
  }, ignoreInit=FALSE)

  selected_event <- reactive({
    ev <- events()
    req(input$event_id)
    row <- ev[ev$event_id == input$event_id, , drop=FALSE]
    validate(need(nrow(row)==1, "Selected event is unavailable."))
    row
  })

  output$event_plot <- renderPlot({
    ev <- selected_event()
    df <- xrs_b()
    lo <- ev$start_time - 60*60
    hi <- ev$end_time + 60*60
    s <- df[df$time_tag >= lo & df$time_tag <= hi, , drop=FALSE]
    validate(need(nrow(s)>0, "No GOES samples around selected event."))
    plot(s$time_tag, s$flux_clean, type="l", log="y", lwd=1.2,
         xlab="UTC time", ylab="Flux (W/m², log scale)",
         main=paste("Aligned event", ev$event_id, "· NOAA", ev$noaa_class))
    abline(v=as.numeric(ev$start_time), lty=2)
    abline(v=as.numeric(ev$peak_time), lty=1, lwd=2)
    abline(v=as.numeric(ev$end_time), lty=3)
    points(ev$peak_time, ev$peak_flux, pch=19)
    legend("topright", c("XRS-B flux","START","PEAK","END"), lty=c(1,2,1,3), bty="n")
    grid()
  })

  output$event_details <- renderUI({
    ev <- selected_event()
    tagList(
      h4("Detected event"),
      tags$table(class="table table-condensed",
        tags$tr(tags$td("Event ID"), tags$td(ev$event_id)),
        tags$tr(tags$td("Start"), tags$td(fmt_time(ev$start_time))),
        tags$tr(tags$td("Peak"), tags$td(fmt_time(ev$peak_time))),
        tags$tr(tags$td("End"), tags$td(fmt_time(ev$end_time))),
        tags$tr(tags$td("Rise duration"), tags$td(paste(fmt_num(ev$rise_duration_min,1), "min"))),
        tags$tr(tags$td("Total duration"), tags$td(paste(fmt_num(ev$duration_min,1), "min"))),
        tags$tr(tags$td("Peak flux (descriptive)"), tags$td(fmt_sci(ev$peak_flux))),
        tags$tr(tags$td("Max standard Z"), tags$td(fmt_num(ev$max_z_mean,2))),
        tags$tr(tags$td("Max robust Z"), tags$td(fmt_num(ev$max_z_mad,2)))
      )
    )
  })

  output$alignment_details <- renderUI({
    ev <- selected_event()
    tagList(
      h4("NOAA alignment"),
      tags$table(class="table table-condensed",
        tags$tr(tags$td("NOAA event ID"), tags$td(ev$noaa_event_id)),
        tags$tr(tags$td("NOAA class"), tags$td(ev$noaa_class)),
        tags$tr(tags$td("Class letter"), tags$td(ev$noaa_class_letter)),
        tags$tr(tags$td("Detector peak"), tags$td(fmt_time(ev$peak_time))),
        tags$tr(tags$td("|peak timing error|"), tags$td(paste(fmt_num(ev$abs_peak_error_min,1), "min"))),
        tags$tr(tags$td("Matching status"), tags$td("Matched and retained after physical-event deduplication"))
      ),
      p(class="small-muted", "The exact NOAA peak timestamp is not stored in labeled_events_deduplicated.csv; the saved absolute peak timing error is shown instead rather than reconstructing it.")
    )
  })

  output$detector_summary_ui <- renderUI({
    # Historical Python event_segmentation_summary.csv is deliberately NOT used,
    # because it predates the corrected R methodology.
    ev <- events()
    fluidRow(
      column(3, metric_card(nrow(ev), "Matched deduplicated rows", "Before U exclusion")),
      column(3, metric_card(sum(!is.na(ev$severity_class)), "ML-eligible matched events")),
      column(6, artifact_notice("authoritative Stage 5 detector summary artifact", "Stage 5 precision / recall / F1 + unmatched counts"))
    )
  })

  # ---------------------------------------------------------------------------
  # EVENT MORPHOLOGY TAB
  # ---------------------------------------------------------------------------
  eligible_events <- reactive({
    e <- events()
    e[!is.na(e$severity_class), , drop=FALSE]
  })

  output$morph_boxplot <- renderPlot({
    e <- eligible_events(); f <- input$morph_feature
    validate(need(f %in% names(e), "Selected feature unavailable."))
    y <- e[[f]]
    boxplot(y ~ e$severity_class, names=c("B","C+"),
            xlab="Severity class", ylab=f,
            main=paste(f, "· B vs C+"))
    stripchart(y ~ e$severity_class, method="jitter", vertical=TRUE, add=TRUE, pch=19, cex=.7)
    grid(nx=NA, ny=NULL)
  })

  output$rise_corr_plot <- renderPlot({
    e <- eligible_events()
    vars <- c("rise_slope","max_roc","mean_pos_roc")
    cm <- cor(e[,vars], use="complete.obs")
    image(1:3,1:3,t(cm[3:1,]),axes=FALSE,zlim=c(-1,1),xlab="",ylab="",main="Rise-rate predictor correlation")
    axis(1,1:3,c("Rise slope","Max ROC","Mean +ROC"))
    axis(2,1:3,rev(c("Rise slope","Max ROC","Mean +ROC")),las=2)
    for(i in 1:3) for(j in 1:3) text(i,4-j,sprintf("%.3f",cm[j,i]))
    box()
  })

  output$morph_support_cards <- renderUI({
    e <- eligible_events(); tb <- table(e$severity_class)
    fluidRow(
      column(6, metric_card(ifelse("B" %in% names(tb), tb[["B"]],0), "B events")),
      column(6, metric_card(ifelse("C_plus" %in% names(tb), tb[["C_plus"]],0), "C+ events"))
    )
  })

  output$event_table <- renderTable({
    e <- events()
    cols <- intersect(c(
      "event_id","noaa_event_id","noaa_class","severity_class",
      "start_time","peak_time","end_time",
      "rise_slope","max_roc","mean_pos_roc","rise_duration_min","bg_flux",
      "peak_flux","duration_min","abs_peak_error_min"
    ), names(e))
    out <- e[,cols,drop=FALSE]
    head(out, 32)
  }, striped=TRUE, bordered=TRUE, spacing="xs")

  # ---------------------------------------------------------------------------
  # SEVERITY NOWCASTING TAB
  # ---------------------------------------------------------------------------
  output$nowcast_selector_ui <- renderUI({
    p <- final_predictions()
    if (is.null(p)) return(artifact_notice("reports/STAGE8_FINAL_TEST_PREDICTIONS.csv"))
    req("event_id" %in% names(p))
    selectInput("nowcast_event_id", "Select frozen final-test event", choices=p$event_id, selected=p$event_id[1])
  })

  output$nowcast_details <- renderUI({
    p <- final_predictions()
    if (is.null(p)) return(artifact_notice("reports/STAGE8_FINAL_TEST_PREDICTIONS.csv"))
    req(input$nowcast_event_id)
    row <- p[p$event_id == input$nowcast_event_id, , drop=FALSE]
    ev <- eligible_events()
    erow <- ev[ev$event_id == input$nowcast_event_id, , drop=FALSE]
    validate(need(nrow(row)==1, "Prediction row unavailable."))
    validate(need(nrow(erow)==1, "Event feature row unavailable."))

    pred_prob <- if ("probability_C_plus" %in% names(row)) fmt_num(row$probability_C_plus,4) else "not saved"
    fluidRow(
      column(5,
        h4("Five frozen predictor values"),
        tags$table(class="table table-condensed",
          lapply(PRIMARY_PREDICTORS, function(f) {
            val <- erow[[f]]
            tags$tr(tags$td(f), tags$td(if (f=="bg_flux") fmt_sci(val) else fmt_num(val,6)))
          })
        )
      ),
      column(7,
        h4("Frozen prediction"),
        tags$table(class="table table-condensed",
          tags$tr(tags$td("Event"), tags$td(row$event_id)),
          tags$tr(tags$td("Actual class"), tags$td(row$actual)),
          tags$tr(tags$td("Predicted class"), tags$td(row$predicted)),
          tags$tr(tags$td("P(C+)"), tags$td(pred_prob)),
          tags$tr(tags$td("Prediction point"), tags$td("t_peak"))
        ),
        div(class="scientific-note", "The GUI displays saved Stage 8 predictions. It does not refit or call the saved model object.")
      )
    )
  })

  # ---------------------------------------------------------------------------
  # ML EVALUATION TAB
  # ---------------------------------------------------------------------------
  output$dev_results_ui <- renderUI({
    d <- dev_results()
    if (is.null(d)) return(artifact_notice("reports/STAGE8_MODEL_COMPARISON.csv"))
    tableOutput("dev_results_table")
  })

  output$dev_results_table <- renderTable({
    d <- dev_results(); req(d)
    keep <- intersect(c("Model","N","Accuracy","Macro_F1","Balanced_Accuracy","TP","FP","TN","FN"), names(d))
    d[,keep,drop=FALSE]
  }, striped=TRUE, bordered=TRUE)

  output$dev_metric_plot <- renderPlot({
    d <- dev_results()
    validate(need(!is.null(d), "Development comparison artifact is not available."))
    validate(need(all(c("Model","Macro_F1","Balanced_Accuracy") %in% names(d)), "Development artifact schema is incomplete."))
    mat <- rbind(d$Macro_F1, d$Balanced_Accuracy)
    barplot(mat, beside=TRUE, names.arg=d$Model, ylim=c(0,1.08), ylab="Metric", main="Development-set comparison")
    legend("bottomright", c("Macro F1","Balanced Accuracy"), fill=c("gray35","gray70"), bty="n")
    grid(nx=NA, ny=NULL)
  })

  output$final_split_cards <- renderUI({
    tr <- stage8_train(); dv <- stage8_dev(); te <- stage8_test()
    if (is.null(tr) || is.null(dv) || is.null(te)) {
      return(artifact_notice("data/processed/stage8_train.csv + stage8_development.csv + stage8_final_test.csv"))
    }
    fluidRow(
      column(3, metric_card(nrow(tr)+nrow(dv)+nrow(te), "ML events")),
      column(3, metric_card(nrow(tr), "Training")),
      column(3, metric_card(nrow(dv), "Development")),
      column(3, metric_card(nrow(te), "Final test"))
    )
  })

  output$final_cm_table <- renderTable({
    x <- final_cm()
    validate(need(!is.null(x), "reports/STAGE8_CONFUSION_MATRICES.csv is unavailable."))
    x
  }, rownames=TRUE, bordered=TRUE)

  output$final_prediction_table <- renderTable({
    p <- final_predictions()
    validate(need(!is.null(p), "reports/STAGE8_FINAL_TEST_PREDICTIONS.csv is unavailable."))
    keep <- intersect(c("event_id","noaa_event_id","peak_time","actual","predicted","probability_C_plus"), names(p))
    p[,keep,drop=FALSE]
  }, striped=TRUE, bordered=TRUE)

  output$robustness_ui <- renderUI({
    l <- loocv_all()
    primary <- loocv_primary()
    sens <- sensitivity_results()
    repro <- reproducibility_result()

    blocks <- list()
    if (!is.null(l)) {
      blocks <- c(blocks, list(div(class="section-card", h4("LOOCV — all three models"), tableOutput("loocv_all_table"))))
    } else if (!is.null(primary)) {
      blocks <- c(blocks, list(div(class="section-card", h4("LOOCV — Logistic Regression"), tableOutput("loocv_primary_table"))))
    } else {
      blocks <- c(blocks, list(artifact_notice("reports/STAGE8_LOOCV_RESULTS.csv or reports/STAGE8_ROBUSTNESS.csv")))
    }

    if (!is.null(sens)) {
      blocks <- c(blocks, list(div(class="section-card", h4("Sensitivity analysis"), tableOutput("sensitivity_table"))))
    }
    if (!is.null(repro)) {
      blocks <- c(blocks, list(div(class="section-card", h4("Reproducibility"), tableOutput("repro_table"))))
    }
    do.call(tagList, blocks)
  })

  output$loocv_all_table <- renderTable({
    x <- loocv_all(); req(x)
    keep <- intersect(c("Model","Accuracy","Macro_F1","Balanced_Accuracy","B_Precision","B_Recall","C_plus_Precision","C_plus_Recall"), names(x))
    x[,keep,drop=FALSE]
  }, striped=TRUE, bordered=TRUE)

  output$loocv_primary_table <- renderTable({
    x <- loocv_primary(); req(x)
    x
  }, striped=TRUE, bordered=TRUE)

  output$sensitivity_table <- renderTable({
    x <- sensitivity_results(); req(x)
    keep <- intersect(c("Model","Partition","Accuracy","Macro_F1","Balanced_Accuracy","Separation","Warning_Count"), names(x))
    x[,keep,drop=FALSE]
  }, striped=TRUE, bordered=TRUE)

  output$repro_table <- renderTable({
    x <- reproducibility_result(); req(x)
    x
  }, striped=TRUE, bordered=TRUE)

  output$vif_table <- renderTable({
    v <- vif_current()
    validate(need(!is.null(v), "Training VIF artifact is unavailable."))
    v
  }, striped=TRUE, bordered=TRUE)

  output$separation_ui <- renderUI({
    s <- separation_current()
    if (is.null(s)) {
      return(tagList(
        artifact_notice("reports/STAGE8_SEPARATION_DIAGNOSTIC.csv"),
        div(class="warning-note",
          tags$strong("Frozen scientific conclusion:"),
          " ordinary Logistic Regression exhibits complete separation / convergence warnings in the completed Stage 8 robustness analysis."
        )
      ))
    }
    tagList(
      tableOutput("separation_table"),
      div(class="warning-note", "These are diagnostic limitations. They do not trigger model replacement in the frozen experiment.")
    )
  })

  output$separation_table <- renderTable({
    x <- separation_current(); req(x)
    x
  }, bordered=TRUE)
}

# Launch when app.R is run interactively or via shiny::runApp().
shinyApp(ui = ui, server = server)
