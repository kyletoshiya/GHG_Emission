/*
programs_estimate_missing.do  --  expected-emissions residual allocation (defines `allocate_joint`).

Reported ENV-Info establishment values are kept. For every missing establishment-scope cell an
expected emission is formed as (predicted scope intensity, tCO2eq per TJ) x (establishment energy):
  tier 1  own history   : median scope intensity over the establishment's `nn' nearest reporting
                          years, bounded to [lo, hi] x the firm-level fallback intensity;
  tier 2  firm fallback : phi_ft x c_ft for scope 1 and (1 - phi_ft) x c_ft for scope 2, where phi_ft is
                          the firm-year scope 1 share from 1a (4-step rule) and c_ft the emission
                          intensity of the firm's establishments reporting both scopes (same year,
                          else all years, else the global median).
The unreported residual R_ft = max(NGMS_ft - reported scope 1 - reported scope 2, 0) is allocated
to the missing cells of the firm-year in proportion to expected emissions, so that final
establishment values add up to the NGMS total whenever every missing cell can be estimated.
The firm-year ratio R_ft / sum of expected emissions is kept as a consistency diagnostic
(flagged outside [1/3, 3]); the unreconciled expected values are released alongside.

method(energy) uses tier 2 for every missing cell (energy-share allocation within the firm's
scope composition) and serves as the comparison method.

Validation (complete-reporting firm-years, all three bases positive) holds the observed ENV firm-year
scope total fixed and compares employee, revenue, energy and expected-emission (leave-one-year-out
own history) shares with observed shares; metrics for all firm-years, firm-years with 2+ establishments,
firm-years spanning 2+ counties, firm-years in which every establishment has own history, and by year.

Inputs : ${data}/NGMS_ENV_ready_2026_09_13.dta, ${out}/results/firm_year_ngms_s1_s2.dta
Outputs: ${out}/results/<tag>_completed_estab_emissions.dta, <tag>_firm_year.dta,
         <tag>_s<g>_metrics_*.dta, <tag>_s<g>_validation_predictions.dta, figures validation_s<g>_*.png
Options: method(expected|energy) nn(3) lo(0.3333) hi(3) bgap(0) bmin(0) tag(estimates) novalidation
         The bound is applied to an own-history intensity when the nearest own report is more than
         bgap years away or fewer than bmin own years are available (defaults 0/0: always applied).
Globals: data, out (paths); skip_figures = 1 suppresses figure export.
*/

