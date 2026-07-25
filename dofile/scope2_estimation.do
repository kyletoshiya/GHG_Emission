

clear all

global data = "${main}/data"
global out = "${main}/out"

local mincell 25
local total_folds 5
local bases "employee revenue energy"
tempfile analysis_base validation_all firmyear_totals

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
bys firmyear_id: egen actual_sum_env = total(est_emission_scope2) // scope 2 emission, firm-level 
bys firmyear_id: egen n_env_scope2 = count(est_emission_scope2)

* Sample A: complete observed ENV scope 2 firm-years.
gen byte sampleA = (n_env_scope2 == K_ft & actual_sum_env > 0)
gen byte sampleB = (!sampleA)

gen double actual_share = est_emission_scope2 / actual_sum_env if sampleA
gen double actual_emis_env = est_emission_scope2 if sampleA

label var actual_share "ENV scope 2 within-firm allocation share"
label var actual_emis_env "Observed ENV establishment scope 2 emissions"
label var actual_sum_env "Observed ENV firm-year scope 2 total"
label var sampleA "Complete observed ENV scope 2 firm-year with positive total"
label var sampleB "Non-Sample-A firm-year for scope 2 share prediction"


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

* 2. Estimate reported ENV scope 2 firm-year totals.

preserve
    keep firm_id firmyear_id year ind1 k_class K_ft sampleA actual_sum_env ///
        emission_ngms total_employee_valid total_revenue_valid total_energy_valid
    bys firmyear_id: keep if _n == 1
    rename total_employee_valid firm_total_employee
    rename total_revenue_valid firm_total_revenue
    rename total_energy_valid firm_total_energy

    gen double actual_s2_total_obs = actual_sum_env if sampleA
    gen byte total_train = sampleA & actual_s2_total_obs > 0
    gen double ln_s2_total_obs = ln(actual_s2_total_obs) if total_train

    gen double ln_firm_employee = ln(firm_total_employee) if firm_total_employee > 0
    gen double ln_firm_revenue = ln(firm_total_revenue) if firm_total_revenue > 0
    gen double ln_firm_energy = ln(firm_total_energy) if firm_total_energy > 0
    gen double ln_emission_ngms = ln(emission_ngms) if emission_ngms > 0
    encode ind1, gen(ind1_id)

    gen byte total_fold = mod(firm_id, `total_folds') + 1
    local total_model_name_1 "log_linear"

    forvalues m = 1/1 {
        gen double ln_cv_m`m' = .
        gen double pred_cv_m`m' = .
        gen double ln_full_m`m' = .
        gen double pred_full_m`m' = .
    }

    forvalues f = 1/`total_folds' {
        quietly regress ln_s2_total_obs ///
            c.ln_firm_employee c.ln_firm_revenue c.ln_firm_energy c.ln_emission_ngms ///
            i.year i.ind1_id i.k_class ///
            if total_train & total_fold != `f'

        tempvar xb_fold
        predict double `xb_fold' if total_fold == `f', xb
        replace ln_cv_m1 = `xb_fold' if total_fold == `f' & !missing(`xb_fold')
        replace pred_cv_m1 = exp(ln_cv_m1) if total_fold == `f' & !missing(ln_cv_m1)
        drop `xb_fold'
    }

    quietly regress ln_s2_total_obs ///
        c.ln_firm_employee c.ln_firm_revenue c.ln_firm_energy c.ln_emission_ngms ///
        i.year i.ind1_id i.k_class ///
        if total_train

    tempvar xb_full
    predict double `xb_full', xb
    replace ln_full_m1 = `xb_full' if !missing(`xb_full')
    replace pred_full_m1 = exp(ln_full_m1) if !missing(ln_full_m1)
    drop `xb_full'

    tempfile firmyear_stage1
    save `firmyear_stage1', replace

    tempfile total_model_metrics
    clear
    set obs 0
    gen byte model_id = .
    gen str32 total_model = ""
    gen byte selected_total_model = .
    gen N_firm_year = .
    gen double MAE_total_cv = .
    gen double MSE_total_cv = .
    gen double RMSE_total_cv = .
    gen double MAE_ln_total_cv = .
    gen double MSE_ln_total_cv = .
    gen double RMSE_ln_total_cv = .
    gen double MAPE_total_cv = .
    save `total_model_metrics', emptyok replace

    forvalues m = 1/1 {
        use `firmyear_stage1', clear
        keep if total_train & actual_s2_total_obs > 0 & pred_cv_m`m' > 0
        gen double err_total_cv = pred_cv_m`m' - actual_s2_total_obs
        gen double err_ln_total_cv = ln_cv_m`m' - ln_s2_total_obs
        gen double abs_total_cv = abs(err_total_cv)
        gen double sq_total_cv = err_total_cv^2
        gen double abs_ln_total_cv = abs(err_ln_total_cv)
        gen double sq_ln_total_cv = err_ln_total_cv^2
        gen double ape_total_cv = abs_total_cv / actual_s2_total_obs
        gen one = 1
        collapse ///
            (count) N_firm_year=one ///
            (mean) MAE_total_cv=abs_total_cv MSE_total_cv=sq_total_cv ///
                   MAE_ln_total_cv=abs_ln_total_cv MSE_ln_total_cv=sq_ln_total_cv ///
                   MAPE_total_cv=ape_total_cv
        gen RMSE_total_cv = sqrt(MSE_total_cv)
        gen RMSE_ln_total_cv = sqrt(MSE_ln_total_cv)
        gen byte model_id = `m'
        gen str32 total_model = "`total_model_name_`m''"
        gen byte selected_total_model = 0
        keep model_id total_model selected_total_model N_firm_year ///
            MAE_total_cv MSE_total_cv RMSE_total_cv ///
            MAE_ln_total_cv MSE_ln_total_cv RMSE_ln_total_cv MAPE_total_cv
        append using `total_model_metrics'
        save `total_model_metrics', replace
    }

    use `total_model_metrics', clear
    gsort MAE_ln_total_cv MAE_total_cv model_id
    replace selected_total_model = (_n == 1)
    local selected_total_model_id = model_id[1]
    local selected_total_model_name = total_model[1]
    save "${out}/results/method_v3_scope2_total_model_comparison.dta", replace
    keep if selected_total_model
    save "${out}/results/method_v3_scope2_total_metrics.dta", replace

    use `firmyear_stage1', clear
    gen byte selected_total_model_id = `selected_total_model_id'
    gen str32 selected_total_model = "`selected_total_model_name'"
    gen double ln_pred_s2_total_cv = ln_cv_m`selected_total_model_id'
    gen double pred_s2_total_cv = pred_cv_m`selected_total_model_id'
    gen double ln_pred_s2_total_full = ln_full_m`selected_total_model_id'
    gen double pred_s2_total_full = pred_full_m`selected_total_model_id'

    xtile pred_s2_total_q_cv = pred_s2_total_cv ///
        if total_train & pred_s2_total_cv > 0, nq(4)
    replace pred_s2_total_q_cv = 0 if missing(pred_s2_total_q_cv)
    xtile pred_s2_total_q_full = pred_s2_total_full ///
        if pred_s2_total_full > 0, nq(4)
    replace pred_s2_total_q_full = 0 if missing(pred_s2_total_q_full)

    label var actual_s2_total_obs "Observed reported ENV scope 2 firm-year total"
    label var pred_s2_total_cv "Cross-fitted predicted reported scope 2 firm-year total"
    label var pred_s2_total_full "Full-sample predicted reported scope 2 firm-year total"
    label var pred_s2_total_q_cv "CV predicted scope 2 firm-total quartile"
    label var pred_s2_total_q_full "Full-sample predicted scope 2 firm-total quartile"
    label var selected_total_model "Selected firm-year scope 2 total estimator"

    save "${out}/results/method_v3_scope2_total_predictions.dta", replace
    keep firmyear_id actual_s2_total_obs total_train total_fold ///
        selected_total_model_id selected_total_model ///
        pred_s2_total_cv ln_pred_s2_total_cv pred_s2_total_q_cv ///
        pred_s2_total_full ln_pred_s2_total_full pred_s2_total_q_full
    save `firmyear_totals', replace
restore

merge m:1 firmyear_id using `firmyear_totals', nogen keep(master match)

