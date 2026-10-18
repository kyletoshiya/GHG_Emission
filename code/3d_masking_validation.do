/*
3d_masking_validation.do -- end-to-end validation by artificial missingness (run after 2).

Truth set: step-1 firm-years of the unmasked 1a run (every establishment reports both scopes and the reported
total lies within 15% of the NGMS total) with at least two establishments. Scenarios:
  random     : both scopes hidden for a random 30% of establishment-years (at least one kept per firm-year)
  small      : both scopes hidden for establishment-years below the firm-year median energy
  nonmanuf   : both scopes hidden for non-manufacturing establishments of firm-years with both types
  scope1only : scope 1 hidden for a random 30% of establishment-years
  neverrep   : both scopes hidden in every year for a random 25% of the establishments of truth firms
               (never-reporting establishments; at least one establishment kept per truth firm-year)
For each scenario the whole procedure (1a decomposition and allocate_joint with the expected-emissions key and
with the energy key) is re-run on the masked copy with the actual NGMS totals (mode C) and, to isolate the
effect of the NGMS-ENV total gap, with the complete ENV total in place of the NGMS total for truth firm-years
(mode B). Mode A takes the true hidden scope totals as given and distributes them with each key.
Metrics over hidden cells with energy > 0, by scope: share MAE (|estimate - true| / firm-year total S1+S2),
scope-share MAE (/ firm-year scope total), median APE, median signed relative error, share of over-predictions,
county-year spatial-share MAE and the mean over years of half the L1 distance between true and estimated county
distributions of the affected firm-years; counts of hidden cells with own history, unfilled, without energy,
true zeros; hidden emission shares. The random scenario is replicated with 10 seeds (mode C).

Cell-level metrics use a common evaluation sample across variants (hidden cells with energy that the released
procedure estimates); results are also stratified by the distance to the nearest own report, restricted to firm-years
spanning two or more counties, and extended to year-to-year changes (establishments hidden in consecutive years;
county-year changes and first-to-last-year differences of county totals over a fixed cohort of firms affected in both years).
Outputs: output/results/masking_results.dta, masking_by_gap.dta, masking_replications.dta; scratch runs under output/masking/<scenario>[_B]/
Parameters of allocate_joint come from globals p_nn p_lo p_hi p_bgap p_bmin (defaults 3, 0.2, 5, 2, 3).
*/
version 17
clear all
set more off
if "${path}" == "" {
    global path "`c(pwd)'"
    capture confirm file "${path}/data/NGMS_ENV_ready_2026_09_13.dta"
    if _rc {
        global path "`c(pwd)'/.."
    }
}
local data_main "${path}/data"
local out_main  "${path}/output"
local R "`out_main'/results"
local M "`out_main'/masking"
if "${p_nn}"   == "" global p_nn   3
if "${p_lo}"   == "" global p_lo   0.2
if "${p_hi}"   == "" global p_hi   5
if "${p_bgap}" == "" global p_bgap 2
if "${p_bmin}" == "" global p_bmin 3
cap mkdir "`M'"

* ---------------------------------------------------------------- truth set (unmasked 1a output)
use "`R'/firm_year_ngms_s1_s2.dta", clear
keep if phi_source == 1 & K >= 2
keep firm_name year
save "`M'/truth_fy.dta", replace

