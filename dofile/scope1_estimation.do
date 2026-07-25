

clear all

global data = "${main}"
global out = "${main}/out"

local mincell 25
local bases "employee revenue energy"
tempfile analysis_base validation_all

cap mkdir "${out}"
cap mkdir "${out}/results"
cap mkdir "${out}/figures"

* 1. Build analysis file.

use "${data}/NGMS_ENV_matched.dta", clear
compress
confirm variable sgg_code
label var sgg_code "Harmonized county code"

egen firm_id = group(firm_name), missing label
egen estab_id = group(firm_name est_name), missing label
egen firmyear_id = group(firm_id year), missing label
isid firm_id estab_id year

bys firmyear_id: gen K_ft = _N // # of estab, firm-level
bys firmyear_id: egen actual_sum_env = total(est_emission_scope1) // scope 1 emission, firm-level 
bys firmyear_id: egen n_env_scope1 = count(est_emission_scope1)

* Sample A: complete observed ENV scope 1 firm-years.
* Sample B: other firm-years with positive NGMS scope 1.
gen byte sampleA = (n_env_scope1 == K_ft & actual_sum_env > 0)
gen byte sampleB = (!sampleA & emission_ngms > 0)

gen double actual_share = est_emission_scope1 / actual_sum_env if sampleA
gen double actual_emis_env = est_emission_scope1 if sampleA

label var actual_share "ENV scope 1 within-firm allocation share"
label var actual_emis_env "Observed ENV establishment scope 1 emissions"
label var actual_sum_env "Observed ENV firm-year scope 1 total"
label var sampleA "Complete observed ENV scope 1 firm-year with positive total"
label var sampleB "Non-Sample-A firm-year with positive NGMS emissions"


* Cells and shares.
gen str120 ind1 = industry
replace ind1 = "Unknown" if missing(ind1) | ind1 == ""

gen byte k_class = .
replace k_class = 1 if K_ft == 1
replace k_class = 2 if inrange(K_ft, 2, 3)
replace k_class = 3 if inrange(K_ft, 4, 9)
replace k_class = 4 if K_ft >= 10 & K_ft < .

label define k_class_lbl 1 "1 estab" 2 "2-3 estabs" 3 "4-9 estabs" 4 "10+ estabs", replace
label values k_class k_class_lbl

xtile emis_q = emission_ngms if emission_ngms > 0, nq(4)
replace emis_q = 0 if missing(emis_q)

egen cell3 = group(ind1 k_class emis_q), missing
label var cell3 "1-digit industry x K class x NGMS emissions quartile"

foreach b of local bases {
    gen double value_`b' = `b'
    replace value_`b' = . if value_`b' < 0
    
    bys firmyear_id: egen double total_`b'_valid = total(value_`b')
    
    gen double share_`b' = value_`b' / total_`b'_valid ///
        if total_`b'_valid > 0 & !missing(value_`b')
	
    gen byte positive_`b' = (share_`b' > 0 & !missing(share_`b'))
    bys firmyear_id: egen n_positive_`b' = total(positive_`b')
    
    label var share_`b' "Within-firm-year `b' share"
}

gen byte actual_positive = (actual_share > 0 & !missing(actual_share))
bys firmyear_id: egen n_actual_positive = total(actual_positive)

gen byte eval_common = sampleA ///
    & n_positive_employee == K_ft ///
    & n_positive_revenue == K_ft ///
    & n_positive_energy == K_ft ///
    & n_actual_positive == K_ft
label var eval_common "Common positive Sample-A firm-year for validation"

save `analysis_base', replace
save "${out}/results/method_v3_log_analysis_dataset.dta", replace

* 2. Leave-one-firm-out validation.

clear
save `validation_all', emptyok replace