egen cell3_cv = group(ind1 k_class pred_s2_total_q_cv), missing
egen cell3_full = group(ind1 k_class pred_s2_total_q_full), missing
label var cell3_cv "1-digit industry x K class x CV predicted scope 2 total quartile"
label var cell3_full "1-digit industry x K class x full predicted scope 2 total quartile"

save `analysis_base', replace
save "${out}/results/method_v3_scope2_log_analysis_dataset.dta", replace

* 3. Leave-one-firm-out validation.

clear
save `validation_all', emptyok replace

foreach b of local bases {
    use `analysis_base', clear

    gen double log_bias = ln(share_`b') - ln(actual_share) ///
        if sampleA & share_`b' > 0 & actual_share > 0
    label var log_bias "log(`b' share) - log(actual ENV scope 2 allocation share)"

    preserve
    keep if !missing(log_bias)
    bys cell3_cv: egen double sum_cell = total(log_bias)
    bys cell3_cv: egen N_cell = count(log_bias)
    bys cell3_cv firm_id: egen double sum_firm_cell = total(log_bias)
    bys cell3_cv firm_id: egen N_firm_cell = count(log_bias)
    keep cell3_cv firm_id sum_cell N_cell sum_firm_cell N_firm_cell
    duplicates drop
    gen N_excl = N_cell - N_firm_cell
    gen double mu_loo = (sum_cell - sum_firm_cell) / N_excl if N_excl >= `mincell'
    gen str8 selected_tier = "cell3" if !missing(mu_loo)
    gen N_train_cell = N_excl if !missing(mu_loo)
    keep cell3_cv firm_id mu_loo selected_tier N_train_cell
    tempfile loo_cell3
    save `loo_cell3', replace
    restore

    merge m:1 cell3_cv firm_id using `loo_cell3', nogen keep(master match)

    keep if eval_common & share_`b' > 0 & actual_share > 0 ///
        & pred_s2_total_cv > 0 & !missing(mu_loo)

    gen double base_share = share_`b'
    gen double pred_share_bc_raw = exp(ln(base_share) - mu_loo)
    bys firmyear_id: egen double pred_share_bc_total = total(pred_share_bc_raw)
    gen double pred_share_bc = pred_share_bc_raw / pred_share_bc_total ///
        if pred_share_bc_total > 0
    gen double pred_emis_bc = pred_s2_total_cv * pred_share_bc
    gen double pred_emis_cond_bc = actual_sum_env * pred_share_bc

    gen double err_share_bc = pred_share_bc - actual_share
    gen double err_emis_bc = pred_emis_bc - actual_emis_env
    gen double err_emis_cond_bc = pred_emis_cond_bc - actual_emis_env
    gen double ln_actual_emis = ln(actual_emis_env)
    gen double ln_pred_emis_bc = ln(pred_emis_bc)
    gen double err_ln_emis_bc = ln_pred_emis_bc - ln_actual_emis
    gen double ln_pred_emis_cond_bc = ln(pred_emis_cond_bc)
    gen double err_ln_emis_cond_bc = ln_pred_emis_cond_bc - ln_actual_emis

    foreach v in share emis ln_emis emis_cond ln_emis_cond {
        gen double abs_`v'_bc = abs(err_`v'_bc)
        gen double sq_`v'_bc = err_`v'_bc^2
    }

    gen str8 base = "`b'"
    gen byte base_order = cond(base == "employee", 1, cond(base == "revenue", 2, 3))

    keep base_order base firm_id firmyear_id estab_id firm_name est_name ///
        address year sgg_code K_ft emission_ngms actual_sum_env actual_s2_total_obs ///
        selected_total_model_id selected_total_model ///
        pred_s2_total_cv pred_s2_total_full actual_share actual_emis_env ///
        base_share pred_share_bc_raw pred_share_bc pred_emis_bc pred_emis_cond_bc ///
        mu_loo selected_tier N_train_cell ln_actual_emis ln_pred_emis_bc ///
        ln_pred_emis_cond_bc ///
        err_* abs_* sq_*

    append using `validation_all'
    save `validation_all', replace
}