capture program drop allocate_joint
program define allocate_joint
    syntax , [METHod(string) NN(integer 3) LO(real 0.3333333333) HI(real 3) BGAP(integer 0) BMIN(integer 0) TAG(string) NOVALidation]
    if "`method'" == "" local method "expected"
    if !inlist("`method'", "expected", "energy") {
        display as error "method() must be expected or energy"
        exit 198
    }
    if "`tag'" == "" local tag "estimates"
    local R "${out}/results"
    tempfile base hist own

    * ------------------------------------------------------------------ 1. analysis file
    use "${data}/NGMS_ENV_ready_2026_09_13.dta", clear
    merge m:1 firm_name year using "`R'/firm_year_ngms_s1_s2.dta", ///
        assert(match) nogenerate keepusing(phi phi_source phi_conflict NGMS_S1 NGMS_S2)
    egen firm_id     = group(firm_name), missing label
    egen estab_id    = group(firm_name est_name), missing label
    egen firmyear_id = group(firm_id year), missing label
    isid firm_id estab_id year
    bys firmyear_id: gen K_ft = _N
    bys firmyear_id sigungu_code: gen byte first_cty = _n == 1
    bys firmyear_id: egen n_county = total(first_cty)
    drop first_cty
    gen double e1 = est_emission_scope1
    gen double e2 = est_emission_scope2
    gen byte rep1 = !missing(e1)
    gen byte rep2 = !missing(e2)
    gen byte energy_ok = energy > 0 & !missing(energy)
    gen double I1 = e1 / energy if rep1 & energy_ok
    gen double I2 = e2 / energy if rep2 & energy_ok
    label var I1 "Reported scope 1 intensity (tCO2eq/TJ)"
    label var I2 "Reported scope 2 intensity (tCO2eq/TJ)"

    * ------------------------------------------------------------------ 2. tier 1: own history for missing cells
    preserve
        keep if (rep1 | rep2) & energy_ok
        keep estab_id year I1 I2
        rename year yr
        save `hist', replace
    restore
    preserve
        keep if !rep1 | !rep2
        keep estab_id year
        joinby estab_id using `hist', unmatched(master)
        gen d = abs(year - yr)
        foreach g in 1 2 {
            gen double dd`g' = cond(I`g' != ., d + 0.001 * (yr > year), .)
            bys estab_id year (dd`g'): gen rk`g' = _n if I`g' != .
            gen double sel`g' = I`g' if rk`g' <= `nn'
            gen double gp`g'  = d if rk`g' == 1
            gen byte   ct`g'  = rk`g' <= `nn'
        }
        collapse (median) own_I1 = sel1 own_I2 = sel2 (min) own_gap1 = gp1 own_gap2 = gp2 ///
                 (sum) own_n1 = ct1 own_n2 = ct2, by(estab_id year)
        save `own', replace
    restore
    merge m:1 estab_id year using `own', keep(master match) nogenerate
    foreach g in 1 2 {
        replace own_n`g' = . if own_I`g' == .
        label var own_I`g'   "Own-history scope `g' intensity (median of `nn' nearest reporting years)"
        label var own_gap`g' "Years to the nearest own scope `g' report"
        label var own_n`g'   "Number of own reporting years used"
    }

    * ------------------------------------------------------------------ 3. tier 2: firm-level fallback intensity
    gen byte both_rep = rep1 & rep2 & energy_ok
    bys firmyear_id: egen double fy_E = total(cond(both_rep, e1 + e2, 0))
    bys firmyear_id: egen double fy_U = total(cond(both_rep, energy, 0))
    bys firm_id: egen double f_E = total(cond(both_rep, e1 + e2, 0))
    bys firm_id: egen double f_U = total(cond(both_rep, energy, 0))
    gen double Ik = (e1 + e2) / energy if both_rep
    quietly summarize Ik, detail
    local Iglob = r(p50)
    gen double Ik1 = e1 / energy if both_rep
    quietly summarize Ik1, detail
    local Iglob1 = r(p50)
    gen double Ik2 = e2 / energy if both_rep
    quietly summarize Ik2, detail
    local Iglob2 = r(p50)
    drop Ik1 Ik2
    gen double c_fy = fy_E / fy_U if fy_U > 0
    gen byte   c_src = 1 if c_fy != .
    replace c_src = 2 if c_fy == . & f_U > 0
    replace c_fy = f_E / f_U if c_fy == . & f_U > 0
    replace c_src = 3 if c_fy == .
    replace c_fy = `Iglob' if c_fy == .
    gen double t2_I1 = phi * c_fy
    gen double t2_I2 = (1 - phi) * c_fy
    label var c_fy  "Firm-level emission intensity of establishments reporting both scopes (tCO2eq/TJ)"
    label var c_src "Source of c_fy: 1 same firm-year, 2 firm all years, 3 global median"
    label var t2_I1 "Firm-fallback scope 1 intensity: phi x c_fy"
    label var t2_I2 "Firm-fallback scope 2 intensity: (1 - phi) x c_fy"
    drop fy_E fy_U f_E f_U Ik

    * ------------------------------------------------------------------ 4. expected emissions of missing cells
    foreach g in 1 2 {
        gen byte miss`g' = !rep`g'
        gen byte own_avail`g' = own_I`g' != . if miss`g'
        gen double own_Ib`g' = own_I`g'
        gen byte do_bound`g' = (own_gap`g' > `bgap' | own_n`g' < `bmin') if own_I`g' != .
        replace own_Ib`g' = min(max(own_I`g', `lo' * t2_I`g'), `hi' * t2_I`g') if own_I`g' != . & t2_I`g' > 0 & t2_I`g' != . & do_bound`g'
        drop do_bound`g'
        gen byte own_clipped`g' = (abs(own_Ib`g' - own_I`g') > 1e-9) if own_I`g' != .
        gen double I_use`g' = .
        gen byte tier`g' = .
        if "`method'" == "expected" {
            replace I_use`g' = own_Ib`g' if miss`g' & own_I`g' != .
            replace tier`g' = 1 if miss`g' & own_I`g' != .
        }
        replace I_use`g' = t2_I`g' if miss`g' & I_use`g' == .
        replace tier`g' = 2 if miss`g' & tier`g' == .
        gen double expct`g' = I_use`g' * energy if miss`g' & energy_ok
        label var own_Ib`g'      "Own-history scope `g' intensity bounded to [`lo', `hi'] x firm fallback"
        label var own_clipped`g' "1 if the own-history intensity was bounded"
        label var tier`g'        "Expected-emission tier for missing scope `g': 1 own history, 2 firm fallback"
        label var expct`g'       "Expected scope `g' emissions of a missing cell (intensity x energy)"
    }

    * ------------------------------------------------------------------ 5. residual allocation
    bys firmyear_id: egen double Y1 = total(cond(rep1, e1, 0))
    bys firmyear_id: egen double Y2 = total(cond(rep2, e2, 0))
    gen double R = max(emission_ngms - Y1 - Y2, 0)
    bys firmyear_id: egen double W = total(cond(miss1 & expct1 != ., expct1, 0) + cond(miss2 & expct2 != ., expct2, 0))
    bys firmyear_id: egen n_miss_cells = total(miss1 + miss2)
    bys firmyear_id: egen n_est_cells  = total((miss1 & expct1 != .) + (miss2 & expct2 != .))
    gen double ratio = R / W if W > 0
    gen byte ratio_flag = (ratio < 1/3 | ratio > 3) if ratio != .
    label var Y1 "Reported ENV scope 1 subtotal of the firm-year"
    label var Y2 "Reported ENV scope 2 subtotal of the firm-year"
    label var R  "Unreported residual: max(NGMS total - reported subtotals, 0)"
    label var W  "Sum of expected emissions over estimable missing cells"
    label var ratio "R / W: consistency of the NGMS residual with expected emissions"
    label var ratio_flag "1 if ratio outside [1/3, 3]"
    foreach g in 1 2 {
        gen double emi_est`g' = R * expct`g' / W if miss`g' & expct`g' != . & W > 0
        replace emi_est`g' = . if miss`g' & phi_conflict == 1 & R == 0
        gen double emi_final`g' = e`g'
        replace emi_final`g' = emi_est`g' if miss`g'
        gen str14 src`g' = "reported" if rep`g'
        replace src`g' = "own_history"   if miss`g' & emi_est`g' != . & tier`g' == 1 & R > 0
        replace src`g' = "firm_fallback" if miss`g' & emi_est`g' != . & tier`g' == 2 & R > 0
        replace src`g' = "zero_residual" if miss`g' & emi_est`g' != . & R == 0
        replace src`g' = "unfilled"      if miss`g' & emi_est`g' == .
        gen str14 unfill`g' = ""
        replace unfill`g' = "no_energy"    if src`g' == "unfilled" & !energy_ok
        replace unfill`g' = "inconsistent" if src`g' == "unfilled" & energy_ok & phi_conflict == 1 & R == 0
        replace unfill`g' = "other"        if src`g' == "unfilled" & unfill`g' == ""
        gen byte is_est`g' = cond(rep`g', 0, cond(emi_est`g' != ., 1, .))
        label var emi_est`g'   "Estimated scope `g' emissions (residual x expected share)"
        label var emi_final`g' "Final scope `g' emissions: reported if available, else estimated"
        label var src`g'       "Source of final scope `g' value"
        label var unfill`g'    "Reason a missing scope `g' cell is unfilled"
        label var is_est`g'    "0 reported, 1 estimated, missing unfilled"
    }
    bys firmyear_id: egen double S1f = total(emi_final1)
    bys firmyear_id: egen double S2f = total(emi_final2)
    bys firmyear_id: egen n_unfilled = total((src1 == "unfilled") + (src2 == "unfilled"))
    gen double fy_target = max(emission_ngms, Y1 + Y2)
    gen byte fy_cons = abs(S1f + S2f - fy_target) <= 1e-6 * fy_target
    label var S1f "Final firm-year scope 1 total (sum of establishment values)"
    label var S2f "Final firm-year scope 2 total (sum of establishment values)"
    label var fy_cons "1 if final scope 1 + scope 2 equal max(NGMS, reported subtotals)"
    label var n_unfilled "Number of unfilled cells in the firm-year"

    * rename scope-specific variables with s1_/s2_ prefixes
    foreach g in 1 2 {
        foreach v in e rep I own_I own_gap own_n own_avail own_Ib own_clipped t2_I miss I_use tier expct emi_est emi_final src unfill is_est {
            rename `v'`g' s`g'_`v'
        }
        rename Y`g' s`g'_Y
        rename S`g'f s`g'_final_fy
    }
    gen str8 method = "`method'"
    save `base', replace
    keep firm_id firmyear_id estab_id firm_name est_name year sigungu_code industry K_ft n_county energy energy_ok ///
         emission_ngms NGMS_S1 NGMS_S2 phi phi_source phi_conflict c_fy c_src R W ratio ratio_flag n_miss_cells n_est_cells n_unfilled fy_target fy_cons method s1_* s2_*
    compress
    save "`R'/`tag'_completed_estab_emissions.dta", replace
    bys firmyear_id: keep if _n == 1
    keep firm_id firmyear_id firm_name year K_ft n_county emission_ngms phi phi_source phi_conflict c_fy c_src ///
         s1_Y s2_Y R W ratio ratio_flag n_miss_cells n_est_cells n_unfilled s1_final_fy s2_final_fy fy_target fy_cons method
    save "`R'/`tag'_firm_year.dta", replace

    if "`novalidation'" != "" {
        display as text "`tag' (`method'): allocation complete, validation skipped."
        exit
    }

    * ------------------------------------------------------------------ 6. validation of the allocation key
    foreach g in 1 2 {
        local stub "`tag'_s`g'"
        use `base', clear
        bys firmyear_id: egen double actual_sum_env = total(s`g'_e)
        bys firmyear_id: egen n_env = count(s`g'_e)
        gen byte sampleA = (n_env == K_ft & actual_sum_env > 0)
        gen double actual_share    = s`g'_e / actual_sum_env if sampleA
        gen double actual_emis_env = s`g'_e if sampleA
        foreach b in employee revenue energy {
            gen double value_`b' = `b'
            replace value_`b' = . if value_`b' < 0
            bys firmyear_id: egen double total_`b'_valid = total(value_`b')
            gen double share_`b' = value_`b' / total_`b'_valid if total_`b'_valid > 0 & !missing(value_`b')
            gen byte positive_`b' = (share_`b' > 0 & !missing(share_`b'))
            bys firmyear_id: egen n_positive_`b' = total(positive_`b')
        }
        gen byte actual_positive = (actual_share > 0 & !missing(actual_share))
        bys firmyear_id: egen n_actual_positive = total(actual_positive)
        gen byte eval_common = sampleA & n_positive_employee == K_ft & n_positive_revenue == K_ft ///
            & n_positive_energy == K_ft & n_actual_positive == K_ft
        keep if eval_common
        * leave-one-year-out own history and leave-one-cell-out firm fallback
        preserve
            keep estab_id year
            joinby estab_id using `hist', unmatched(master)
            gen d = abs(year - yr)
            drop if d == 0
            gen double dd = cond(I`g' != ., d + 0.001 * (yr > year), .)
            bys estab_id year (dd): gen rk = _n if I`g' != .
            gen double sel = I`g' if rk <= `nn'
            gen byte ct = rk <= `nn'
            gen double gp = d if rk == 1
            collapse (median) loo_own = sel (sum) loo_n = ct (min) loo_gap = gp, by(estab_id year)
            replace loo_n = . if loo_own == .
            tempfile loo
            save `loo', replace
        restore
        merge m:1 estab_id year using `loo', keep(master match) nogenerate
        * leak-free firm fallback: scope-g intensity of the firm's other establishments reporting both scopes
        * (same year, else the firm's other years, else the global median); for complete-reporting firm-years this
        * equals phi x c computed without the cell
        gen byte bothpos = s1_rep & s2_rep & energy_ok
        bys firmyear_id: egen double fyEg = total(cond(bothpos, s`g'_e, 0))
        bys firmyear_id: egen double fyU = total(cond(bothpos, energy, 0))
        bys firm_id: egen double fEg = total(cond(bothpos, s`g'_e, 0))
        bys firm_id: egen double fU = total(cond(bothpos, energy, 0))
        gen double own_cell_E = cond(bothpos, s`g'_e, 0)
        gen double own_cell_U = cond(bothpos, energy, 0)
        gen double t2_loo = (fyEg - own_cell_E) / (fyU - own_cell_U) if (fyU - own_cell_U) > 0
        replace t2_loo = (fEg - own_cell_E) / (fU - own_cell_U) if t2_loo == . & (fU - own_cell_U) > 0
        replace t2_loo = `Iglob`g'' if t2_loo == .
        gen double I_loo = loo_own
        replace I_loo = min(max(loo_own, `lo' * t2_loo), `hi' * t2_loo) if loo_own != . & t2_loo > 0 & (loo_gap > `bgap' | loo_n < `bmin')
        gen byte has_own = loo_own != .
        replace I_loo = t2_loo if I_loo == .
        gen double value_expected = I_loo * energy
        bys firmyear_id: egen double total_expected_valid = total(value_expected)
        gen double share_expected = value_expected / total_expected_valid if total_expected_valid > 0
        bys firmyear_id: egen n_has_own = total(has_own)
        gen byte allown = n_has_own == K_ft
        quietly count
        local n_eval = r(N)
        quietly count if has_own
        display as text "Scope `g' validation sample: `n_eval' establishment-years, " r(N) " with own history"
        tempfile vbase
        save `vbase', replace

        clear
        tempfile validation_all
        save `validation_all', emptyok replace
        foreach b in employee revenue energy expected {
            use `vbase', clear
            gen double pred_share = share_`b'
            gen double pred_emis  = actual_sum_env * pred_share
            gen double err_share  = pred_share - actual_share
            gen double err_emis   = pred_emis - actual_emis_env
            gen double ln_actual_emis = ln(actual_emis_env)
            gen double ln_pred_emis   = ln(pred_emis)
            gen double err_ln_emis    = ln_pred_emis - ln_actual_emis
            foreach v in share emis ln_emis {
                gen double abs_`v' = abs(err_`v')
                gen double sq_`v'  = err_`v'^2
            }
            gen str8 base = "`b'"
            gen byte base_order = cond(base == "employee", 1, cond(base == "revenue", 2, cond(base == "energy", 3, 4)))
            keep base_order base firm_id firmyear_id estab_id firm_name est_name year sigungu_code K_ft n_county allown has_own ///
                actual_sum_env actual_share actual_emis_env pred_share pred_emis ln_actual_emis ln_pred_emis err_* abs_* sq_*
            append using `validation_all'
            save `validation_all', replace
        }
        use `validation_all', clear
        compress
        save "`R'/`stub'_validation_predictions.dta", replace

        * (1) establishment-year metrics
        gen one = 1
        gen byte multi = K_ft >= 2
        gen byte multicounty = n_county >= 2
        foreach s in all multi multicounty allown {
            preserve
                if "`s'" != "all" keep if `s'
                collapse (count) N_estab_year=one (mean) MAE_share=abs_share MSE_share=sq_share ///
                    MAE_emis=abs_emis MSE_emis=sq_emis MAE_ln_emis=abs_ln_emis MSE_ln_emis=sq_ln_emis, by(base_order base)
                gen RMSE_share = sqrt(MSE_share)
                gen RMSE_emis = sqrt(MSE_emis)
                gen RMSE_ln_emis = sqrt(MSE_ln_emis)
                gen str12 sample = "`s'"
                sort base_order
                save "`R'/`stub'_metrics_estab_year_`s'.dta", replace
            restore
        }
        * (2) county-year metrics
        use "`R'/`stub'_validation_predictions.dta", clear
        keep if !missing(sigungu_code)
        gen byte multicounty = n_county >= 2
        foreach s in all multicounty {
            preserve
                if "`s'" != "all" keep if `s'
                gen one = 1
                collapse (sum) actual_emis=actual_emis_env pred_emis (count) n_estab_year=one, by(base_order base year sigungu_code)
                bys base_order base year: egen double actual_year_total = total(actual_emis)
                bys base_order base year: egen double pred_year_total = total(pred_emis)
                gen double actual_spatial_share = actual_emis / actual_year_total if actual_year_total > 0
                gen double pred_spatial_share   = pred_emis / pred_year_total if pred_year_total > 0
                gen double err_emis = pred_emis - actual_emis
                gen double err_spatial_share = pred_spatial_share - actual_spatial_share
                gen double abs_emis = abs(err_emis)
                gen double sq_emis = err_emis^2
                gen double abs_spatial_share = abs(err_spatial_share)
                gen double sq_spatial_share = err_spatial_share^2
                if "`s'" == "all" save "`R'/`stub'_by_sigungu_year.dta", replace
                collapse (count) N_sigungu_year=actual_emis (mean) MAE_spatial_share=abs_spatial_share MSE_spatial_share=sq_spatial_share ///
                    MAE_emis=abs_emis MSE_emis=sq_emis, by(base_order base)
                gen RMSE_spatial_share = sqrt(MSE_spatial_share)
                gen RMSE_emis = sqrt(MSE_emis)
                gen str12 sample = "`s'"
                sort base_order
                save "`R'/`stub'_metrics_sigungu_year_`s'.dta", replace
            restore
        }
        use "`R'/`stub'_by_sigungu_year.dta", clear
        keep if inlist(base, "energy", "expected")
        collapse (count) N_sigungu_year=actual_emis (mean) MAE_spatial_share=abs_spatial_share MAE_emis=abs_emis, by(base_order base year)
        save "`R'/`stub'_metrics_sigungu_by_year.dta", replace
        * (3) establishment level, pooled years
        use "`R'/`stub'_validation_predictions.dta", clear
        gen one = 1
        collapse (sum) actual_emis=actual_emis_env pred_emis (count) n_estab_year=one, ///
            by(base_order base firm_id estab_id firm_name est_name sigungu_code)
        bys base_order base firm_id: egen double actual_firm_total = total(actual_emis)
        bys base_order base firm_id: egen double pred_firm_total = total(pred_emis)
        bys base_order base firm_id: gen n_estab_firm = _N
        gen double actual_alloc_share = actual_emis / actual_firm_total if actual_firm_total > 0
        gen double pred_alloc_share   = pred_emis / pred_firm_total if pred_firm_total > 0
        gen double ln_actual_emis = ln(actual_emis)
        gen double ln_pred_emis   = ln(pred_emis)
        gen double err_emis = pred_emis - actual_emis
        gen double err_alloc_share = pred_alloc_share - actual_alloc_share
        gen double err_ln_emis = ln_pred_emis - ln_actual_emis
        gen double abs_emis = abs(err_emis)
        gen double sq_emis = err_emis^2
        gen double abs_alloc_share = abs(err_alloc_share)
        gen double sq_alloc_share = err_alloc_share^2
        gen double abs_ln_emis = abs(err_ln_emis)
        gen double sq_ln_emis = err_ln_emis^2
        save "`R'/`stub'_by_estab.dta", replace
        foreach s in all multi {
            preserve
                if "`s'" == "multi" keep if n_estab_firm >= 2
                gen one = 1
                collapse (count) N_estab=one (mean) MAE_emis=abs_emis MSE_emis=sq_emis ///
                    MAE_alloc_share=abs_alloc_share MSE_alloc_share=sq_alloc_share MAE_ln_emis=abs_ln_emis MSE_ln_emis=sq_ln_emis, by(base_order base)
                gen RMSE_emis = sqrt(MSE_emis)
                gen RMSE_alloc_share = sqrt(MSE_alloc_share)
                gen RMSE_ln_emis = sqrt(MSE_ln_emis)
                gen str12 sample = "`s'"
                sort base_order
                save "`R'/`stub'_metrics_estab_`s'.dta", replace
            restore
        }
        * (4) county level, pooled years
        use "`R'/`stub'_by_sigungu_year.dta", clear
        collapse (sum) actual_emis pred_emis (count) n_sigungu_year=year, by(base_order base sigungu_code)
        bys base_order base: egen double actual_total = total(actual_emis)
        bys base_order base: egen double pred_total = total(pred_emis)
        gen double actual_spatial_share = actual_emis / actual_total if actual_total > 0
        gen double pred_spatial_share   = pred_emis / pred_total if pred_total > 0
        gen double err_emis = pred_emis - actual_emis
        gen double err_spatial_share = pred_spatial_share - actual_spatial_share
        gen double abs_emis = abs(err_emis)
        gen double sq_emis = err_emis^2
        gen double abs_spatial_share = abs(err_spatial_share)
        gen double sq_spatial_share = err_spatial_share^2
        save "`R'/`stub'_by_sigungu.dta", replace
        gen one = 1
        collapse (count) N_sigungu=one (mean) MAE_spatial_share=abs_spatial_share MSE_spatial_share=sq_spatial_share ///
            MAE_emis=abs_emis MSE_emis=sq_emis, by(base_order base)
        gen RMSE_spatial_share = sqrt(MSE_spatial_share)
        gen RMSE_emis = sqrt(MSE_emis)
        sort base_order
        save "`R'/`stub'_metrics_sigungu.dta", replace

        * (5) figures
        if "${skip_figures}" != "1" {
            plot_validation_panels using "`R'/`stub'_by_estab.dta", ///
                actualshare(actual_alloc_share) predshare(pred_alloc_share) actualemis(actual_emis) predemis(pred_emis) ///
                sharextitle("Actual allocation share") shareytitle("Predicted allocation share") ///
                emisxtitle("Log actual Scope `g' total emissions") emisytitle("Log predicted Scope `g' total emissions") ///
                outstub("${out}/figures/validation_s`g'_estab") prefix(s`g'_el)
            plot_validation_panels using "`R'/`stub'_by_sigungu.dta", ///
                actualshare(actual_spatial_share) predshare(pred_spatial_share) actualemis(actual_emis) predemis(pred_emis) ///
                sharextitle("Actual county share") shareytitle("Predicted county share") ///
                emisxtitle("Log actual Scope `g' total emissions") emisytitle("Log predicted Scope `g' total emissions") ///
                outstub("${out}/figures/validation_s`g'_county") prefix(s`g'_cl)
        }
    }
    display as text "`tag' (`method'): allocation and validation complete."
end

capture program drop plot_validation_panels
program define plot_validation_panels
    syntax using/, ACTUALSHARE(name) PREDSHARE(name) ACTUALEMIS(name) PREDEMIS(name) ///
        SHAREXTITLE(string) SHAREYTITLE(string) EMISXTITLE(string) EMISYTITLE(string) OUTSTUB(string) PREFIX(name)
    use "`using'", clear
    tempvar pas pps pae ppe lae lpe
    gen double `pas' = `actualshare'
    gen double `pps' = `predshare'
    gen double `pae' = `actualemis'
    gen double `ppe' = `predemis'
    gen double `lae' = ln(`pae') if `pae' > 0
    gen double `lpe' = ln(`ppe') if `ppe' > 0
    quietly summarize `pas' if !missing(`pas', `pps'), meanonly
    local share_hi = r(max)
    quietly summarize `pps' if !missing(`pas', `pps'), meanonly
    local share_hi = max(`share_hi', r(max))
    local share_max = `share_hi'
    local share_hi = `share_hi' * 1.05
    if `share_hi' <= 0 local share_hi = 0.1
    local share_step = cond(`share_hi' > .5, .10, .05)
    local share_hi = ceil(`share_hi' / `share_step') * `share_step'
    if `share_max' <= 1 & `share_hi' > 1 local share_hi = 1
    quietly summarize `lae' if !missing(`lae', `lpe'), meanonly
    local emis_lo = r(min)
    local emis_hi = r(max)
    quietly summarize `lpe' if !missing(`lae', `lpe'), meanonly
    local emis_lo = min(`emis_lo', r(min))
    local emis_hi = max(`emis_hi', r(max))
    local emis_pad = (`emis_hi' - `emis_lo') * 0.04
    if `emis_pad' <= 0 local emis_pad = 0.1
    local emis_lo = floor((`emis_lo' - `emis_pad') / 2) * 2
    local emis_hi = ceil((`emis_hi' + `emis_pad') / 2) * 2
    foreach b in employee revenue energy expected {
        local color = cond("`b'" == "employee", "navy%38", cond("`b'" == "revenue", "maroon%38", cond("`b'" == "energy", "forest_green%38", "dkorange%38")))
        twoway (scatter `pps' `pas' if base == "`b'" & !missing(`pas', `pps'), msymbol(oh) msize(vsmall) mcolor(`color')) ///
               (function y=x, range(0 `share_hi') lcolor(black) lwidth(medthin)), ///
            xtitle("`sharextitle'", size(vsmall)) ytitle("`shareytitle'", size(vsmall)) ///
            xlabel(, labsize(vsmall) grid glcolor(gs14)) ylabel(, labsize(vsmall) angle(horizontal) grid glcolor(gs14)) ///
            xscale(range(0 `share_hi')) yscale(range(0 `share_hi')) aspectratio(1) legend(off) ///
            graphregion(color(white)) plotregion(color(white)) name(`prefix'_share_`b', replace)
        graph export "`outstub'_sha_`b'.png", replace width(1200)
        twoway (scatter `lpe' `lae' if base == "`b'" & !missing(`lae', `lpe'), msymbol(oh) msize(vsmall) mcolor(`color')) ///
               (function y=x, range(`emis_lo' `emis_hi') lcolor(black) lwidth(medthin)), ///
            xtitle("`emisxtitle'", size(vsmall)) ytitle("`emisytitle'", size(vsmall)) ///
            xlabel(, labsize(vsmall) grid glcolor(gs14)) ylabel(, labsize(vsmall) angle(horizontal) grid glcolor(gs14)) ///
            xscale(range(`emis_lo' `emis_hi')) yscale(range(`emis_lo' `emis_hi')) aspectratio(1) legend(off) ///
            graphregion(color(white)) plotregion(color(white)) name(`prefix'_emis_`b', replace)
        graph export "`outstub'_emi_`b'.png", replace width(1200)
    }
    graph drop _all
end