foreach b of local bases {
    use `analysis_base', clear

    gen double log_bias = ln(share_`b') - ln(actual_share) ///
        if sampleA & share_`b' > 0 & actual_share > 0
    label var log_bias "log(`b' share) - log(actual ENV scope 1 allocation share)"

    preserve
    keep if !missing(log_bias)
    bys cell3: egen double sum_cell = total(log_bias)
    bys cell3: egen N_cell = count(log_bias)
    bys cell3 firm_id: egen double sum_firm_cell = total(log_bias)
    bys cell3 firm_id: egen N_firm_cell = count(log_bias)
    keep cell3 firm_id sum_cell N_cell sum_firm_cell N_firm_cell
    duplicates drop
    gen N_excl = N_cell - N_firm_cell
    gen double mu_loo = (sum_cell - sum_firm_cell) / N_excl if N_excl >= `mincell'
    gen str8 selected_tier = "cell3" if !missing(mu_loo)
    gen N_train_cell = N_excl if !missing(mu_loo)
    keep cell3 firm_id mu_loo selected_tier N_train_cell
    tempfile loo_cell3
    save `loo_cell3', replace
    restore

    merge m:1 cell3 firm_id using `loo_cell3', nogen keep(master match)

    keep if eval_common & share_`b' > 0 & actual_share > 0 & !missing(mu_loo)

    gen double base_share = share_`b'
    gen double pred_share_bc_raw = exp(ln(base_share) - mu_loo)
    bys firmyear_id: egen double pred_share_bc_total = total(pred_share_bc_raw)
    gen double pred_share_bc = pred_share_bc_raw / pred_share_bc_total ///
        if pred_share_bc_total > 0
    gen double pred_emis_bc = actual_sum_env * pred_share_bc

    gen double err_share_bc = pred_share_bc - actual_share
    gen double err_emis_bc = pred_emis_bc - actual_emis_env
    gen double ln_actual_emis = ln(actual_emis_env)
    gen double ln_pred_emis_bc = ln(pred_emis_bc)
    gen double err_ln_emis_bc = ln_pred_emis_bc - ln_actual_emis

    foreach v in share emis ln_emis {
        gen double abs_`v'_bc = abs(err_`v'_bc)
        gen double sq_`v'_bc = err_`v'_bc^2
    }

    gen str8 base = "`b'"
    gen byte base_order = cond(base == "employee", 1, cond(base == "revenue", 2, 3))

    keep base_order base firm_id firmyear_id estab_id firm_name est_name ///
        address year sgg_code K_ft emission_ngms actual_sum_env actual_share actual_emis_env ///
        base_share pred_share_bc_raw pred_share_bc pred_emis_bc ///
        mu_loo selected_tier N_train_cell ln_actual_emis ln_pred_emis_bc ///
        err_* abs_* sq_*

    append using `validation_all'
    save `validation_all', replace
}