use `validation_all', clear
compress
save "${out}/results/method_v3_scope2_log_validation_predictions.dta", replace

* Cell-support diagnostics.
use "${out}/results/method_v3_scope2_log_validation_predictions.dta", clear
gen byte tier_order = 1
gen str90 tier_label = "1-digit industry x K class x predicted scope 2 total quartile"

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
save "${out}/results/method_v3_scope2_log_cell_support.dta", replace

* 4. Performance metrics.

* (1) Establishment-year.
use "${out}/results/method_v3_scope2_log_validation_predictions.dta", clear
gen one = 1
collapse ///
    (count) N_estab_year=one ///
    (mean) MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc ///
           MAE_emis_cond_bc=abs_emis_cond_bc MSE_emis_cond_bc=sq_emis_cond_bc ///
           MAE_ln_emis_bc=abs_ln_emis_bc MSE_ln_emis_bc=sq_ln_emis_bc ///
           MAE_ln_emis_cond_bc=abs_ln_emis_cond_bc MSE_ln_emis_cond_bc=sq_ln_emis_cond_bc ///
           MAE_share_bc=abs_share_bc MSE_share_bc=sq_share_bc, ///
    by(base_order base)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
gen RMSE_emis_cond_bc = sqrt(MSE_emis_cond_bc)
gen RMSE_ln_emis_bc = sqrt(MSE_ln_emis_bc)
gen RMSE_ln_emis_cond_bc = sqrt(MSE_ln_emis_cond_bc)
gen RMSE_share_bc = sqrt(MSE_share_bc)
sort base_order
save "${out}/results/method_v3_scope2_log_metrics_estab_year.dta", replace

* (2) County-year.
use "${out}/results/method_v3_scope2_log_validation_predictions.dta", clear
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
save "${out}/results/method_v3_scope2_log_by_sigungu_year.dta", replace

collapse ///
    (count) N_sigungu_year=actual_emis ///
    (mean) MAE_spatial_share_bc=abs_spatial_share_bc MSE_spatial_share_bc=sq_spatial_share_bc ///
           MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc, ///
    by(base_order base)
gen RMSE_spatial_share_bc = sqrt(MSE_spatial_share_bc)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
sort base_order
save "${out}/results/method_v3_scope2_log_metrics_sigungu_year.dta", replace

* (3) Establishment-level.
use "${out}/results/method_v3_scope2_log_validation_predictions.dta", clear
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
save "${out}/results/method_v3_scope2_log_by_estab.dta", replace

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
save "${out}/results/method_v3_scope2_log_metrics_estab.dta", replace

* (4) County-level.
use "${out}/results/method_v3_scope2_log_by_sigungu_year.dta", clear
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
save "${out}/results/method_v3_scope2_log_by_sigungu.dta", replace

gen one = 1
collapse ///
    (count) N_sigungu=one ///
    (mean) MAE_spatial_share_bc=abs_spatial_share_bc MSE_spatial_share_bc=sq_spatial_share_bc ///
           MAE_emis_bc=abs_emis_bc MSE_emis_bc=sq_emis_bc, ///
    by(base_order base)
gen RMSE_spatial_share_bc = sqrt(MSE_spatial_share_bc)
gen RMSE_emis_bc = sqrt(MSE_emis_bc)
sort base_order
save "${out}/results/method_v3_scope2_log_metrics_sigungu.dta", replace

* 5. Fill missing scope 2 emissions.

use `analysis_base', clear

