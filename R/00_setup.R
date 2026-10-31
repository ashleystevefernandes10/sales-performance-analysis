# 00_setup.R -- shared packages, paths and helpers. Run all scripts from the project root.
suppressPackageStartupMessages({
  library(DBI); library(RSQLite); library(dplyr); library(tidyr)
  library(ggplot2); library(scales); library(lubridate); library(readr)
})

DB_PATH  <- "data/sales.sqlite"
FIG_DIR  <- "output/figures"
TAB_DIR  <- "output/tables"
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(TAB_DIR, showWarnings = FALSE, recursive = TRUE)

theme_set(theme_minimal(base_size = 12) +
  theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank(),
        legend.position = "bottom"))
pal <- c("Furniture" = "#C0504D", "Office Supplies" = "#4F81BD", "Technology" = "#2E8B57")

connect <- function() dbConnect(SQLite(), DB_PATH)

# Execute every statement in a .sql file (statements end with ';' at line end)
run_sql_file <- function(con, path) {
  txt <- paste(readLines(path), collapse = "\n")
  txt <- gsub("--[^\n]*", "", txt)                       # strip comments
  stmts <- trimws(strsplit(txt, ";[ \t]*(\n|$)")[[1]])
  for (s in stmts[nzchar(stmts)]) dbExecute(con, s)
  invisible(length(stmts))
}

save_plot <- function(p, name, w = 9, h = 5.2) {
  ggsave(file.path(FIG_DIR, paste0(name, ".png")), p, width = w, height = h, dpi = 150, bg = "white")
}
save_tab <- function(df, name) write_csv(df, file.path(TAB_DIR, paste0(name, ".csv")))