use `validation_all', clear
compress
save "${out}/results/method_v3_log_validation_predictions.dta", replace

* Cell-support diagnostics.
use "${out}/results/method_v3_log_validation_predictions.dta", clear
gen byte tier_order = 1
gen str80 tier_label = "1-digit industry x K class x NGMS emissions quartile"

gen one = 1
collapse ///
    (count) n_obs=one ///
    (min) min_N_train=N_train_cell ///
    (p25) p25_N_train=N_train_cell ///
    (p50) median_N_train=N_train_cell ///
    (p75) p75_N_train=N_train_cell ///
    (max) max_N_train=N_train_cell, ///
    by(base_order base tier_order selected_tier tier_label)
sort base_order tier_order
save "${out}/results/method_v3_log_cell_support.dta", replace

* 3. Performance metrics.

* (1) Establishment-year.
use "${out}/results/method_v3_log_validation_predictions.dta", clear
gen one = 1
collapse ///
    (count) N_estab_year=one ///
    (mean) MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc ///
           MAE_ln_emis_bc=abs_ln_emis_bc MSE_ln_emis_bc=sq_ln_emis_bc ///
           MAE_share_bc=abs_share_bc MSE_share_bc=sq_share_bc, ///
    by(base_order base)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
gen RMSE_ln_emis_bc = sqrt(MSE_ln_emis_bc)
gen RMSE_share_bc = sqrt(MSE_share_bc)
sort base_order
save "${out}/results/method_v3_log_metrics_estab_year.dta", replace

* (2) County-year.
use "${out}/results/method_v3_log_validation_predictions.dta", clear
keep if !missing(sgg_code)
gen one = 1
collapse ///
    (sum) actual_emis=actual_emis_env pred_emis_bc=pred_emis_bc ///
    (count) n_estab_year=one, ///
    by(base_order base year sgg_code)
bys base_order base year: egen double actual_year_total = total(actual_emis)
bys base_order base year: egen double pred_year_total_bc = total(pred_emis_bc)
gen double actual_spatial_share = actual_emis / actual_year_total if actual_year_total > 0
gen double pred_spatial_share_bc = pred_emis_bc / pred_year_total_bc if pred_year_total_bc > 0
gen double err_emis_bc = pred_emis_bc - actual_emis
gen double err_spatial_share_bc = pred_spatial_share_bc - actual_spatial_share
gen double abs_emis_bc = abs(err_emis_bc)
gen double sq_emis_bc = err_emis_bc^2
gen double abs_spatial_share_bc = abs(err_spatial_share_bc)
gen double sq_spatial_share_bc = err_spatial_share_bc^2
save "${out}/results/method_v3_log_by_sigungu_year.dta", replace

collapse ///
    (count) N_sigungu_year=actual_emis ///
    (mean) MAE_spatial_share_bc=abs_spatial_share_bc MSE_spatial_share_bc=sq_spatial_share_bc ///
           MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc, ///
    by(base_order base)
gen RMSE_spatial_share_bc = sqrt(MSE_spatial_share_bc)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
sort base_order
save "${out}/results/method_v3_log_metrics_sigungu_year.dta", replace

* (3) Establishment-level.
use "${out}/results/method_v3_log_validation_predictions.dta", clear
gen one = 1
collapse ///
    (sum) actual_emis=actual_emis_env pred_emis_bc=pred_emis_bc ///
    (count) n_estab_year=one, ///
    by(base_order base firm_id estab_id firm_name est_name sgg_code)
bys base_order base firm_id: egen double actual_firm_total = total(actual_emis)
bys base_order base firm_id: egen double pred_firm_total_bc = total(pred_emis_bc)
gen double actual_alloc_share = actual_emis / actual_firm_total if actual_firm_total > 0
gen double pred_alloc_share_bc = pred_emis_bc / pred_firm_total_bc if pred_firm_total_bc > 0
gen double ln_actual_emis = ln(actual_emis)
gen double ln_pred_emis_bc = ln(pred_emis_bc)
gen double err_emis_bc = pred_emis_bc - actual_emis
gen double err_alloc_share_bc = pred_alloc_share_bc - actual_alloc_share
gen double err_ln_emis_bc = ln_pred_emis_bc - ln_actual_emis
gen double abs_emis_bc = abs(err_emis_bc)
gen double sq_emis_bc = err_emis_bc^2
gen double abs_alloc_share_bc = abs(err_alloc_share_bc)
gen double sq_alloc_share_bc = err_alloc_share_bc^2
gen double abs_ln_emis_bc = abs(err_ln_emis_bc)
gen double sq_ln_emis_bc = err_ln_emis_bc^2
save "${out}/results/method_v3_log_by_estab.dta", replace

gen one = 1
collapse ///
    (count) N_estab=one ///
    (mean) MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc ///
           MAE_alloc_share_bc=abs_alloc_share_bc MSE_alloc_share_bc=sq_alloc_share_bc ///
           MAE_ln_emis_bc=abs_ln_emis_bc MSE_ln_emis_bc=sq_ln_emis_bc, ///
    by(base_order base)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
gen RMSE_alloc_share_bc = sqrt(MSE_alloc_share_bc)
gen RMSE_ln_emis_bc = sqrt(MSE_ln_emis_bc)
sort base_order
save "${out}/results/method_v3_log_metrics_estab.dta", replace

* (4) County-level.
use "${out}/results/method_v3_log_by_sigungu_year.dta", clear
collapse ///
    (sum) actual_emis pred_emis_bc ///
    (count) n_sigungu_year=year, ///
    by(base_order base sgg_code)
bys base_order base: egen double actual_total = total(actual_emis)
bys base_order base: egen double pred_total_bc = total(pred_emis_bc)
gen double actual_spatial_share = actual_emis / actual_total if actual_total > 0
gen double pred_spatial_share_bc = pred_emis_bc / pred_total_bc if pred_total_bc > 0
gen double err_emis_bc = pred_emis_bc - actual_emis
gen double err_spatial_share_bc = pred_spatial_share_bc - actual_spatial_share
gen double abs_emis_bc = abs(err_emis_bc)
gen double sq_emis_bc = err_emis_bc^2
gen double abs_spatial_share_bc = abs(err_spatial_share_bc)
gen double sq_spatial_share_bc = err_spatial_share_bc^2
save "${out}/results/method_v3_log_by_sigungu.dta", replace

gen one = 1
collapse ///
    (count) N_sigungu=one ///
    (mean) MAE_spatial_share_bc=abs_spatial_share_bc MSE_spatial_share_bc=sq_spatial_share_bc ///
           MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc, ///
    by(base_order base)
gen RMSE_spatial_share_bc = sqrt(MSE_spatial_share_bc)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
sort base_order
save "${out}/results/method_v3_log_metrics_sigungu.dta", replace

* 4. Fill missing scope 1 emissions.

use `analysis_base', clear