gen double s2_log_bias_energy = ln(share_energy) - ln(actual_share) ///
    if sampleA & share_energy > 0 & actual_share > 0
quietly summarize s2_log_bias_energy, meanonly
local s2_global_mu_energy = r(mean)

preserve
keep if !missing(s2_log_bias_energy)
bys cell3_full: egen double sum_cell = total(s2_log_bias_energy)
bys cell3_full: egen N_cell = count(s2_log_bias_energy)
keep cell3_full sum_cell N_cell
duplicates drop
gen double s2_mu_energy_cell = sum_cell / N_cell if N_cell >= `mincell'
gen N_train_cell_energy = N_cell if !missing(s2_mu_energy_cell)
keep cell3_full s2_mu_energy_cell N_train_cell_energy
tempfile s2_energy_cell
save `s2_energy_cell', replace
restore

merge m:1 cell3_full using `s2_energy_cell', nogen keep(master match)

gen byte s2_energy_sha_ok = n_positive_energy == K_ft ///
    & share_energy > 0
gen double s2_mu_energy = s2_mu_energy_cell
replace s2_mu_energy = `s2_global_mu_energy' ///
    if s2_energy_sha_ok & missing(s2_mu_energy) ///
    & !missing(`s2_global_mu_energy')

gen str8 s2_est_base = ""
replace s2_est_base = "energy" ///
    if s2_energy_sha_ok & !missing(s2_mu_energy)

gen str8 s2_est_tier = ""
replace s2_est_tier = "cell3" ///
    if s2_energy_sha_ok & !missing(s2_mu_energy_cell)
replace s2_est_tier = "global" ///
    if s2_energy_sha_ok & missing(s2_mu_energy_cell) ///
    & !missing(s2_mu_energy)

gen double pred_s2_energy_sha_raw = exp(ln(share_energy) - s2_mu_energy) ///
    if s2_energy_sha_ok & !missing(s2_mu_energy)
bys firmyear_id: egen double pred_s2_energy_sha_tot = total(pred_s2_energy_sha_raw)
gen double pred_s2_energy_sha = pred_s2_energy_sha_raw ///
    / pred_s2_energy_sha_tot if pred_s2_energy_sha_tot > 0

* Actual-first residual allocation.
gen byte s2_missing_estab = missing(est_emission_scope2)
gen double s2_obs_subtotal = actual_sum_env
gen double s2_resid_raw = pred_s2_total_full - s2_obs_subtotal ///
    if !missing(pred_s2_total_full)
gen byte s2_actual_gt_pred = ///
    (s2_obs_subtotal > pred_s2_total_full) ///
    if !missing(pred_s2_total_full)
gen double s2_resid_alloc = s2_resid_raw
replace s2_resid_alloc = 0 ///
    if s2_resid_alloc < 0 ///
    & !missing(s2_resid_alloc)

gen double pred_s2_sha_miss_raw = pred_s2_energy_sha_raw ///
    if s2_missing_estab
bys firmyear_id: egen double pred_s2_sha_miss_tot = ///
    total(pred_s2_sha_miss_raw)
gen double pred_s2_sha_resid = pred_s2_energy_sha_raw ///
    / pred_s2_sha_miss_tot ///
    if s2_missing_estab & pred_s2_sha_miss_tot > 0

gen double emi_s2_est = ///
    s2_resid_alloc * pred_s2_sha_resid ///
    if s2_missing_estab ///
    & !missing(s2_resid_alloc) ///
    & !missing(pred_s2_sha_resid)

gen double emi_s2_final = est_emission_scope2
replace emi_s2_final = emi_s2_est ///
    if missing(emi_s2_final)

gen byte emi_s2_is_est = .
replace emi_s2_is_est = 0 if !missing(est_emission_scope2)
replace emi_s2_is_est = 1 if missing(est_emission_scope2) ///
    & !missing(emi_s2_est)

gen str10 emi_s2_source = ""
replace emi_s2_source = "actual" if emi_s2_is_est == 0
replace emi_s2_source = "estimated" if emi_s2_is_est == 1
replace emi_s2_source = "unfilled" if missing(emi_s2_final)

gen str40 s2_unfill_reason = ""
replace s2_unfill_reason = "no_energy_sha" ///
    if missing(est_emission_scope2) & missing(emi_s2_est) ///
    & !s2_energy_sha_ok
replace s2_unfill_reason = "no_mu" ///
    if missing(est_emission_scope2) & missing(emi_s2_est) ///
    & s2_energy_sha_ok & missing(s2_mu_energy)
replace s2_unfill_reason = "no_s2_total" ///
    if missing(est_emission_scope2) & missing(emi_s2_est) ///
    & missing(pred_s2_total_full)
replace s2_unfill_reason = "no_resid_sha" ///
    if missing(est_emission_scope2) & missing(emi_s2_est) ///
    & !missing(pred_s2_total_full) & s2_energy_sha_ok ///
    & !missing(s2_mu_energy) ///
    & missing(pred_s2_sha_resid)

bys firmyear_id: egen double s2_final_firm_total = total(emi_s2_final)
gen double s2_final_minus_pred = s2_final_firm_total - pred_s2_total_full ///
    if !missing(pred_s2_total_full)
gen byte s2_firm_total_cons = ///
    (abs(s2_final_minus_pred) <= 1e-6 * max(1, abs(pred_s2_total_full))) ///
    if !missing(s2_final_minus_pred)

label var s2_energy_sha_ok "Complete positive within-firm energy share for scope 2 filling"
label var pred_s2_energy_sha "Energy-based predicted scope 2 allocation share over all establishments"
label var pred_s2_sha_resid "Energy-based predicted scope 2 allocation share among missing establishments"
label var s2_obs_subtotal "Observed ENV scope 2 subtotal in the firm-year"
label var s2_resid_raw "Predicted scope 2 total minus observed ENV scope 2 subtotal"
label var s2_resid_alloc "Positive scope 2 residual allocated to missing establishments"
label var s2_actual_gt_pred "1 if observed ENV scope 2 subtotal exceeds predicted total"
label var emi_s2_est "Residual-anchored energy estimate for missing scope 2 emissions"
label var emi_s2_final "Final scope 2 emissions: actual if observed, else residual energy estimate"
label var emi_s2_is_est "1 if final scope 2 emission is estimated; 0 if actual"
label var emi_s2_source "Final scope 2 emission source"
label var s2_est_base "Scope 2 final estimator allocation base"
label var s2_est_tier "Scope 2 final estimator correction tier"
label var s2_unfill_reason "Reason scope 2 final emission remains missing"
label var s2_final_firm_total "Firm-year sum of final scope 2 establishment emissions"
label var s2_final_minus_pred "Final scope 2 firm-year total minus predicted total"
label var s2_firm_total_cons "1 if final scope 2 firm-year total equals predicted total within tolerance"

keep firm_id firmyear_id estab_id firm_name est_name address year sgg_code K_ft ///
    emission_ngms est_emission_scope2 actual_sum_env n_env_scope2 sampleA sampleB ///
    selected_total_model_id selected_total_model pred_s2_total_full ///
    share_energy s2_energy_sha_ok pred_s2_energy_sha ///
    pred_s2_sha_resid s2_obs_subtotal ///
    s2_resid_raw s2_resid_alloc ///
    s2_actual_gt_pred ///
    emi_s2_est emi_s2_final emi_s2_is_est ///
    emi_s2_source s2_est_base s2_est_tier ///
    s2_unfill_reason s2_final_firm_total s2_final_minus_pred ///
    s2_firm_total_cons
compress
save "${out}/results/method_v3_scope2_completed_estab_emissions.dta", replace

* 6. Validation figures.
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

method_v4_plot_panels using "${out}/results/method_v3_scope2_log_by_estab.dta", ///
    actualshare(actual_alloc_share) predshare(pred_alloc_share_bc) ///
    actualemis(actual_emis) predemis(pred_emis_bc) ///
    sharextitle("Actual allocation share") ///
    shareytitle("Predicted allocation share") ///
    emisxtitle("Log actual Scope 2 total emissions") ///
    emisytitle("Log predicted Scope 2 total emissions") ///
    outstub("${out}/figures/valid_s2_estab") ///
    prefix(s2_el)

method_v4_plot_panels using "${out}/results/method_v3_scope2_log_by_sigungu.dta", ///
    actualshare(actual_spatial_share) predshare(pred_spatial_share_bc) ///
    actualemis(actual_emis) predemis(pred_emis_bc) ///
    sharextitle("Actual county share") ///
    shareytitle("Predicted county share") ///
    emisxtitle("Log actual Scope 2 total emissions") ///
    emisytitle("Log predicted Scope 2 total emissions") ///
    outstub("${out}/figures/valid_s2_county") ///
    prefix(s2_cl)

display as text "Log-share cell-mean outputs written to ${out}"