* ---------------------------------------------------------------- part 1: build masked copies and run the procedure
local scenarios "random small nonmanuf scope1only neverrep"
local reps 10
local runs "`scenarios'"
forvalues i = 1/`reps' {
    local runs "`runs' rep`i'"
}
foreach s of local runs {
    local seed 20261006
    local kind "`s'"
    if substr("`s'", 1, 3) == "rep" {
        local seed = 20261006 + real(substr("`s'", 4, .))
        local kind "random"
    }
    set seed `seed'
    use "`data_main'/NGMS_ENV_ready_2026_09_13.dta", clear
    merge m:1 firm_name year using "`M'/truth_fy.dta", keep(master match)
    gen byte truth = _merge == 3
    drop _merge
    egen estab_id = group(firm_name est_name)
    egen fy_id = group(firm_name year)
    gen double true_s1 = est_emission_scope1
    gen double true_s2 = est_emission_scope2
    gen byte manuf = industry == "제조업"
    bys fy_id: egen double med_energy = median(energy)
    bys fy_id: egen n_manuf = total(manuf)
    bys fy_id: egen n_nonmanuf = total(1 - manuf)
    sort firm_name est_name year
    gen double u = runiform()
    bys fy_id (u): gen byte rank_u = _n
    gen byte hide1 = 0
    gen byte hide2 = 0
    if "`kind'" == "random" {
        replace hide1 = truth & u < 0.30 & rank_u > 1
        replace hide2 = hide1
    }
    if "`kind'" == "small" {
        replace hide1 = truth & energy < med_energy
        replace hide2 = hide1
    }
    if "`kind'" == "nonmanuf" {
        replace hide1 = truth & n_manuf >= 1 & n_nonmanuf >= 1 & manuf == 0
        replace hide2 = hide1
    }
    if "`kind'" == "scope1only" {
        replace hide1 = truth & u < 0.30 & rank_u > 1
    }
    if "`kind'" == "neverrep" {
        gen double ue = u
        bys estab_id (year): replace ue = ue[1]
        bys estab_id: egen byte in_truth = max(truth)
        bys fy_id: egen double ue_min = min(cond(truth, ue, .))
        gen byte protect = truth & ue == ue_min
        bys estab_id: egen byte prot_any = max(protect)
        replace hide1 = in_truth & ue < 0.25 & !prot_any
        replace hide2 = hide1
        drop ue in_truth ue_min protect prot_any
    }
    * ENV complete total of truth firm-years (mode B replaces the NGMS total with it)
    gen double tt = true_s1 + true_s2
    bys fy_id: egen double T_env = total(tt)
    save "`M'/work_`s'.dta", replace
    foreach mode in C B {
        if "`mode'" == "B" & substr("`s'", 1, 3) == "rep" continue
        use "`M'/work_`s'.dta", clear
        local mdir = cond("`mode'" == "C", "`M'/`s'", "`M'/`s'_B")
        cap mkdir "`mdir'"
        cap mkdir "`mdir'/data"
        cap mkdir "`mdir'/results"
        preserve
            keep firm_name est_name year hide1 hide2 true_s1 true_s2 truth
            save "`mdir'/hidden.dta", replace
        restore
        preserve
            if "`mode'" == "B" {
                recast double emission_ngms
                replace emission_ngms = T_env if truth
            }
            replace est_emission_scope1 = . if hide1
            replace est_emission_scope2 = . if hide2
            drop truth estab_id fy_id true_s1 true_s2 manuf med_energy n_manuf n_nonmanuf u rank_u hide1 hide2 tt T_env
            save "`mdir'/data/NGMS_ENV_ready_2026_09_13.dta", replace
        restore
        global data "`mdir'/data"
        global out  "`mdir'"
        global skip_figures 1
        quietly do "${path}/code/1a_firm_decomp_s1_s2.do"
        quietly do "${path}/code/programs_estimate_missing.do"
        quietly allocate_joint, method(expected) nn(${p_nn}) lo(${p_lo}) hi(${p_hi}) bgap(${p_bgap}) bmin(${p_bmin}) tag(estimates) novalidation
        quietly allocate_joint, method(energy) tag(estimates_energy) novalidation
        global data ""
        global out  ""
        global skip_figures ""
        display as text "masking run complete: `mdir'"
    }
    capture erase "`M'/work_`s'.dta"
}

