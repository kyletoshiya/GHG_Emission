# Replication package: firm-establishment matched GHG emissions, South Korea 2012-2023

Version 2026-10-18 (expected-emissions residual allocation).

This package is self-contained. It takes the cleaned firm-establishment panel as input, estimates the
missing establishment-level Scope 1 and Scope 2 emissions, produces the released dataset, and
reproduces the validation results reported in the Methods and Technical Validation sections.

## Contents

```
README.md
dataset/   KR_firm_estab_GHG_2012_2023.dta, .csv   released dataset (15,868 establishment-years, 26 variables)
data/      NGMS_ENV_ready_2026_09_13.dta           input: cleaned and matched firm-establishment panel
           firm_info.dta                           input: firm characteristics (industry, region)
           region_code.dta                         input: crosswalk from si-gun-gu codes to GIS codes
code/      0_master.do                             driver: runs the pipeline in order
           1a_firm_decomp_s1_s2.do                 firm-year Scope 1 share (fallback composition) and its validation
           1b_reporting_coverage.do                reporting and coverage diagnostics
           2_estimate_missing.do                   estimation of missing cells and validation of the allocation key
           programs_estimate_missing.do            subroutine defining allocate_joint (called by 2 and 3d)
           3a_build_final_dataset.do               released dataset, diagnostics file, firm-year totals
           3b_accounting_diagnostics.do            conservation, sources, consistency ratio, reporting gaps
           3c_parameter_sensitivity.do             sensitivity of the own-history tier to its parameters
           3d_masking_validation.do                end-to-end validation with artificial missingness
           4_maps.do                               county-level emission aggregation by headquarters and establishment location
output/    results/, figures/                      produced by the pipeline (included for reference)
```

The data cleaning that produces `data/NGMS_ENV_ready_2026_09_13.dta` from the ENV-Info and NGMS downloads
(address standardisation, 2015 county codes, firm-name harmonisation, agreed value corrections, 2012-2023
window) is documented in the paper and is not part of this package. Number 4 in the script numbering is
reserved for the map figures.

## Requirements and run time

Stata 17 (MP or SE). No user-written commands are required. Run from the package root:

```
stata-mp -b do code/0_master.do
```

or set the global `path` to the package root before running. The whole pipeline takes about one
minute on a desktop computer. Each script can also be run on its own in the order above (it finds the
package root from the working directory). Logs are written next to the scripts.

Parameters of the own-history tier are set in the driver (globals `p_nn` = 3 nearest reporting years,
bound `p_lo` = 0.2 and `p_hi` = 5 times the firm fallback, applied when the nearest own report is
more than `p_bgap` = 2 years away or fewer than `p_bmin` = 3 own reporting years exist). Random
masking uses fixed seeds (20261006 + replication number); draws are made after sorting, so results do
not depend on the row order of the input.

## Outputs and the tables and figures of the paper

| Script | Output (output/results unless noted) | Used for |
|---|---|---|
| 1a | firm_year_ngms_s1_s2.dta, decompose_source_summary.dta, decompose_validation.dta, decompose_gate_sensitivity.dta | Methods (share rule counts), Technical Validation "Fallback composition" |
| 1b | reporting_counts.dta, coverage_by_year.dta, env_ngms_consistency_by_year.dta | Table 1 (reported/missing rows), coverage figures |
| 2 | estimates_completed_estab_emissions.dta, estimates_firm_year.dta, estimates_s1_/s2_metrics_*.dta, estimates_energy_* (comparison run), output/figures/validation_*.png | Table 3, Figure 2, Supplementary Figure 5 |
| 3a | KR_firm_estab_GHG_2012_2023.dta (copied to dataset/), KR_firm_estab_GHG_2012_2023_diagnostics.dta, firm_year_totals.dta | Released dataset, Table 5, firm-year totals for the map figures |
| 3b | final_status_by_scope.dta, conservation_by_cause.dta, conservation_by_year.dta, ratio_distribution.dta, gap_distribution.dta, method_comparison.dta | Table 1 (final status rows), Table 2, Methods (ratio, reporting gaps, comparison with the energy-share key) |
| 3c | sensitivity_own_history.dta | Appendix Table 2 |
| 3d | masking_results.dta, masking_by_gap.dta, masking_replications.dta; scratch runs under output/masking/ | Table 4, Appendix Tables 3 and 4 |
| 4 | gis_firm.csv, gis_est.csv | Figure 3 and 4 |
Tables in the paper are transcribed from these files.

## Released dataset: dataset/KR_firm_estab_GHG_2012_2023

One row per establishment-year (15,868 rows; 308 firms, 1,941 establishments, 2012-2023). Emissions in tCO2eq.

| Variable | Type | Description |
|---|---|---|
| year | integer | Year |
| firm_id | integer | Firm identifier, constant over years (assigned to the harmonised firm name) |
| firm_name | string | Firm name (harmonised to the 2023 name) |
| estab_id | integer | Establishment identifier, constant over years (assigned to the harmonised firm and establishment names) |
| estab_name | string | Establishment name |
| address | string | Establishment address |
| sido, sido_code | string, integer | Province name and code |
| sigungu, sigungu_code | string, integer | County name and code, harmonised to the 2015 administrative divisions |
| industry, sub_industry | string | Establishment 1-digit and 2-digit industry codes (ENV-Info) |
| firm_industry, firm_sub_industry | string | Firm 1-digit and 2-digit industry codes (KSIC, from Value Search; constant over time) |
| product | string | Establishment main product |
| employee | integer | Number of employees |
| revenue | integer | Revenue (million KRW) |
| energy | numeric | Energy use (TJ) |
| water, waste, chemicals | numeric | Water use, waste generation, chemical emissions (ton) |
| emi_total_firm | numeric | NGMS firm-year total (Scope 1 + Scope 2) |
| emi_s1_firm, emi_s2_firm | numeric | Firm-year Scope 1 and Scope 2 totals: sums of the final establishment values |
| emi_s1_estab, emi_s2_estab | numeric | Final establishment-level Scope 1 and Scope 2 emissions (missing = unfilled) |
| emi_s1_src, emi_s2_src | integer | Source of the final value: 0 reported in ENV-Info; 1 estimated from the establishment's own reports in other years; 2 estimated from the firm's other establishments (same or other years); 3 set to zero because the reported subtotals already reach the NGMS total; missing = unfilled (no energy use reported, or reported subtotals exceed the NGMS total by more than 2%) |

`firm_id`, `estab_id` and `year` uniquely identify rows. The companion diagnostics file
(output/results/KR_firm_estab_GHG_2012_2023_diagnostics.dta, same keys) adds the reported firm-year subtotals,
the unreported residual, the expected emissions of missing cells before reconciliation, the ratio of the
residual to the expected emissions with its flag, the reconciliation flag and the signed gap to the NGMS
total, the fallback Scope 1 share with its source step, the years to the nearest own report, the number of
own reporting years used, the bound indicator and the reason a cell is unfilled.

## Method in brief

Reported ENV-Info establishment values are kept. For each missing establishment-scope cell an expected
emission is formed as predicted scope intensity (tCO2eq per TJ) times the establishment's energy use: from
the establishment's own reports in other years (median over the three nearest reporting years, bounded
relative to the firm fallback when the history is distant or thin) or, for establishments that never
report the scope, from the firm-year Scope 1 share (1a) times the intensity of the firm's establishments
reporting both scopes. The unreported residual, NGMS total minus all reported values (floored at zero), is
allocated to the missing cells in proportion to their expected emissions, so that establishment values add
up to the NGMS total whenever every missing cell can be estimated. See the Methods section of the paper.
