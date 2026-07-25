# Firm-Establishment Matched Carbon Emissions Data in South Korea from 2011 to 2023

## Overview
This repository provides the data and code required to replicate the figures and tables in our paper. The scripts included here reproduce all reported results.


## Software
Stata 18

## Data

### National Greenhouse Gas Management System (NGMS)
NGMS provides GHG emissions for firms that participate in the Emissions Trading Scheme (ETS) and the Target Management System (TMS). ETS covers firms that meet at least one of the following three criteria: (a) have averaged more than 125,000 tCO<sub>2</sub>-eq in annual GHG emissions over the past three years; (b) operate at least one establishment with annual average emissions exceeding 25,000 tCO$_2$-eq; or (c) voluntarily apply (Act on the Allocation and Trading of Greenhouse-Gas Emission Permits, No.20229). TMS covers firms that meet at least one of the following two criteria: (a) have averaged more than 50,000 tCO$_2$-eq in annual GHG emissions over the past three years; or (b) operate at least one establishment with annual average emissions exceeding 15,000 tCO$_2$-eq (Framework Act on Carbon Neutrality and Green Growth for Coping with Climate Crisis, No. 20849).


### Environmental Information Disclosure System (ENV-Info)
Under Article 16-8 of the Environmental Technology and Industry Support Act, public institutions prescribed by Presidential Decree and enterprises with significant environmental effects are required to prepare and disclose their environmental information. It provides 


## File Description

### dta File
* **EPA_SCC.dta**
  
   It contains the Social Cost of Carbon at discount rates of 1.5%, 2.0%, and 2.5% through 2100.

### do File
* **Figure1_a**

   This code replicates Panel (a) in Figure 1.
  

## Replication Instructions

**Set the directory and run the do file as follows.**
* **Set the directory**

   global directory ""

   global data = "${directory}/data"

   global code = "${directory}/code"

* **Run do file**

   do "${code}/figure1_a.do"