* ---------------------------------------------------------------- part 2: evaluation
capture program drop eval_mask
program define eval_mask
    syntax , SCEN(string) MODE(string) METHod(string) G(integer) RUNdir(string) CDIR(string) HIDden(string) [POSTto(name) GAPto(name)]
    if "`postto'" == "" local postto res
    local tag = cond("`method'" == "expected", "estimates", "estimates_energy")
    tempfile cfile
    use "`cdir'/results/`tag'_completed_estab_emissions.dta", clear
    keep firm_name est_name year s`g'_emi_final
    rename s`g'_emi_final c_est
    save `cfile', replace
    use "`rundir'/results/`tag'_completed_estab_emissions.dta", clear
    keep firm_name est_name year firmyear_id firm_id estab_id sigungu_code n_county energy energy_ok s`g'_emi_final s`g'_expct s`g'_tier s`g'_own_gap
    merge 1:1 firm_name est_name year using `cfile', assert(match) nogenerate
    merge 1:1 firm_name est_name year using "`hidden'", assert(match) nogenerate
    keep if truth
    quietly summarize true_s`g', meanonly
    local truth_tot = r(sum)
    gen byte hid = hide`g'
    bys firmyear_id: egen byte aff = max(hid)
    keep if aff
    bys firmyear_id: egen double F1 = total(true_s1)
    bys firmyear_id: egen double F2 = total(true_s2)
    gen double Ftot = F1 + F2
    bys firmyear_id: egen double H = total(cond(hid, true_s`g', 0))
    gen double imp = s`g'_emi_final if hid
    if "`mode'" == "A" {
        bys firmyear_id: egen double Wh = total(cond(hid & s`g'_expct != ., s`g'_expct, 0))
        replace imp = H * s`g'_expct / Wh if hid & Wh > 0
        replace imp = . if hid & (s`g'_expct == . | Wh <= 0)
    }
    gen double tv = true_s`g'
    * common evaluation sample: hidden cells with energy that the released procedure (mode C) estimates
    gen byte ev = hid & energy_ok & c_est != .
    gen double e_tot = abs(imp - tv) / Ftot if ev
    gen double e_sc  = abs(imp - tv) / F`g' if ev
    gen double ape   = abs(imp - tv) / tv if ev & tv > 0
    gen double sre   = (imp - tv) / tv if ev & tv > 0
    gen byte   over  = imp > tv if ev & tv > 0 & imp != .
    quietly count if hid & energy_ok
    local nh = r(N)
    quietly count if ev
    local nev = r(N)
    bys firmyear_id: gen byte first = _n == 1
    quietly count if first
    local nfy = r(N)
    quietly count if ev & s`g'_tier == 1
    local nown = r(N)
    quietly count if hid & energy_ok & c_est == .
    local nunf = r(N)
    quietly count if hid & !energy_ok
    local nnoen = r(N)
    quietly count if hid & tv == 0
    local nzero = r(N)
    quietly summarize tv if hid, meanonly
    local hsum = r(sum)
    quietly summarize tv if hid & !ev, meanonly
    local excl_share = cond(`hsum' > 0, r(sum) / `hsum', 0)
    quietly summarize tv, meanonly
    local hid_aff = `hsum' / r(sum)
    local hid_all = `hsum' / `truth_tot'
    quietly summarize e_tot, meanonly
    local m_tot = r(mean)
    quietly summarize e_sc, meanonly
    local m_sc = r(mean)
    quietly summarize ape, detail
    local p_ape = r(p50)
    quietly summarize sre, detail
    local p_sre = r(p50)
    quietly summarize over, meanonly
    local p_over = r(mean)
    quietly summarize e_sc if n_county >= 2, meanonly
    local m_sc_mc = r(mean)
    quietly count if ev & n_county >= 2
    local nev_mc = r(N)
    * by distance to the nearest own report (expected key, released procedure)
    if "`gapto'" != "" & "`method'" == "expected" & "`mode'" == "C" {
        gen byte gapc = cond(s`g'_own_gap == ., 4, cond(s`g'_own_gap <= 1, 1, cond(s`g'_own_gap <= 3, 2, 3))) if ev
        forvalues c = 1/4 {
            quietly count if ev & gapc == `c'
            local ng = r(N)
            if `ng' == 0 continue
            quietly summarize e_sc if gapc == `c', meanonly
            local gm = r(mean)
            quietly summarize ape if gapc == `c', detail
            local ga = r(p50)
            quietly summarize sre if gapc == `c', detail
            local gs = r(p50)
            post `gapto' ("`scen'") (`g') (`c') (`ng') (`gm') (`ga') (`gs')
        }
    }
    * establishment-level year-to-year changes: hidden cells whose establishment is also hidden in the previous year
    preserve
        keep if ev
        keep estab_id year tv imp Ftot
        sort estab_id year
        by estab_id: gen double d_true = tv - tv[_n-1] if _n > 1 & year == year[_n-1] + 1
        by estab_id: gen double d_est  = imp - imp[_n-1] if _n > 1 & year == year[_n-1] + 1
        gen double e_chg = abs(d_est - d_true) / Ftot if d_true != . & d_est != .
        gen byte s_chg = sign(d_est) == sign(d_true) if d_true != 0 & d_true != . & d_est != .
        quietly count if e_chg != .
        local n_chg = r(N)
        quietly summarize e_chg, meanonly
        local chg_mae = r(mean)
        quietly summarize s_chg, meanonly
        local chg_sign = r(mean)
    restore
    * county-year level (all establishments of the affected firm-years; unfilled hidden cells count as zero)
    gen double fin = cond(hid, cond(missing(imp), 0, imp), tv)
    * county-year changes and first-to-last-year differences on a fixed cohort: establishments of firms that are
    * affected (have hidden cells) in both years compared, so that entry and exit of firm-years do not enter the changes
    preserve
        keep firm_id year sigungu_code tv fin
        tempfile rows
        save `rows', replace
        keep firm_id year
        duplicates drop
        tempfile affy
        save `affy', replace
        quietly summarize year
        local ymin = r(min)
        local ymax = r(max)
        tempfile chg
        clear
        set obs 0
        gen double da = .
        gen double dp = .
        gen byte long_diff = .
        save `chg', replace
        local pairs ""
        forvalues t = `=`ymin'+1'/`ymax' {
            local pairs "`pairs' `=`t'-1',`t',0"
        }
        local pairs "`pairs' `ymin',`ymax',1"
        foreach pr of local pairs {
            tokenize "`pr'", parse(",")
            local t0 `1'
            local t1 `3'
            local ld `5'
            use `affy', clear
            keep if year == `t0' | year == `t1'
            bys firm_id: gen n = _N
            keep if n == 2
            keep firm_id
            duplicates drop
            quietly count
            if r(N) == 0 continue
            merge 1:m firm_id using `rows', keep(match) nogenerate
            keep if year == `t0' | year == `t1'
            collapse (sum) a = tv p = fin, by(sigungu_code year)
            reshape wide a p, i(sigungu_code) j(year)
            foreach v in a`t0' a`t1' p`t0' p`t1' {
                capture confirm variable `v'
                if _rc gen double `v' = 0
                replace `v' = 0 if missing(`v')
            }
            gen double da = a`t1' - a`t0'
            gen double dp = p`t1' - p`t0'
            gen byte long_diff = `ld'
            keep da dp long_diff
            append using `chg'
            save `chg', replace
        }
        use `chg', clear
        gen double ad_abs = abs(da)
        gen double dd_abs = abs(dp - da)
        gen byte dsign = sign(dp) == sign(da) if da != 0
        gen byte dpos = da > 0 if da != 0
        foreach ld in 0 1 {
            quietly summarize dd_abs if long_diff == `ld', meanonly
            local sdd = r(sum)
            quietly summarize ad_abs if long_diff == `ld', meanonly
            local rel`ld' = cond(r(sum) > 0, `sdd' / r(sum), .)
            quietly summarize dsign if long_diff == `ld', meanonly
            local sgn`ld' = r(mean)
            quietly summarize dpos if long_diff == `ld', meanonly
            local pos`ld' = r(mean)
            quietly count if long_diff == `ld' & (da != 0 | dp != 0)
            local n`ld' = r(N)
        }
        local n_cchg = `n0'
        local cchg_rel = `rel0'
        local cchg_sign = `sgn0'
        local cchg_pos = `pos0'
        local n_long = `n1'
        local long_rel = `rel1'
        local long_sign = `sgn1'
    restore
    preserve
        keep if n_county >= 2
        quietly count
        if r(N) > 0 {
            collapse (sum) a = tv p = fin, by(year sigungu_code)
            bys year: egen double at = total(a)
            bys year: egen double pt = total(p)
            gen double ce = abs(p / pt - a / at)
            collapse (sum) ce, by(year)
            quietly summarize ce, meanonly
            local l1_mc = r(mean) / 2
        }
        else local l1_mc = .
    restore
    collapse (sum) a = tv p = fin nh = hid, by(year sigungu_code)
    bys year: egen double at = total(a)
    bys year: egen double pt = total(p)
    gen double ce = abs(p / pt - a / at)
    gen double rel = abs(p - a) / a if a > 0 & nh > 0
    quietly summarize ce, meanonly
    local cm = r(mean)
    quietly summarize rel, detail
    local rel50 = r(p50)
    local rel90 = r(p90)
    quietly count if rel != .
    local ncy_h = r(N)
    collapse (sum) ce, by(year)
    gen double l1h = ce / 2
    quietly summarize l1h, meanonly
    local l1 = r(mean)
    post `postto' ("`scen'") ("`mode'") ("`method'") (`g') (`nh') (`nev') (`nfy') (`nown') (`nunf') (`nnoen') (`nzero') ///
        (`hid_aff') (`hid_all') (`excl_share') (`m_tot') (`m_sc') (`p_ape') (`p_sre') (`p_over') (`cm') (`l1') ///
        (`nev_mc') (`m_sc_mc') (`l1_mc') (`ncy_h') (`rel50') (`rel90') ///
        (`n_chg') (`chg_mae') (`chg_sign') (`n_cchg') (`cchg_rel') (`cchg_sign') (`cchg_pos') (`n_long') (`long_rel') (`long_sign')
end

local cols "str10 scen str1 mode str8 method byte g hidden evaluated affected_fy n_own_history n_unfilled n_no_energy n_true_zero double(hidden_share_affected hidden_share_truthset excluded_share share_MAE scope_share_MAE med_APE med_signed_RE share_over county_MAE county_L1_half) evaluated_multicounty double(scope_share_MAE_multicounty county_L1_half_multicounty) county_years_with_hidden double(county_rel_p50 county_rel_p90) n_estab_changes double(estab_change_MAE estab_change_sign) n_county_changes double(county_change_relMAE county_change_sign county_change_pos) n_county_long double(county_long_relMAE county_long_sign)"
tempname res gp
postfile res `cols' using "`R'/masking_results.dta", replace
postfile gp str10 scen byte g byte gap_class n double(scope_share_MAE med_APE med_signed_RE) using "`R'/masking_by_gap.dta", replace
foreach s of local scenarios {
    foreach g in 1 2 {
        if "`s'" == "scope1only" & `g' == 2 continue
        foreach m in expected energy {
            eval_mask, scen(`s') mode(A) method(`m') g(`g') rundir("`M'/`s'") cdir("`M'/`s'") hidden("`M'/`s'/hidden.dta")
            eval_mask, scen(`s') mode(B) method(`m') g(`g') rundir("`M'/`s'_B") cdir("`M'/`s'") hidden("`M'/`s'_B/hidden.dta")
            eval_mask, scen(`s') mode(C) method(`m') g(`g') rundir("`M'/`s'") cdir("`M'/`s'") hidden("`M'/`s'/hidden.dta") gapto(gp)
        }
    }
}
postclose res
postclose gp
use "`R'/masking_results.dta", clear
gen byte ord = cond(scen == "random", 1, cond(scen == "small", 2, cond(scen == "nonmanuf", 3, cond(scen == "scope1only", 4, 5))))
sort ord g method mode
drop ord
label var hidden          "Hidden cells with energy use"
label var evaluated       "Common evaluation sample: hidden cells with energy that the released procedure (mode C) estimates"
label var excluded_share  "Share of hidden emissions in cells outside the common sample"
label var share_MAE       "Mean |estimate - true| / firm-year total (S1 + S2), common sample"
label var scope_share_MAE "Mean |estimate - true| / firm-year scope total, common sample"
label var med_APE         "Median |estimate - true| / true, common sample with true > 0"
label var med_signed_RE   "Median (estimate - true) / true"
label var share_over      "Share of evaluated cells over-predicted"
label var county_MAE      "Mean |county-year spatial share error| over affected firm-years (unfilled hidden cells count as zero)"
label var county_L1_half  "Mean over years of half the L1 distance (total variation) between true and estimated county distributions"
label var scope_share_MAE_multicounty "scope_share_MAE for affected firm-years spanning 2+ counties"
label var county_L1_half_multicounty  "county_L1_half for affected firm-years spanning 2+ counties"
label var county_rel_p50  "Median |estimated - true| / true over county-years containing hidden cells"
label var county_rel_p90  "90th percentile of the same"
label var estab_change_MAE  "Mean |estimated - true year-to-year change| / firm-year total, cells hidden in consecutive years"
label var estab_change_sign "Share of those changes with the correct sign"
label var county_change_relMAE "Sum |estimated - true county-year change| / sum |true change| (fixed cohort: firms affected in both years)"
label var county_change_pos "Share of true county-year changes that are positive (naive always-increase benchmark)"
label var n_county_long "County first-to-last-year differences evaluated (firms affected in both 2012 and 2023)"
label var county_change_sign   "Share of county-year changes with the correct sign"
label var county_long_relMAE   "Same for first-to-last-year differences by county"
label var county_long_sign     "Share of first-to-last-year differences with the correct sign"
label var hidden_share_affected "Hidden emissions / emissions of affected firm-years"
label var hidden_share_truthset "Hidden emissions / emissions of all truth firm-years"
save "`R'/masking_results.dta", replace
format %6.4f share_MAE scope_share_MAE county_MAE county_L1_half scope_share_MAE_multicounty county_L1_half_multicounty estab_change_MAE
format %5.3f med_APE med_signed_RE share_over hidden_share_affected hidden_share_truthset excluded_share county_rel_p50 county_rel_p90 estab_change_sign county_change_relMAE county_change_sign county_change_pos county_long_relMAE county_long_sign
list scen g method mode hidden evaluated n_own_history n_unfilled excluded_share scope_share_MAE med_APE med_signed_RE share_over county_MAE county_L1_half, noobs sepby(scen g)
list scen g method mode evaluated_multicounty scope_share_MAE_multicounty county_L1_half_multicounty county_years_with_hidden county_rel_p50 county_rel_p90 if mode == "C", noobs sepby(scen g)
list scen g method mode n_estab_changes estab_change_MAE estab_change_sign n_county_changes county_change_relMAE county_change_sign county_change_pos n_county_long county_long_relMAE county_long_sign if mode == "C", noobs sepby(scen g)
use "`R'/masking_by_gap.dta", clear
label define gapc 1 "1 year" 2 "2-3 years" 3 "4+ years" 4 "no own history", replace
label values gap_class gapc
label var gap_class "Distance to the nearest own report after masking"
sort scen g gap_class
save "`R'/masking_by_gap.dta", replace
format %6.4f scope_share_MAE
format %5.3f med_APE med_signed_RE
list, noobs sepby(scen g)

* replications of the random scenario (mode C)
tempname rr
postfile rr `cols' using "`M'/rep_eval.dta", replace
forvalues i = 1/`reps' {
    foreach g in 1 2 {
        foreach m in expected energy {
            eval_mask, scen(rep`i') mode(C) method(`m') g(`g') rundir("`M'/rep`i'") cdir("`M'/rep`i'") hidden("`M'/rep`i'/hidden.dta") postto(rr)
        }
    }
}
postclose rr
use "`M'/rep_eval.dta", clear
collapse (mean) mean_share_MAE = share_MAE mean_med_APE = med_APE mean_county_MAE = county_MAE mean_L1_half = county_L1_half ///
         (min) min_share_MAE = share_MAE min_med_APE = med_APE min_county_MAE = county_MAE ///
         (max) max_share_MAE = share_MAE max_med_APE = med_APE max_county_MAE = county_MAE (count) replications = share_MAE, by(method g)
label var replications "Number of random-masking replications (mode C, different seeds)"
sort g method
save "`R'/masking_replications.dta", replace
format %6.4f mean_share_MAE min_share_MAE max_share_MAE mean_county_MAE min_county_MAE max_county_MAE mean_L1_half
format %5.3f mean_med_APE min_med_APE max_med_APE
list, noobs
forvalues i = 1/`reps' {
    capture erase "`M'/rep`i'/hidden.dta"
    capture erase "`M'/rep`i'/data/NGMS_ENV_ready_2026_09_13.dta"
    local files : dir "`M'/rep`i'/results" files "*.dta"
    foreach f of local files {
        capture erase "`M'/rep`i'/results/`f'"
    }
    capture rmdir "`M'/rep`i'/results"
    capture rmdir "`M'/rep`i'/data"
    capture rmdir "`M'/rep`i'"
}
capture erase "`M'/rep_eval.dta"
display as text "3d_masking_validation complete."
