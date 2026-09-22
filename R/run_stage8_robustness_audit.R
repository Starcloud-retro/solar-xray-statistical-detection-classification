# R/run_stage8_robustness_audit.R
# Supplementary audit only. Does not change the primary Stage 8 experiment.

# GUI STARTUP GUARD: execute this standalone script only when run directly.
# Shiny automatically sources every .R file under R/.  Direct Rscript execution
# has sys.nframe() == 0; sourcing (including Shiny support loading) does not.
if (sys.nframe() == 0L) {
  options(stringsAsFactors = FALSE)
  set.seed(42)

  find_project_root <- function() {
    args <- commandArgs(trailingOnly = FALSE)
    f <- grep("^--file=", args, value = TRUE)
    candidates <- c(
      if (length(f)) dirname(dirname(normalizePath(sub("^--file=", "", f[1]), winslash="/", mustWork=FALSE))) else character(0),
      normalizePath(getwd(), winslash="/", mustWork=FALSE)
    )
    for (p in unique(candidates)) {
      if (file.exists(file.path(p,"R","07_ml_models.R")) &&
          file.exists(file.path(p,"data","processed","labeled_events_deduplicated.csv"))) return(p)
    }
    stop("Project root not found.")
  }
  setwd(find_project_root())
  source("R/01_stats_primitives.R")
  source("R/06_feature_engineering.R")
  source("R/07_ml_models.R")
  source("R/08_evaluation.R")
  dir.create("reports", showWarnings=FALSE, recursive=TRUE)
  dir.create("reports/figures", showWarnings=FALSE, recursive=TRUE)

  run_stats_primitive_tests()
  run_temporal_roc_scope_tests_r(verbose=TRUE)

  raw <- read.csv("data/processed/labeled_events_deduplicated.csv", stringsAsFactors=FALSE, check.names=FALSE)
  ml <- prepare_ml_dataset_r(raw)
  validation <- validate_ml_dataset_r(ml, TRUE)
  sp <- split_chronological_r(ml,18,6,7)
  tr <- sp$train; dv <- sp$development; te <- sp$test

  # Current-data diagnostics
  cmat <- cor(tr[,STAGE8_PRIMARY_PREDICTORS], use="complete.obs")
  vif <- calculate_vif_r(tr, STAGE8_PRIMARY_PREDICTORS)
  write.csv(cmat,"reports/STAGE8_AUDIT_TRAIN_CORRELATION.csv")
  write.csv(vif,"reports/STAGE8_AUDIT_TRAIN_VIF.csv",row.names=FALSE)

  logit <- fit_logistic_model_r(tr, use_class_weights=FALSE)
  sep <- separation_diagnostic_r(logit,tr)
  coef_tab <- summarize_logistic_coefficients_r(logit)
  write.csv(coef_tab,"reports/STAGE8_AUDIT_LOGISTIC_COEFFICIENTS.csv",row.names=FALSE)
  write.csv(predict_stage8_model_r(logit,tr),"reports/STAGE8_AUDIT_LOGISTIC_TRAIN_PREDICTIONS.csv",row.names=FALSE)
  write.csv(predict_stage8_model_r(logit,dv),"reports/STAGE8_AUDIT_LOGISTIC_DEV_PREDICTIONS.csv",row.names=FALSE)
  write.csv(predict_stage8_model_r(logit,te),"reports/STAGE8_AUDIT_LOGISTIC_TEST_PREDICTIONS.csv",row.names=FALSE)

  # Feature distributions and Cliff's delta
  cliff <- function(b,cp) {
    b<-b[is.finite(b)]; cp<-cp[is.finite(cp)]
    d<-outer(cp,b,"-")
    (sum(d>0)-sum(d<0))/(length(b)*length(cp))
  }
  summ <- function(x) c(N=sum(is.finite(x)),Min=min(x),Q1=quantile(x,.25),Median=median(x),
                        Mean=mean(x),Q3=quantile(x,.75),Max=max(x),SD=sd(x),IQR=IQR(x))
  fs<-list(); es<-list()
  for(v in STAGE8_PRIMARY_PREDICTORS){
    b<-ml[ml$severity_class=="B",v]; cpv<-ml[ml$severity_class=="C_plus",v]
    fs[[paste0(v,"_B")]]<-data.frame(Feature=v,Class="B",t(summ(b)),check.names=FALSE)
    fs[[paste0(v,"_C")]]<-data.frame(Feature=v,Class="C_plus",t(summ(cpv)),check.names=FALSE)
    es[[v]]<-data.frame(Feature=v,Cliffs_Delta_Cplus_vs_B=cliff(b,cpv))
  }
  write.csv(do.call(rbind,fs),"reports/STAGE8_AUDIT_FEATURE_DISTRIBUTIONS.csv",row.names=FALSE)
  write.csv(do.call(rbind,es),"reports/STAGE8_AUDIT_FEATURE_EFFECTS.csv",row.names=FALSE)

  labs<-c(rise_slope="Rise slope",max_roc="Maximum rate of change",
          mean_pos_roc="Mean positive rate of change",rise_duration_min="Rise duration (min)",
          bg_flux="Background flux (W/m^2)")
  set.seed(42)
  for(v in STAGE8_PRIMARY_PREDICTORS){
    png(file.path("reports/figures",paste0("stage8_audit_",v,".png")),1400,1000,res=180)
    boxplot(ml[[v]]~ml$severity_class,names=c("B","C+"),xlab="Severity class",ylab=labs[[v]],
            main=paste0(labs[[v]],": B vs C+"))
    stripchart(ml[[v]]~ml$severity_class,method="jitter",vertical=TRUE,add=TRUE,pch=16,cex=.75)
    grid(nx=NA,ny=NULL); dev.off()
  }
  png("reports/figures/stage8_audit_rise_rate_pairs.png",1500,1500,res=180)
  pairs(ml[,c("rise_slope","max_roc","mean_pos_roc")],pch=19,main="Rise-rate predictor relationships")
  dev.off()

  # Generic LOOCV using unchanged current configurations.
  loocv_model <- function(type){
    out<-vector("list",nrow(ml)); warning_folds<-0L
    for(i in seq_len(nrow(ml))){
      fitdf<-ml[-i,,drop=FALSE]; hold<-ml[i,,drop=FALSE]
      if(type=="Logistic Regression"){
        fit<-fit_logistic_model_r(fitdf,use_class_weights=FALSE)
        if(length(fit$warnings)>0) warning_folds<-warning_folds+1L
      } else if(type=="Decision Tree"){
        fit<-fit_decision_tree_r(fitdf,maxdepth=3,minsplit=4,cp=.01)
      } else {
        fit<-fit_random_forest_r(fitdf,ntree=200,mtry=2,seed=42)
      }
      p<-predict_stage8_model_r(fit,hold); p$Fold<-i; out[[i]]<-p
    }
    pred<-do.call(rbind,out)
    met<-calculate_binary_metrics_r(pred$actual,pred$predicted,model_name=type,partition="LOOCV")
    list(pred=pred,metrics=met,warning_folds=warning_folds)
  }
  lv<-loocv_model("Logistic Regression")
  tv<-loocv_model("Decision Tree")
  rv<-loocv_model("Random Forest")
  write.csv(rbind(lv$metrics,tv$metrics,rv$metrics),"reports/STAGE8_LOOCV_RESULTS.csv",row.names=FALSE)
  write.csv(data.frame(Model=c("Logistic Regression","Decision Tree","Random Forest"),
                       Warning_Producing_Folds=c(lv$warning_folds,tv$warning_folds,rv$warning_folds)),
            "reports/STAGE8_LOOCV_WARNING_COUNTS.csv",row.names=FALSE)

  # Sensitivity specifications; no best-model selection.
  specs<-list(
   A_Primary=c("rise_slope","max_roc","mean_pos_roc","rise_duration_min","bg_flux"),
   B_Remove_rise_slope=c("max_roc","mean_pos_roc","rise_duration_min","bg_flux"),
   C_Remove_max_roc=c("rise_slope","mean_pos_roc","rise_duration_min","bg_flux"),
   D_Remove_mean_pos_roc=c("rise_slope","max_roc","rise_duration_min","bg_flux")
  )
  res<-list()
  for(nm in names(specs)){
    fit<-fit_logistic_model_r(tr,predictors=specs[[nm]],use_class_weights=FALSE)
    sdg<-separation_diagnostic_r(fit,tr)
    pd<-predict_stage8_model_r(fit,dv); pt<-predict_stage8_model_r(fit,te)
    md<-calculate_binary_metrics_r(pd$actual,pd$predicted,nm,"Development")
    mt<-calculate_binary_metrics_r(pt$actual,pt$predicted,nm,"Final Test Sensitivity")
    md$Separation<-sdg$classification; mt$Separation<-sdg$classification
    md$Warning_Count<-length(fit$warnings); mt$Warning_Count<-length(fit$warnings)
    res[[paste0(nm,"_dev")]]<-md; res[[paste0(nm,"_test")]]<-mt
  }
  write.csv(do.call(rbind,res),"reports/STAGE8_SENSITIVITY_RESULTS.csv",row.names=FALSE)

  # Reproducibility: fixed configs and seed, run twice.
  fit_once<-function(){
    l<-fit_logistic_model_r(tr,use_class_weights=FALSE)
    t<-fit_decision_tree_r(tr,maxdepth=3,minsplit=4,cp=.01)
    r<-fit_random_forest_r(tr,ntree=200,mtry=2,seed=42)
    list(ld=predict_stage8_model_r(l,dv)$predicted,
         lt=predict_stage8_model_r(l,te)$predicted,
         td=predict_stage8_model_r(t,dv)$predicted,
         rd=predict_stage8_model_r(r,dv)$predicted)
  }
  a<-fit_once(); b<-fit_once()
  write.csv(data.frame(Check=names(a),Identical=mapply(identical,a,b)),
            "reports/STAGE8_REPRODUCIBILITY_CHECK.csv",row.names=FALSE)

  # Do not force a degenerate 7/7 bootstrap.
  write.csv(data.frame(Performed=FALSE,
   Reason="Not forced: resampling a fixed 7/7 all-correct prediction table gives degenerate accuracy=1 and understates uncertainty."),
   "reports/STAGE8_BOOTSTRAP_DECISION.csv",row.names=FALSE)

  cat("\nSTAGE 8 ROBUSTNESS AUDIT COMPLETE\n")
  cat("Primary experiment changed: NO\n")
  cat("FINAL_RESULTS.md modified: NO\n")
}
