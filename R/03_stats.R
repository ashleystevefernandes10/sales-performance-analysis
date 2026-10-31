# 03_stats.R -- statistical analysis of profitability drivers
source("R/00_setup.R")
con <- connect()
d <- dbGetQuery(con, "SELECT * FROM sales_clean WHERE discount_imputed = 0") |>
  mutate(margin = profit / sales, across(c(category, region, segment), factor))
out <- list()

# 1. Correlation between discount and margin
ct <- cor.test(d$discount, d$margin, method = "spearman", exact = FALSE)
out$spearman <- tibble(test = "Spearman: discount vs margin", estimate = unname(ct$estimate), p_value = ct$p.value)

# 2. Welch t-test: margin when discount >30% vs <=30%
tt <- t.test(margin ~ I(discount > .3), data = d)
out$ttest <- tibble(test = "Welch t-test: margin, discount<=30% vs >30%",
                    estimate = unname(diff(rev(tt$estimate))), p_value = tt$p.value)

# 3. Do regions differ in margin? (Kruskal-Wallis, robust to non-normality)
kw <- kruskal.test(margin ~ region, data = d)
out$kw_region <- tibble(test = "Kruskal-Wallis: margin by region", estimate = unname(kw$statistic), p_value = kw$p.value)
kw2 <- kruskal.test(margin ~ category, data = d)
out$kw_cat <- tibble(test = "Kruskal-Wallis: margin by category", estimate = unname(kw2$statistic), p_value = kw2$p.value)

stats_tbl <- bind_rows(out); print(stats_tbl); save_tab(stats_tbl, "stats_tests")

# 4. Multiple regression: what drives margin?
fit <- lm(margin ~ discount + I(discount^2) + category + region + segment + log(quantity), data = d)
coefs <- broom::tidy(fit, conf.int = TRUE); print(summary(fit)$r.squared)
save_tab(coefs, "stats_regression_coefficients")
cat(sprintf("\nRegression R-squared: %.3f\n", summary(fit)$r.squared))

p <- coefs |> filter(term != "(Intercept)") |>
  ggplot(aes(estimate, reorder(term, estimate))) +
  geom_vline(xintercept = 0, linetype = 2) +
  geom_pointrange(aes(xmin = conf.low, xmax = conf.high), colour = "#1F3A5F") +
  labs(title = "Drivers of profit margin (OLS, 95% CI)", x = "Effect on margin (pp as fraction)", y = NULL)
save_plot(p, "09_margin_drivers_regression")

# 5. Break-even discount by category: where does margin cross zero?
be <- d |> group_by(category, discount_band) |> summarise(margin = sum(profit) / sum(sales), .groups = "drop")
save_tab(be, "stats_margin_by_category_discount")
p2 <- be |> mutate(discount_band = factor(discount_band, c("0%", "1-20%", "21-30%", "31-50%", ">50%"))) |>
  ggplot(aes(discount_band, margin, colour = category, group = category)) +
  geom_hline(yintercept = 0, linetype = 2) + geom_line(linewidth = 1.1) + geom_point(size = 2.5) +
  scale_colour_manual(values = pal) + scale_y_continuous(labels = percent) +
  labs(title = "Margin by discount band and category", x = "Discount band", y = "Profit margin", colour = NULL)
save_plot(p2, "10_margin_by_discount_category")
dbDisconnect(con)
