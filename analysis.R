# ==============================================================================
# analysis.R : Card Transaction Fraud Detection (EDA), charts
#
# Reads the aggregated CSVs produced by analysis.sql and saves four charts.
# Run from the repository root (in RStudio: Session > Set Working Directory >
# To Source File Location), then source the whole script.
#
# Inputs : fraud_by_product.csv, fraud_by_amount_usd.csv, by_hour.csv,
#          heatmap.csv, by_product_card.csv
# Outputs: chart_amount_bands.png, chart_hourly.png, chart_heatmap.png,
#          chart_product_card.png
#
# Note on time: TransactionDT is an offset from an undisclosed reference point,
# so hours are offset hours (not local clock time) and the 7 day cycle is not
# a real weekday.
# ==============================================================================

# Run once if needed: install.packages("tidyverse")
library(tidyverse)

# ------------------------------------------------------------------------------
# Shared style: one quiet theme, a fixed blue and orange pair, gray for context
# ------------------------------------------------------------------------------
ink      <- "#0b0b0b"   # titles and key labels
ink_2    <- "#52514e"   # subtitles, reference line labels
muted    <- "#898781"   # axis text, captions
grid_col <- "#e1e0d9"   # hairline gridlines
surface  <- "#fcfcfb"   # chart background
blue     <- "#2a78d6"   # main series and highlight
orange   <- "#eb6834"   # second series
context  <- "#c3c2b7"   # bars that give context only

source_note <- "Source: IEEE-CIS Fraud Detection (Vesta Corporation, Kaggle), 590,540 transactions."

theme_fraud <- function() {
  theme_minimal(base_size = 13) +
    theme(
      plot.background     = element_rect(fill = surface, colour = NA),
      panel.background    = element_rect(fill = surface, colour = NA),
      panel.grid.major.x  = element_blank(),
      panel.grid.minor    = element_blank(),
      panel.grid.major.y  = element_line(colour = grid_col, linewidth = 0.4),
      axis.text           = element_text(colour = muted),
      axis.title          = element_text(colour = ink_2),
      plot.title          = element_text(colour = ink, face = "bold", size = 15),
      plot.subtitle       = element_text(colour = ink_2, margin = margin(b = 10)),
      plot.caption        = element_text(colour = muted, hjust = 0, size = 9),
      strip.text          = element_text(colour = ink_2, face = "bold", hjust = 0),
      legend.position     = "top",
      legend.justification = "left",
      legend.title        = element_blank(),
      legend.text         = element_text(colour = ink_2),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.margin         = margin(14, 18, 10, 14)
    )
}

pct <- function(x, digits = 2) sprintf(paste0("%.", digits, "f%%"), x)

# Overall fraud rate, weighted by volume (frauds / transactions), used as the
# reference line in every chart
prod <- read_csv("fraud_by_product.csv", show_col_types = FALSE)
overall_rate <- sum(prod$frauds) / sum(prod$txns) * 100


# ------------------------------------------------------------------------------
# Chart A: fraud rate and share of fraud dollars by amount band (Finding 1)
# Two aligned panels: count based risk on top, dollar exposure below.
# ------------------------------------------------------------------------------
band_labels <- c("Under $50", "$50 to $100", "$100 to $250", "$250 to $1,000", "$1,000 and above")

amt <- read_csv("fraud_by_amount_usd.csv", show_col_types = FALSE) |>
  mutate(
    band = factor(
      amt_bucket,
      levels = c("01: <50", "02: 50-100", "03: 100-250", "04: 250-1000", "05: 1000+"),
      labels = band_labels
    ),
    highlight = band == "$250 to $1,000"
  )

amt_panels <- c("Fraud rate (%)", "Share of all fraud dollars (%)")
amt_long <- bind_rows(
  transmute(amt, band, highlight, value = fraud_rate_pct, panel = amt_panels[1],
            label = pct(fraud_rate_pct, 2)),
  transmute(amt, band, highlight, value = share_of_fraud_usd_pct, panel = amt_panels[2],
            label = pct(share_of_fraud_usd_pct, 1))
) |>
  mutate(panel = factor(panel, levels = amt_panels))

