# 02_eda_kpis.R -- KPI tables (from SQL views) + exploratory visualisations
source("R/00_setup.R")
con <- connect()
q <- function(v) dbGetQuery(con, paste("SELECT * FROM", v))

monthly <- q("v_monthly") |> mutate(date = ymd(paste0(year_month, "-01")))
yearly  <- q("v_yearly"); category <- q("v_category"); region <- q("v_region")
regcat  <- q("v_region_category"); disc <- q("v_discount")
segment <- q("v_segment"); season <- q("v_seasonality"); regg <- q("v_region_growth")
cust    <- q("v_customer")

for (n in c("yearly","category","region","regcat","disc","segment","season","regg"))
  save_tab(get(n), paste0("kpi_", n))
cat("\n== Yearly KPIs ==\n"); print(yearly)

# 1. Sales & profit trend with 12m rolling average
p1 <- monthly |> arrange(date) |>
  mutate(roll12 = zoo::rollmean(sales, 12, fill = NA, align = "right")) |>
  ggplot(aes(date)) +
  geom_col(aes(y = sales), fill = "#9DB9D9") +
  geom_line(aes(y = roll12), colour = "#1F3A5F", linewidth = 1.1, na.rm = TRUE) +
  scale_y_continuous(labels = label_dollar(scale = 1e-3, suffix = "k")) +
  labs(title = "Monthly sales with 12-month rolling average", x = NULL, y = "Sales")
save_plot(p1, "01_monthly_sales_trend")

# 2. Yearly sales growth & margin
p2 <- yearly |> ggplot(aes(factor(order_year))) +
  geom_col(aes(y = sales), fill = "#4F81BD") +
  geom_text(aes(y = sales, label = ifelse(is.na(sales_growth_pct), "", paste0("+", sales_growth_pct, "% YoY"))),
            vjust = -.4, size = 3.6) +
  geom_line(aes(y = margin_pct * max(sales) / 30, group = 1), colour = "#C0504D", linewidth = 1.1) +
  geom_point(aes(y = margin_pct * max(sales) / 30), colour = "#C0504D", size = 2.5) +
  scale_y_continuous(labels = label_dollar(scale = 1e-6, suffix = "M"),
                     sec.axis = sec_axis(~ . * 30 / max(yearly$sales), name = "Profit margin (%)")) +
  labs(title = "Annual sales, growth and profit margin", x = NULL, y = "Sales")
save_plot(p2, "02_yearly_growth_margin")

# 3. Category / sub-category: sales vs margin
p3 <- category |> ggplot(aes(sales, margin_pct, colour = category, size = abs(profit))) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey50") +
  geom_point(alpha = .8) + ggrepel::geom_text_repel(aes(label = sub_category), size = 3.4, show.legend = FALSE) +
  scale_colour_manual(values = pal) + scale_size(range = c(3, 12), guide = "none") +
  scale_x_continuous(labels = label_dollar(scale = 1e-6, suffix = "M")) +
  labs(title = "Sub-category performance: scale vs profitability", x = "Sales", y = "Profit margin (%)", colour = NULL)
save_plot(p3, "03_subcategory_sales_vs_margin")

# 4. Regional performance
p4 <- regcat |> ggplot(aes(reorder(region, -sales), sales, fill = category)) +
  geom_col() + scale_fill_manual(values = pal) +
  geom_text(data = region, aes(reorder(region, -sales), sales, label = paste0(margin_pct, "% margin"), fill = NULL),
            vjust = -.5, size = 3.6) +
  scale_y_continuous(labels = label_dollar(scale = 1e-6, suffix = "M"), expand = expansion(mult = c(0, .12))) +
  labs(title = "Regional sales by category (label = profit margin)", x = NULL, y = "Sales", fill = NULL)
save_plot(p4, "04_regional_performance")

# 5. Region x category margin heatmap
p5 <- regcat |> ggplot(aes(category, region, fill = margin_pct)) +
  geom_tile(colour = "white") + geom_text(aes(label = paste0(margin_pct, "%")), fontface = "bold") +
  scale_fill_gradient2(low = "#C0504D", mid = "white", high = "#2E8B57", midpoint = 0) +
  labs(title = "Profit margin heatmap: region x category", x = NULL, y = NULL, fill = "Margin %")
save_plot(p5, "05_region_category_heatmap", h = 4.2)

# 6. Discount impact (the headline finding)
lvl <- c("0%", "1-20%", "21-30%", "31-50%", ">50%")
p6 <- disc |> mutate(discount_band = factor(discount_band, lvl)) |>
  ggplot(aes(discount_band, margin_pct, fill = margin_pct > 0)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(margin_pct, "%\n", pct_lines_loss_making, "% loss-making")),
            vjust = ifelse(disc$margin_pct[match(lvl, disc$discount_band)] > 0, -.2, 1.2), size = 3.3) +
  scale_fill_manual(values = c("TRUE" = "#2E8B57", "FALSE" = "#C0504D")) +
  scale_y_continuous(expand = expansion(mult = .2)) +
  labs(title = "Discount depth destroys margin", x = "Discount band", y = "Profit margin (%)")
save_plot(p6, "06_discount_impact")

# 7. Seasonality
p7 <- season |> ggplot(aes(factor(order_month, labels = month.abb), avg_share_of_year_pct)) +
  geom_col(fill = "#4F81BD") + geom_hline(yintercept = 100/12, linetype = 2) +
  labs(title = "Seasonality: average share of annual sales by month", x = NULL, y = "% of year (dashed = even split)")
save_plot(p7, "07_seasonality")

# 8. Customer concentration (Pareto)
par <- cust |> arrange(desc(monetary)) |> mutate(cum_cust = row_number() / n(), cum_sales = cumsum(monetary) / sum(monetary))
p8 <- ggplot(par, aes(cum_cust, cum_sales)) + geom_line(linewidth = 1.2, colour = "#1F3A5F") +
  geom_abline(linetype = 2, colour = "grey50") +
  scale_x_continuous(labels = percent) + scale_y_continuous(labels = percent) +
  labs(title = "Customer concentration (Pareto curve)", x = "Share of customers", y = "Cumulative share of sales")
save_plot(p8, "08_customer_pareto", h = 4.8)
top20 <- par |> filter(cum_cust <= .2) |> slice_tail(n = 1) |> pull(cum_sales)
cat(sprintf("\nTop 20%% of customers generate %.1f%% of sales\n", 100 * top20))
save_tab(tibble(metric = "top20pct_customers_share_of_sales", value = top20), "kpi_concentration")
dbDisconnect(con)
