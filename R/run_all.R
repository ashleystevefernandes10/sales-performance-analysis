# run_all.R -- reproduce the entire project:  Rscript R/run_all.R   (from the project root)
for (f in c("R/01_build_db.R", "R/02_eda_kpis.R", "R/03_stats.R", "R/04_forecast.R", "R/05_recommendations.R")) {
  cat("\n\n=====", f, "=====\n"); source(f, echo = FALSE)
}
cat("\nDone. See output/figures and output/tables\n")