amt_rate_panel <- tibble(
  panel = factor(amt_panels[1], levels = amt_panels),
  band = factor("$1,000 and above", levels = band_labels),
  y = overall_rate
)

p_amt <- ggplot(amt_long, aes(x = band, y = value, fill = highlight)) +
  geom_col(width = 0.6) +
  geom_hline(data = amt_rate_panel, aes(yintercept = y), colour = ink_2, linewidth = 0.5) +
  geom_text(data = amt_rate_panel, aes(x = band, y = y, label = paste("Overall", pct(overall_rate))),
            inherit.aes = FALSE, hjust = 1, vjust = -0.7, nudge_x = 0.45,
            colour = ink_2, size = 3.5) +
  geom_text(data = filter(amt_long, highlight), aes(label = label),
            vjust = -0.6, colour = ink, size = 4) +
  facet_wrap(~panel, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c(`TRUE` = blue, `FALSE` = context), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.22))) +
  labs(
    title = "$250 to $1,000: highest fraud rate and almost half of all fraud dollars",
    subtitle = "Fraud rate and share of all fraud dollars by transaction amount band.",
    x = NULL, y = NULL, caption = source_note
  ) +
  theme_fraud()

ggsave("chart_amount_bands.png", p_amt, width = 9.5, height = 7, dpi = 150, bg = surface)


# ------------------------------------------------------------------------------
# Chart B: volume and fraud rate by offset hour, two aligned panels (Finding 2)
# Two panels instead of a dual axis, so each measure keeps its own honest scale.
# ------------------------------------------------------------------------------
hr <- read_csv("by_hour.csv", show_col_types = FALSE)

window_hours <- 5:9
window_share <- sum(hr$txns[hr$hour_of_day %in% window_hours]) / sum(hr$txns) * 100
peak <- slice_max(hr, fraud_rate_pct, n = 1)

panel_levels <- c("Transactions (thousands)", "Fraud rate (%)")
hr_long <- bind_rows(
  transmute(hr, hour_of_day, value = txns / 1000, panel = panel_levels[1]),
  transmute(hr, hour_of_day, value = fraud_rate_pct, panel = panel_levels[2])
) |>
  mutate(panel = factor(panel, levels = panel_levels))

rate_panel <- function(df) mutate(df, panel = factor(panel_levels[2], levels = panel_levels))

p_hr <- ggplot() +
  annotate("rect", xmin = min(window_hours) - 0.5, xmax = max(window_hours) + 0.5,
           ymin = -Inf, ymax = Inf, fill = blue, alpha = 0.08) +
  geom_col(data = filter(hr_long, panel == panel_levels[1]),
           aes(x = hour_of_day, y = value), fill = context, width = 0.7) +
  geom_hline(data = rate_panel(tibble(y = overall_rate)),
             aes(yintercept = y), colour = ink_2, linewidth = 0.5) +
  geom_text(data = rate_panel(tibble(x = 14.5, y = overall_rate)),
            aes(x = x, y = y, label = paste("Overall", pct(overall_rate))),
            hjust = 0.5, vjust = -0.7, colour = ink_2, size = 3.5) +
  geom_line(data = filter(hr_long, panel == panel_levels[2]),
            aes(x = hour_of_day, y = value), colour = blue, linewidth = 0.9) +
  geom_point(data = filter(hr_long, panel == panel_levels[2]),
             aes(x = hour_of_day, y = value), shape = 21, size = 2.6,
             fill = blue, colour = surface, stroke = 0.9) +
  geom_text(data = rate_panel(tibble(x = peak$hour_of_day, y = peak$fraud_rate_pct)),
            aes(x = x, y = y, label = paste0("Offset hour ", x, ": ", pct(y))),
            hjust = -0.12, vjust = -0.4, colour = ink, size = 3.8) +
  facet_wrap(~panel, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = 0:23, expand = expansion(add = 0.4)) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(
    title = "Fraud peaks in the quietest hours of the daily cycle",
    subtitle = paste0(
      "Shaded: offset hours ", min(window_hours), " to ", max(window_hours),
      ", which hold ", pct(window_share), " of all transactions.\n",
      "Hours are offsets from an undisclosed reference point, not local clock time."
    ),
    x = "Offset hour", y = NULL, caption = source_note
  ) +
  theme_fraud()

