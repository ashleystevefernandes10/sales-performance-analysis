# 04_forecast.R -- 12-month sales forecast: model selection on a hold-out, then final forecast
source("R/00_setup.R"); suppressPackageStartupMessages(library(forecast))
con <- connect()
m <- dbGetQuery(con, "SELECT year_month, sales, profit FROM v_monthly ORDER BY year_month")
y_all <- ts(m$sales, start = c(2021, 1), frequency = 12)

# --- Backtest: train 2021-2023, test 2024 --------------------------------------
train <- window(y_all, end = c(2023, 12)); test <- window(y_all, start = c(2024, 1))
h <- length(test)
models <- list(
  "Seasonal naive"   = snaive(train, h = h),
  "ETS"              = forecast(ets(train), h = h),
  "ARIMA"            = forecast(auto.arima(train, lambda = "auto"), h = h),
  "STL + ETS" = forecast(stlf(train, method = "ets"), h = h)
)
acc <- bind_rows(lapply(names(models), function(nm) {
  a <- accuracy(models[[nm]], test)["Test set", ]
  tibble(model = nm, MAPE = a["MAPE"], RMSE = a["RMSE"], MAE = a["MAE"])
})) |> arrange(MAPE)
print(acc); save_tab(acc, "forecast_backtest_accuracy")
best <- acc$model[1]; cat("\nBest model on 2024 hold-out:", best, "\n")

# --- Refit best model on ALL data, forecast 2025 -------------------------------
final <- switch(best,
  "Seasonal naive" = snaive(y_all, h = 12),
  "ETS" = forecast(ets(y_all), h = 12),
  "ARIMA" = forecast(auto.arima(y_all, lambda = "auto"), h = 12),
  "STL + ETS" = forecast(stlf(y_all, method = "ets"), h = 12))

fc <- tibble(date = seq(ymd("2025-01-01"), by = "month", length.out = 12),
             forecast = as.numeric(final$mean),
             lo80 = as.numeric(final$lower[, 1]), hi80 = as.numeric(final$upper[, 1]),
             lo95 = as.numeric(final$lower[, 2]), hi95 = as.numeric(final$upper[, 2]))
save_tab(fc, "forecast_2025_monthly")

hist <- tibble(date = ymd(paste0(m$year_month, "-01")), sales = m$sales)
p <- ggplot() +
  geom_ribbon(data = fc, aes(date, ymin = lo95, ymax = hi95), fill = "#9DB9D9", alpha = .4) +
  geom_ribbon(data = fc, aes(date, ymin = lo80, ymax = hi80), fill = "#4F81BD", alpha = .4) +
  geom_line(data = hist, aes(date, sales), colour = "#1F3A5F", linewidth = 1) +
  geom_line(data = fc, aes(date, forecast), colour = "#C0504D", linewidth = 1.1) +
  scale_y_continuous(labels = label_dollar(scale = 1e-3, suffix = "k")) +
  labs(title = paste0("2025 sales forecast (", best, ") with 80% / 95% intervals"), x = NULL, y = "Monthly sales")
save_plot(p, "11_sales_forecast_2025")

# Annual outlook + margin-adjusted profit outlook
ann <- dbGetQuery(con, "SELECT order_year, sales, profit FROM v_yearly")
last_margin <- tail(ann$profit / ann$sales, 1)
outlook <- tibble(year = 2025, forecast_sales = sum(fc$forecast), lo95 = sum(fc$lo95), hi95 = sum(fc$hi95),
                  assumed_margin = last_margin, implied_profit = sum(fc$forecast) * last_margin,
                  growth_vs_2024 = sum(fc$forecast) / tail(ann$sales, 1) - 1)
print(outlook); save_tab(outlook, "forecast_2025_annual_outlook")
dbDisconnect(con)