gen double s1_log_bias_energy = ln(share_energy) - ln(actual_share) ///
    if sampleA & share_energy > 0 & actual_share > 0
quietly summarize s1_log_bias_energy, meanonly
local s1_global_mu_energy = r(mean)

preserve
keep if !missing(s1_log_bias_energy)
bys cell3: egen double sum_cell = total(s1_log_bias_energy)
bys cell3: egen N_cell = count(s1_log_bias_energy)
keep cell3 sum_cell N_cell
duplicates drop
gen double s1_mu_energy_cell = sum_cell / N_cell if N_cell >= `mincell'
gen N_train_cell_energy = N_cell if !missing(s1_mu_energy_cell)
keep cell3 s1_mu_energy_cell N_train_cell_energy
tempfile s1_energy_cell
save `s1_energy_cell', replace
restore

merge m:1 cell3 using `s1_energy_cell', nogen keep(master match)

gen byte s1_energy_sha_ok = n_positive_energy == K_ft ///
    & share_energy > 0
gen double s1_mu_energy = s1_mu_energy_cell
replace s1_mu_energy = `s1_global_mu_energy' ///
    if s1_energy_sha_ok & missing(s1_mu_energy) ///
    & !missing(`s1_global_mu_energy')

gen str8 s1_est_base = ""
replace s1_est_base = "energy" ///
    if s1_energy_sha_ok & !missing(s1_mu_energy)

gen str8 s1_est_tier = ""
replace s1_est_tier = "cell3" ///
    if s1_energy_sha_ok & !missing(s1_mu_energy_cell)
replace s1_est_tier = "global" ///
    if s1_energy_sha_ok & missing(s1_mu_energy_cell) ///
    & !missing(s1_mu_energy)

gen double pred_s1_energy_sha_raw = exp(ln(share_energy) - s1_mu_energy) ///
    if s1_energy_sha_ok & !missing(s1_mu_energy)
bys firmyear_id: egen double pred_s1_energy_sha_tot = total(pred_s1_energy_sha_raw)
gen double pred_s1_energy_sha = pred_s1_energy_sha_raw ///
    / pred_s1_energy_sha_tot if pred_s1_energy_sha_tot > 0

* Actual-first residual allocation.
gen byte s1_missing_estab = missing(est_emission_scope1)
gen double s1_obs_subtotal = actual_sum_env
gen double s1_resid_raw = emission_ngms - s1_obs_subtotal ///
    if !missing(emission_ngms)
gen byte s1_actual_gt_firm = ///
    (s1_obs_subtotal > emission_ngms) if !missing(emission_ngms)
gen double s1_resid_alloc = s1_resid_raw
replace s1_resid_alloc = 0 ///
    if s1_resid_alloc < 0 ///
    & !missing(s1_resid_alloc)

gen double pred_s1_sha_miss_raw = pred_s1_energy_sha_raw ///
    if s1_missing_estab
bys firmyear_id: egen double pred_s1_sha_miss_tot = ///
    total(pred_s1_sha_miss_raw)
gen double pred_s1_sha_resid = pred_s1_energy_sha_raw ///
    / pred_s1_sha_miss_tot ///
    if s1_missing_estab & pred_s1_sha_miss_tot > 0

gen double emi_s1_est = ///
    s1_resid_alloc * pred_s1_sha_resid ///
    if s1_missing_estab ///
    & !missing(s1_resid_alloc) ///
    & !missing(pred_s1_sha_resid)

gen double emi_s1_final = est_emission_scope1
replace emi_s1_final = emi_s1_est ///
    if missing(emi_s1_final)

gen byte emi_s1_is_est = .
replace emi_s1_is_est = 0 if !missing(est_emission_scope1)
replace emi_s1_is_est = 1 if missing(est_emission_scope1) ///
    & !missing(emi_s1_est)

gen str10 emi_s1_source = ""
replace emi_s1_source = "actual" if emi_s1_is_est == 0
replace emi_s1_source = "estimated" if emi_s1_is_est == 1
replace emi_s1_source = "unfilled" if missing(emi_s1_final)

gen str40 s1_unfill_reason = ""
replace s1_unfill_reason = "no_energy_sha" ///
    if missing(est_emission_scope1) & missing(emi_s1_est) ///
    & !s1_energy_sha_ok
replace s1_unfill_reason = "no_mu" ///
    if missing(est_emission_scope1) & missing(emi_s1_est) ///
    & s1_energy_sha_ok & missing(s1_mu_energy)
replace s1_unfill_reason = "no_s1_total" ///
    if missing(est_emission_scope1) & missing(emi_s1_est) ///
    & missing(emission_ngms)
replace s1_unfill_reason = "no_resid_sha" ///
    if missing(est_emission_scope1) & missing(emi_s1_est) ///
    & !missing(emission_ngms) & s1_energy_sha_ok ///
    & !missing(s1_mu_energy) ///
    & missing(pred_s1_sha_resid)

bys firmyear_id: egen double s1_final_firm_total = total(emi_s1_final)
gen double s1_final_minus_ngms = s1_final_firm_total - emission_ngms ///
    if !missing(emission_ngms)
gen byte s1_firm_total_cons = ///
    (abs(s1_final_minus_ngms) <= 1e-6 * max(1, abs(emission_ngms))) ///
    if !missing(s1_final_minus_ngms)

label var s1_energy_sha_ok "Complete positive within-firm energy share for scope 1 filling"
label var pred_s1_energy_sha "Energy-based predicted scope 1 allocation share over all establishments"
label var pred_s1_sha_resid "Energy-based predicted scope 1 allocation share among missing establishments"
label var s1_obs_subtotal "Observed ENV scope 1 subtotal in the firm-year"
label var s1_resid_raw "NGMS scope 1 total minus observed ENV scope 1 subtotal"
label var s1_resid_alloc "Positive scope 1 residual allocated to missing establishments"
label var s1_actual_gt_firm "1 if observed ENV scope 1 subtotal exceeds NGMS total"
label var emi_s1_est "Residual-anchored energy estimate for missing scope 1 emissions"
label var emi_s1_final "Final scope 1 emissions: actual if observed, else residual energy estimate"
label var emi_s1_is_est "1 if final scope 1 emission is estimated; 0 if actual"
label var emi_s1_source "Final scope 1 emission source"
label var s1_est_base "Scope 1 final estimator allocation base"
label var s1_est_tier "Scope 1 final estimator correction tier"
label var s1_unfill_reason "Reason scope 1 final emission remains missing"
label var s1_final_firm_total "Firm-year sum of final scope 1 establishment emissions"
label var s1_final_minus_ngms "Final scope 1 firm-year total minus NGMS total"
label var s1_firm_total_cons "1 if final scope 1 firm-year total equals NGMS total within tolerance"

keep firm_id firmyear_id estab_id firm_name est_name address year sgg_code K_ft ///
    emission_ngms est_emission_scope1 actual_sum_env n_env_scope1 sampleA sampleB ///
    share_energy s1_energy_sha_ok pred_s1_energy_sha ///
    pred_s1_sha_resid s1_obs_subtotal ///
    s1_resid_raw s1_resid_alloc ///
    s1_actual_gt_firm ///
    emi_s1_est emi_s1_final emi_s1_is_est ///
    emi_s1_source s1_est_base s1_est_tier ///
    s1_unfill_reason s1_final_firm_total s1_final_minus_ngms ///
    s1_firm_total_cons
compress
save "${out}/results/method_v3_scope1_completed_estab_emissions.dta", replace

* 5. Validation figures.
capture program drop method_v4_plot_panels
program define method_v4_plot_panels
    syntax using/, ACTUALSHARE(name) PREDSHARE(name) ACTUALEMIS(name) PREDEMIS(name) ///
        SHAREXTITLE(string) SHAREYTITLE(string) EMISXTITLE(string) EMISYTITLE(string) ///
        OUTSTUB(string) PREFIX(name)

    use "`using'", clear

    tempvar plot_actual_share plot_pred_share plot_actual_emis plot_pred_emis ///
        plot_ln_actual_emis plot_ln_pred_emis
    gen double `plot_actual_share' = `actualshare'
    gen double `plot_pred_share' = `predshare'
    gen double `plot_actual_emis' = `actualemis'
    gen double `plot_pred_emis' = `predemis'
    gen double `plot_ln_actual_emis' = ln(`plot_actual_emis') if `plot_actual_emis' > 0
    gen double `plot_ln_pred_emis' = ln(`plot_pred_emis') if `plot_pred_emis' > 0

    quietly count if !missing(`plot_actual_share', `plot_pred_share')
    if r(N) == 0 {
        display as error "No nonmissing share pairs for `outstub'"
        exit 2000
    }

    quietly summarize `plot_actual_share' if !missing(`plot_actual_share', `plot_pred_share'), meanonly
    local share_hi = r(max)
    quietly summarize `plot_pred_share' if !missing(`plot_actual_share', `plot_pred_share'), meanonly
    local share_hi = max(`share_hi', r(max))
    local share_max = `share_hi'
    local share_hi = `share_hi' * 1.05
    if `share_hi' <= 0 local share_hi = 0.1
    local share_step = cond(`share_hi' > .5, .10, .05)
    local share_hi = ceil(`share_hi' / `share_step') * `share_step'
    if `share_max' <= 1 & `share_hi' > 1 local share_hi = 1

    quietly count if !missing(`plot_ln_actual_emis', `plot_ln_pred_emis')
    if r(N) == 0 {
        display as error "No positive emission pairs for `outstub'"
        exit 2000
    }

    quietly summarize `plot_ln_actual_emis' if !missing(`plot_ln_actual_emis', `plot_ln_pred_emis'), meanonly
    local emis_lo = r(min)
    local emis_hi = r(max)
    quietly summarize `plot_ln_pred_emis' if !missing(`plot_ln_actual_emis', `plot_ln_pred_emis'), meanonly
    local emis_lo = min(`emis_lo', r(min))
    local emis_hi = max(`emis_hi', r(max))
    local emis_pad = (`emis_hi' - `emis_lo') * 0.04
    if `emis_pad' <= 0 local emis_pad = 0.1
    local emis_lo = floor((`emis_lo' - `emis_pad') / 2) * 2
    local emis_hi = ceil((`emis_hi' + `emis_pad') / 2) * 2

    foreach b in employee revenue energy {
        local color = cond("`b'" == "employee", "navy%38", cond("`b'" == "revenue", "maroon%38", "forest_green%38"))
        local label = cond("`b'" == "employee", "Employee", cond("`b'" == "revenue", "Revenue", "Energy"))

        twoway ///
            (scatter `plot_pred_share' `plot_actual_share' if base == "`b'" & !missing(`plot_actual_share', `plot_pred_share'), ///
                msymbol(oh) msize(vsmall) mcolor(`color')) ///
            (function y=x, range(0 `share_hi') lcolor(black) lpattern(solid) lwidth(medthin)), ///
            xtitle("`sharextitle'", size(vsmall)) ///
            ytitle("`shareytitle'", size(vsmall)) ///
            xlabel(, labsize(vsmall) grid glcolor(gs14)) ///
            ylabel(, labsize(vsmall) angle(horizontal) grid glcolor(gs14)) ///
            xscale(range(0 `share_hi')) yscale(range(0 `share_hi')) aspectratio(1) ///
            legend(off) graphregion(color(white)) plotregion(color(white)) ///
            name(`prefix'_share_`b', replace)
        graph export "`outstub'_sha_`b'.png", replace width(1200)

        twoway ///
            (scatter `plot_ln_pred_emis' `plot_ln_actual_emis' if base == "`b'" & !missing(`plot_ln_actual_emis', `plot_ln_pred_emis'), ///
                msymbol(oh) msize(vsmall) mcolor(`color')) ///
            (function y=x, range(`emis_lo' `emis_hi') lcolor(black) lpattern(solid) lwidth(medthin)), ///
            xtitle("`emisxtitle'", size(vsmall)) ///
            ytitle("`emisytitle'", size(vsmall)) ///
            xlabel(, labsize(vsmall) grid glcolor(gs14)) ///
            ylabel(, labsize(vsmall) angle(horizontal) grid glcolor(gs14)) ///
            xscale(range(`emis_lo' `emis_hi')) yscale(range(`emis_lo' `emis_hi')) aspectratio(1) ///
            legend(off) graphregion(color(white)) plotregion(color(white)) ///
            name(`prefix'_emis_`b', replace)
        graph export "`outstub'_emi_`b'.png", replace width(1200)
    }

    graph drop `prefix'_share_employee `prefix'_share_revenue `prefix'_share_energy ///
        `prefix'_emis_employee `prefix'_emis_revenue `prefix'_emis_energy
end

method_v4_plot_panels using "${out}/results/method_v3_log_by_estab.dta", ///
    actualshare(actual_alloc_share) predshare(pred_alloc_share_bc) ///
    actualemis(actual_emis) predemis(pred_emis_bc) ///
    sharextitle("Actual allocation share") ///
    shareytitle("Predicted allocation share") ///
    emisxtitle("Log actual Scope 1 total emissions") ///
    emisytitle("Log predicted Scope 1 total emissions") ///
    outstub("${out}/figures/valid_s1_estab") ///
    prefix(s1_el)

method_v4_plot_panels using "${out}/results/method_v3_log_by_sigungu.dta", ///
    actualshare(actual_spatial_share) predshare(pred_spatial_share_bc) ///
    actualemis(actual_emis) predemis(pred_emis_bc) ///
    sharextitle("Actual county share") ///
    shareytitle("Predicted county share") ///
    emisxtitle("Log actual Scope 1 total emissions") ///
    emisytitle("Log predicted Scope 1 total emissions") ///
    outstub("${out}/figures/valid_s1_county") ///
    prefix(s1_cl)

display as text "Log-share cell-mean outputs written to ${out}"