ggsave("chart_hourly.png", p_hr, width = 10, height = 6.5, dpi = 150, bg = surface)


# ------------------------------------------------------------------------------
# Chart C: fraud rate by offset hour and 7 day cycle (supports Finding 2)
# ------------------------------------------------------------------------------
hm <- read_csv("heatmap.csv", show_col_types = FALSE) |>
  mutate(cycle_day = factor(weekday_proxy, levels = 0:6, labels = paste("Day", 1:7)))

p_hm <- ggplot(hm, aes(x = hour_of_day, y = cycle_day, fill = fraud_rate_pct)) +
  geom_tile(colour = surface, linewidth = 0.8) +
  scale_fill_gradientn(
    colours = c("#cde2fb", "#86b6ef", "#3987e5", "#256abf", "#104281"),
    name = "Fraud rate (%)",
    guide = guide_colourbar(barwidth = unit(12, "lines"), barheight = unit(0.6, "lines"))
  ) +
  scale_x_continuous(breaks = 0:23, expand = c(0, 0)) +
  scale_y_discrete(limits = rev) +
  labs(
    title = "Fraud rate by offset hour and 7 day cycle",
    subtitle = "Day 1 to Day 7 repeat from the reference point and are not real weekdays.",
    x = "Offset hour", y = NULL, caption = source_note
  ) +
  theme_fraud() +
  theme(
    panel.grid.major.y = element_blank(),
    legend.title = element_text(colour = ink_2, size = 10, vjust = 0.9)
  )

ggsave("chart_heatmap.png", p_hm, width = 10, height = 5, dpi = 150, bg = surface)


# ------------------------------------------------------------------------------
# Chart D: fraud rate by product and card type (Finding 3)
# Products ordered by their overall fraud rate; credit and debit side by side.
# ------------------------------------------------------------------------------
product_order <- prod |> arrange(desc(fraud_rate_pct)) |> pull(ProductCD)

pc <- read_csv("by_product_card.csv", show_col_types = FALSE) |>
  filter(card_type %in% c("credit", "debit")) |>
  mutate(
    ProductCD = factor(ProductCD, levels = product_order),
    card_type = factor(card_type, levels = c("credit", "debit"), labels = c("Credit", "Debit"))
  )

dodge_width <- 0.7
top_cell <- slice_max(pc, fraud_rate_pct, n = 1) |>
  mutate(x = as.numeric(ProductCD) + if_else(card_type == "Credit", -dodge_width / 4, dodge_width / 4))

p_pc <- ggplot(pc, aes(x = ProductCD, y = fraud_rate_pct, fill = card_type)) +
  geom_col(position = position_dodge(width = dodge_width), width = 0.62) +
  geom_hline(yintercept = overall_rate, colour = ink_2, linewidth = 0.5) +
  geom_text(data = top_cell, aes(x = x, y = fraud_rate_pct, label = pct(fraud_rate_pct)),
            inherit.aes = FALSE, vjust = -0.6, colour = ink, size = 4) +
  scale_fill_manual(values = c(Credit = blue, Debit = orange)) +
  scale_y_continuous(labels = function(x) paste0(x, "%"),
                     expand = expansion(mult = c(0, 0.12))) +
  labs(
    title = "Product C on credit cards is the riskiest combination",
    subtitle = paste0("Fraud rate by product code and card type, products ordered by overall fraud rate.\n",
                      "The horizontal line marks the overall rate of ", pct(overall_rate), "."),
    x = "Product code", y = "Fraud rate", caption = source_note
  ) +
  theme_fraud()

ggsave("chart_product_card.png", p_pc, width = 9, height = 5.5, dpi = 150, bg = surface)
