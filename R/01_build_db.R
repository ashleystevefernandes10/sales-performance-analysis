# 01_build_db.R -- load raw CSV into SQLite, then run SQL cleaning + KPI scripts
source("R/00_setup.R")
raw <- read_csv("data/sales_raw.csv", col_types = cols(.default = col_character()),
                show_col_types = FALSE) |>
  mutate(across(c(sales, quantity, discount, profit), as.numeric))

con <- connect()
dbWriteTable(con, "raw_sales", raw, overwrite = TRUE)

run_sql_file(con, "sql/01_clean.sql")
run_sql_file(con, "sql/02_kpis.sql")

audit <- dbGetQuery(con, "SELECT * FROM cleaning_audit")
print(audit); save_tab(audit, "cleaning_audit")
dbDisconnect(con)
