# ==============================================================================
# Day 6 — Visualizations in R (Fraud Analytics Project)
# ==============================================================================

# Setup Environment 
# Run the installation line once if tidyverse isn't installed yet:
# install.packages("tidyverse") 
library(tidyverse)

# ------------------------------------------------------------------------------
# Chart A — Histogram (Transaction Amount Distribution, Log Scale)
# ------------------------------------------------------------------------------
# Aggregated CSVs live alongside this script in the repo root
df <- read_csv("amount_sample.csv") |>
  mutate(status = ifelse(isFraud == 1, "Fraud", "Legit"))

ggplot(df, aes(x = TransactionAmt, fill = status)) +
  geom_histogram(bins = 50, alpha = 0.7, position = "identity") +
  scale_x_log10(labels = scales::dollar) +
  facet_wrap(~status, ncol = 1, scales = "free_y") +
  labs(title = "Transaction Amount: Fraud vs Legit (log scale)",
       x = "Amount (log)", y = "Transactions") +
  theme_minimal(base_size = 13)

# Saves directly to your project directory
ggsave("chart_amount_hist.png", width = 9, height = 6, dpi = 150)


# ------------------------------------------------------------------------------
# Chart B — Heatmap (Fraud Rate by Hour × Day)
# ------------------------------------------------------------------------------
hm <- read_csv("heatmap.csv")

ggplot(hm, aes(x = hour_of_day, y = factor(weekday_proxy), fill = fraud_rate_pct)) +
  geom_tile(color = "white") +
  scale_fill_gradient(low = "#eef6f2", high = "#0f6e4d") +
  labs(title = "Fraud Rate by Hour and Day",
       x = "Hour of day", y = "Day (weekly cycle)", fill = "Fraud %") +
  theme_minimal(base_size = 13)

ggsave("chart_heatmap.png", width = 10, height = 5, dpi = 150)


# ------------------------------------------------------------------------------
# Chart C — Faceted Column Chart (Product Code × Card Type)
# ------------------------------------------------------------------------------
fp <- read_csv("by_product_card.csv")

ggplot(fp, aes(x = ProductCD, y = fraud_rate_pct, fill = ProductCD)) +
  geom_col() +
  facet_wrap(~card_type) +
  labs(title = "Fraud Rate by Product, Split by Card Type",
       x = "Product code", y = "Fraud rate (%)") +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

ggsave("chart_facet.png", width = 10, height = 5, dpi = 150)