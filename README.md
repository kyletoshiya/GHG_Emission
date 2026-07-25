# Firm-Establishment Matched Carbon Emissions Data in South Korea from 2011 to 2023

## Overview
This repository provides the data and code required to replicate the figures and tables in our paper. The scripts included here reproduce all reported results.


## Software
Stata 18

## Data

### National Greenhouse Gas Management System (NGMS)
NGMS provides **annual GHG emissions data from 2011 to 2023 for firms** participating in the Emissions Trading Scheme (ETS) and the Target Management System (TMS). ETS covers firms that meet at least one of the following three criteria: (a) have averaged more than 125,000 tCO₂-eq in annual GHG emissions over the past three years; (b) operate at least one establishment with annual average emissions exceeding 25,000 tCO₂-eq; or (c) voluntarily apply (Act on the Allocation and Trading of Greenhouse-Gas Emission Permits, No.20229). TMS covers firms that meet at least one of the following two criteria: (a) have averaged more than 50,000 tCO₂-eq in annual GHG emissions over the past three years; or (b) operate at least one establishment with annual average emissions exceeding 15,000 tCO₂-eq (Framework Act on Carbon Neutrality and Green Growth for Coping with Climate Crisis, No. 20849).

Source: [National Greenhouse Gas Management System (NGMS)](https://ngms.gir.go.kr:8443/subMain.do?link=/hom/bbs/OGCMBBS023V.xml&menuNo=50900503)

### Environmental Information Disclosure System (ENV-Info)
Under Article 16-8 of the Environmental Technology and Industry Support Act, public institutions prescribed by Presidential Decree and establishements with significant environmental effects are required to prepare and disclose their environmental information. Establishments in this system are required to report not only environmental information but also general information about the firm. Accordingly, this dataset includes environmental variables such as **GHG emissions (Scope 1), GHG emissions (Scope 2), water use, energy use, waste generation, and chemical use**, as well as establishment-level variables such as **industry, address, number of employees, revenue, and product**.

Source: [Environmental Information Disclosure System (ENV-Info)](https://www.env-info.kr/)

## File Description

### dta File
* **NGMS_ENV_matched.dta**
  
   This dataset was constructed by matching firm-level data from NGMS with establishment-level data from ENV-Info. It represents the raw data before any missing values were imputed.

* **NGMS_ENV_estimated.dta**
  
   This dataset provides estimates of GHG emissions for establishments, based on their energy use.


  #### ▸ Variables List and Description


    | Variable | Description | Unit |
    |---|---|---|
    | `firm_name` | Firm name | — |
    | `est_name` | Establishment name | — |
    | `year` | Year | — |
    | `emission_ngms` | Firm-level GHG emissions reported to NGMS | tCO₂-eq |
    | `est_emission_scope1` | Establishment-level direct GHG emissions (Scope 1) | tCO₂-eq |
    | `est_emission_scope2` | Establishment-level indirect GHG emissions from purchased energy (Scope 2) | tCO₂-eq |
    | `industry` | Industry classification | — |
    | `sub_industry` | Sub-industry classification | — |
    | `address` | Establishment address | — |
    | `employee` | Number of employees | persons |
    | `revenue` | Firm revenue | KRW million |
    | `product` | Main product(s) produced | — |
    | `water` | Water use | ton |
    | `energy` | Energy use | TJ |
    | `waste` | Waste generation | ton |
    | `chemicals` | Chemical use | ton |
    | `sido` | Province-level administrative division (Sido) | — |
    | `sigungu` | County-level administrative division (Sigungu) | — |
    | `emi_s1_firm` | NGMS-reported firm-level Scope 1 total | tCO₂-eq |
    | `emi_s1_estab` | Final Scope 1 establishment-level emissions | tCO₂-eq |
    | `emi_s1_src` | Source of `emi_s1_estab`: 0 = actual, 1 = estimated, missing = unfilled | — |
    | `emi_s2_firm` | Predicted firm-level Scope 2 total | tCO₂-eq |
    | `emi_s2_estab` | Final Scope 2 establishment-level emissions | tCO₂-eq |
    | `emi_s2_src` | Source of `emi_s2_estab`: 0 = actual, 1 = estimated, missing = unfilled | — |


### do File

* **scope1_estimation.do**

  This code is organized into the following steps:
  
  1. Build analysis file
  2. Leave-one-firm-out validation
  3. Performance metrics
  4. Fill missing scope 1 emissions
  5. Validation figures
  
  We present **valid_s1_estab_sha_energy.png** and **valid_s1_county_sha_energy.png** as panels (a) and (b) of Figure 2 in the paper, respectively.
  We present **valid_s1_estab_emi_energy.png** and **valid_s1_county_emi_energy.png** as panels (a) and (b) of Figure 5 in the paper, respectively.


* **scope2_estimation.do**

  This code is organized into the following steps:
  
  1. Build analysis file
  2. Estimate reported ENV scope 2 firm-year totals
  3. Leave-one-firm-out validation
  4. Performance metrics
  5. Fill missing scope 2 emissions
  6. Validation figures
  
  We present **valid_s2_estab_sha_energy.png** and **valid_s2_county_sha_energy.png** as panels (c) and (d) of Figure 2 in the paper, respectively.
  We present **valid_s2_estab_emi_energy.png** and **valid_s2_county_emi_energy.png** as panels (c) and (d) of Figure 5 in the paper, respectively.

* **construct_final.do**

  This code is organized into the following steps:
  
  1. Load matched panel and merge in final Scope 1 and Scope 2 estimates.
  2. Assert row-count and source-flag consistency (actual / estimated / unfilled).
  3. Rename and label variables for the final data dictionary.
  4. Drop intermediate identifiers and save the final establishment-level dataset.

### csv File
    Each CSV file was used to construct the GIS data shown in Figures 3 and 4 of the paper. 
    A description of each CSV file is provided below.
    
    | File Name | Description |
    |---|---|
    | `figure3_a.csv` | County-level Scope 1 GHG emissions in 2013 (ENV-Info) |
    | `figure3_b.csv` | County-level Scope 1 GHG emissions in 2023 (ENV-Info) |
    | `figure3_c.csv` | County-level change in Scope 1 GHG emissions, 2013–2023 (ENV-Info) |
    | `figure3_d.csv` | County-level Scope 1 GHG emissions in 2013 (NGMS) |
    | `figure3_e.csv` | County-level Scope 1 GHG emissions in 2023 (NGMS) |
    | `figure3_f.csv` | County-level change in Scope 1 GHG emissions, 2013–2023 (NGMS) |
    | `figure4_a.csv` | County-level Scope 2 GHG emissions in 2013 (ENV-Info) |
    | `figure4_b.csv` | County-level Scope 2 GHG emissions in 2023 (ENV-Info) |
    | `figure4_c.csv` | County-level change in Scope 2 GHG emissions, 2013–2023 (ENV-Info) |
    | `figure4_d.csv` | County-level total (Scope 1 + Scope 2) GHG emissions in 2013 (ENV-Info) |
    | `figure4_e.csv` | County-level total (Scope 1 + Scope 2) GHG emissions in 2023 (ENV-Info) |
    | `figure4_f.csv` | County-level change in total (Scope 1 + Scope 2) GHG emissions, 2013–2023 (ENV-Info) |


## Replication Instructions

**Set the directory and run the do file as follows.**

* **Set the directory**


```bash
global main = "PUT YOUR DIRECTORY"
global dofile ="${main}/dofile"
```

* **Run do file**
```bash
do "${dofile}/scope1_estimation.do"
do "${dofile}/scope2_estimation.do"
do "${dofile}/construct_final.do"
```
