/*
0_master.do -- master do-file for the estimation replication pipeline (expected-emissions residual allocation).

Run from the project root, or set the global macro `path' to the project root first.
Input: data/NGMS_ENV_ready_2026_09_13.dta (analysis-ready firm-establishment panel; produced by the data
cleaning scripts in code/cleaning/, which are not part of this package).
  1a  decompose the NGMS firm-year total into scope shares (firm-level fallback composition)
  1b  coverage and reporting diagnostics
  2   expected-emissions residual allocation, both scopes, with validation of the allocation key (Table 3, Figures 2 and 5)
  3a  final establishment-year dataset (output/results/KR_firm_estab_GHG_2012_2023.dta) and diagnostics file
  3b  accounting diagnostics (Tables 1 and 2; conservation, sources, consistency ratio, reporting gaps, method comparison)
  3c  sensitivity of the own-history tier to its parameters (Appendix Table 2)
  3d  end-to-end validation with artificial missingness (Table 4, Appendix Tables 3 and 4)
  4   reserved for the map figures (coauthors)
Method v5 (energy-share allocation of decomposed scope totals) is preserved in code/old_v5/.
*/
version 17
clear all
set more off
if "${path}" == "" {
    global path "`c(pwd)'"
    capture confirm file "${path}/code/0_master.do"
    if _rc {
        global path "`c(pwd)'/.."
    }
}
global data "${path}/data"
global out  "${path}/output"
* own-history tier parameters (see 3c_parameter_sensitivity.do)
global p_nn   3
global p_lo   0.2
global p_hi   5
global p_bgap 2
global p_bmin 3
capture confirm file "${data}/NGMS_ENV_ready_2026_09_13.dta"
if _rc {
    display as error "Cannot find data/NGMS_ENV_ready_2026_09_13.dta. Run from the project root or set global path to the project root."
    exit 601
}
cap mkdir "${out}"
cap mkdir "${out}/results"
cap mkdir "${out}/figures"
do "${path}/code/1a_firm_decomp_s1_s2.do"
do "${path}/code/1b_reporting_coverage.do"
do "${path}/code/2_estimate_missing.do"
do "${path}/code/3a_build_final_dataset.do"
do "${path}/code/3b_accounting_diagnostics.do"
do "${path}/code/3c_parameter_sensitivity.do"
do "${path}/code/3d_masking_validation.do"
do "${path}/code/4_maps.do"
display as text "0_master complete."
