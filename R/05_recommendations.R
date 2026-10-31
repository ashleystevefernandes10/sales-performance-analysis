# 05_recommendations.R -- quantify profit levers (discount cap, mix) -- scenario assumptions are explicit
source("R/00_setup.R")
con <- connect()
d <- dbGetQuery(con, "SELECT * FROM sales_clean WHERE discount_imputed = 0 AND order_year = 2024")
base_profit <- sum(d$profit); base_sales <- sum(d$sales)

# ---- Lever 1: cap discounts at CAP; assume volume retention on re-priced lines ----
scenario <- function(cap, retention) {
  x <- d |> mutate(over = discount > cap,
    new_sales  = ifelse(over, sales * (1 - cap) / (1 - discount), sales),
    new_profit = ifelse(over, retention * (new_sales - cost), profit),
    new_sales  = ifelse(over, retention * new_sales, sales))
  tibble(cap = cap, retention = retention,
         profit = sum(x$new_profit), d_profit = sum(x$new_profit) - base_profit,
         sales = sum(x$new_sales), margin = sum(x$new_profit) / sum(x$new_sales))
}
grid <- expand.grid(cap = c(.2, .3, .4), retention = c(.6, .8, 1)) |> purrr::pmap_dfr(scenario)
grid <- grid |> mutate(base_profit = base_profit, uplift_pct_of_profit = d_profit / base_profit)
print(grid); save_tab(grid, "reco_discount_cap_scenarios")

p <- grid |> mutate(cap = factor(cap, labels = c("Cap 20%", "Cap 30%", "Cap 40%")),
                    retention = factor(retention, labels = c("60% retained", "80% retained", "100% retained"))) |>
  ggplot(aes(retention, cap, fill = d_profit)) + geom_tile(colour = "white") +
  geom_text(aes(label = dollar(d_profit, scale = 1e-3, suffix = "k", accuracy = 1)), fontface = "bold") +
  scale_fill_gradient2(low = "#C0504D", mid = "white", high = "#2E8B57", midpoint = 0, labels = label_dollar(scale = 1e-3, suffix = "k")) +
  labs(title = "FY2024 profit uplift from capping discounts", subtitle = "Re-priced lines at the cap; share of volume retained on those lines",
       x = NULL, y = NULL, fill = "Profit change")
save_plot(p, "12_discount_cap_scenarios", h = 4.4)

# ---- Lever 2: structurally unprofitable sub-categories (FY2024) ----
sub <- d |> group_by(category, sub_category) |>
  summarise(sales = sum(sales), profit = sum(profit), margin = profit / sales, avg_disc = mean(discount), .groups = "drop") |>
  arrange(margin)
save_tab(sub, "reco_subcategory_fy2024"); print(head(sub, 4))

# ---- Lever 3: region/category pockets that lose money ----
pockets <- d |> group_by(region, category, sub_category) |>
  summarise(sales = sum(sales), profit = sum(profit), .groups = "drop") |> filter(profit < 0) |> arrange(profit)
save_tab(pockets, "reco_loss_pockets_fy2024")
cat(sprintf("\nFY2024 loss-making pockets: %d, total loss $%s\n", nrow(pockets), format(round(sum(pockets$profit)), big.mark = ",")))
dbDisconnect(con)
