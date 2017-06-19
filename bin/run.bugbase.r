#!/usr/bin/env Rscript
# Runs BugBase analysis:
# - Uses a single-cell approach to predict microbiome phenotypes
# - plots phenotype relative abundances
# - prints statisical analyses
# - plots thresholds
# - plots otu contributions

# USAGE
# Default
# predict_phenotypes.r 	-i otu_table.txt 
#						-m mapping_file.txt 
#						-c map_column 
#						-o output_directory_name 

# Options
# -w 	Data is whole genome shotgun data (picked against IMG database) 
# -t 	Specify which taxa level to plot otu contributions by (number 1-7) 
# -p 	Specify list of traits (phenotypes) to test (list, comma separated)
# -T 	Specify a threshold to use for all traits (number 0-1)
# -g 	Specify subset of groups in map column to plot (list, comma separated)
# -u  Use a user-define trait table. Absolute file path must be specified
# -k  Use the kegg pathways instead of default traits
# -z 	Data is of type continuous 
# -C 	Use covariance instead of variance to determine thresholds
# -a 	Plot all samples (no stats will be run)
options(warn = -1)

#Set BugBase path
my_env <- Sys.getenv(c('BUGBASE_PATH'))
if(my_env == ""){
  stop("BUGBASE_PATH not set.")
}

#Load packages needed
# library(optparse)
# library(reshape2) 
# library(plyr)
# library(RColorBrewer)
# library(gridExtra)
# library(ggplot2)
# library(beeswarm)
# library(biom)

#See if these packages exist on comp, if not, install.
package_list <- c("optparse", 
  "reshape2", 
  "plyr", 
  "RColorBrewer", 
  "gridExtra", 
  "ggplot2", 
  "beeswarm", 
   "plyr",
   "RJSONIO",
   "Matrix")

for(i in 1:length(package_list)){
  if(!require(package_list[i])){
    install.packages(package_list[i], dependancies =T)
    library(package_list[i])
}

#Set R package paths - This is to over come the lack of biom now available
lib_location <- paste(my_env, "/R_lib", sep='/')

# Load biom package
library(biom, lib.loc = lib_location)

#Find functions in the lib
lib_dir <- paste(my_env, "/lib", sep='/')
r_funcs <- list.files(lib_dir)
for (i in 1:length(r_funcs)){
  source(paste(lib_dir, r_funcs[[i]], sep = "/"))
}

option_list <- list(
  make_option(c("-v", "--verbose"), action="store_true", default=TRUE,
              help="Print extra output [default]"),
  make_option(c("-i", "--otutable"), type="character", default=NULL,
              help="otu table to plot [default %default]"),
  make_option(c("-c", "--mapcolumn"), type="character", default=NULL,
              help="column of mapping file to plot [default %default]"),
  make_option(c("-m", "--mappingfile"), type="character", default=NULL,
              help="mapping file to plot [default %default]"),
  make_option(c("-o", "--output"), type="character", default=".",
              help="output directory [default %default]"),
  make_option(c("-t", "--taxalevel"), type="character", default=NULL,
              help="taxa level to plot otu contributions by, default is 
              2 (phylum) [default %default]"),
  make_option(c("-p", "--phenotype"), type="character", default=NULL,
              help="specific traits (phenotypes) to predict, separated by 
              commas, no spaces [default %default]"),
  make_option(c("-x", "--predict"), action="store_true", default=FALSE,
              help="only output the prediction table, do not make plots 
              [default %default]"),
  make_option(c("-T", "--threshold"), type="character", default=NULL,
              help="threshold to use, must be between 0 and 1 
              [default %default]"),
  make_option(c("-g", "--groups"), type="character", default=NULL,
              help="treatment groups of samples, separated by commas, no spaces 
              [default %default]"),
  make_option(c("-u", "--usertable"), type="character", default=NULL,
              help="user define trait table, absolute file path required [
              default %default]"),
  make_option(c("-z", "--continuous"), action="store_true", default=FALSE,
              help="plot continuous data [default %default]"),
  make_option(c("-k", "--kegg"), action="store_true", default=FALSE,
              help="use kegg pathway table [default %default]"),
  make_option(c("-C", "--cov"), action="store_true", default=FALSE,
              help="use covariance instead of variance [default %default]"),
  make_option(c("-a", "--all"), action="store_true", default=FALSE,
              help="plot all samples without a mapping file (this outputs no 
              statistics) [default %default]"),
  make_option(c("-w", "--wgs"), action="store_true", default=FALSE,
              help="Data is whole genome shotgun data 
              (picked against IMG database) [default %default]")
  )
opts <- parse_args(OptionParser(option_list=option_list))

#Define the database files
db_fp <- paste(my_env, "/usr", sep='/')

#Check for WGS and KEGG
if(isTRUE(opts$wgs)){
  copy_no_file <- paste(db_fp, "16S_13_5_precalculated.txt.gz", sep='/')
  taxonomy <- paste(db_fp, "img_otu_taxonomy.txt.gz", sep='/')
  if(isTRUE(opts$kegg)){
    trait_table <- paste(db_fp, 
      "kegg_modules_img_precalculated.txt.gz", sep='/')
    if(!isTRUE(opts$predict)){
      if(is.null(opts$phenotype)){
      stop("A list of modules must be specified when using KEGG")
      }
    }
  } else {
    if(is.null(opts$usertable)){
      trait_table <- paste(db_fp, 
        "default_traits_img_precalculated.txt.gz", sep='/')
    } else{
      trait_table <- opts$usertable
    }
  }
} else {
  copy_no_file <- paste(db_fp, "16S_13_5_precalculated.txt.gz", sep='/')
  taxonomy <- paste(db_fp, "97_otu_taxonomy.txt.gz", sep='/')
  if(isTRUE(opts$kegg)){
    trait_table <- paste(db_fp, "kegg_modules_precalculated.txt.gz", sep='/')
    if(!isTRUE(opts$predict)){
      if(is.null(opts$phenotype)){
      stop("A list of modules must be specified when using KEGG")
      }
    }
  } else {
    if(is.null(opts$usertable)){
      trait_table <- paste(db_fp, 
        "default_traits_precalculated.txt.gz", sep='/')
    } else{
      trait_table <- opts$usertable
    }
  }
}

#Check for 'plot all'
#If not 'plot all', check map and column exist
if(!isTRUE(opts$all)){
  if(isTRUE(opts$predict)){
    map <- NULL
    mapcolumn <- NULL
    groups <- NULL

  } else {
    if(is.null(opts$mappingfile)){
    stop("Mapping file not specified. 
         To run BugBase without a mapping file use '-a'")
    } else {
      map <- opts$mappingfile
    }
    if(is.null(opts$mapcolumn)){
      stop("Column header must be specified")
    } else {
      mapcolumn <- opts$mapcolumn
      groups <- opts$groups
    }
  }
} else {
  map <- NULL
  mapcolumn <- NULL
  groups <- NULL
}

# If continuous, remove groups
if(isTRUE(opts$continuous)){
  groups <- NULL #plotting by continuous ignores groups in the column
}

#Define OTU table
if(is.null(opts$otutable)){
  stop("No otu table specified")
} else {
  otu_table <- opts$otutable
}

#Define threshold
threshold_set <- opts$threshold
if(! is.null(threshold_set)){
  if(! 1 >= threshold_set) {
    stop("Threshold must be between 0 and 1")
  }
  if(! threshold_set > 0){
    stop("Threshold must be between 0 and 1")
  }
}

#Define taxa level
taxa_level <- opts$taxalevel
if(! is.null(taxa_level)){
  if(! taxa_level %in% c(1,2,3,4,5,6,7)){
    stop("Taxa level must be 1,2,3,4,5,6 or 7")
  }
}

#Define trait (phenotype) to predict, default is all
test_trait <- opts$phenotype
if(! is.null(test_trait)){
  if(test_trait == "all"){
    test_trait <- NULL
  }
} else {
  test_trait <- test_trait
}

#Define metric for threshold calculations (variance is default)
use_cov <- opts$cov
if(! isTRUE(use_cov)){
  use_cov <- NULL
}

#Make output directories
output <- opts$output
if(output != "."){
  if(!file.exists(output)){
    dir.create(output, showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output, "normalized_otus"))
    dir.create(file.path(output, "predicted_phenotypes"))
    dir.create(file.path(output, "thresholds"))
    dir.create(file.path(output, "otu_contributions"))
  } else {
    stop("Output directory already exists")
  }
} else {
  stop("Cannot create a hidden directory")
}

print("Loading Inputs...")
#Load inputs
#Required: otu table
#Options: map, map column,groups
loaded.inputs <- load.inputs(otu_table, map, mapcolumn, groups)

if(isTRUE(opts$wgs)){
  print("WGS specified, no copy number normalization will take place...")
} else {
  print("16S copy number normalizing OTU table...")
  #16S copy normalize otu table
  #Required: copyNo_table, loaded otu
  normalized_otus <- copyNo.normalize.otu(copy_no_file, 
    loaded.inputs$otu_table, output)
}

print("Predicting phenotypes...")
#Make predictions
#Required:trait table,  normalized otu table
#Options: single trait, threshold, use cov
if(isTRUE(opts$wgs)){
  prediction_outputs <- single.cell.predictions(trait_table, 
                                                loaded.inputs$otu_table, 
                                                test_trait,
                                                threshold_set,
                                                use_cov)
} else {
  prediction_outputs <- single.cell.predictions(trait_table, 
                                                normalized_otus, 
                                                test_trait,
                                                threshold_set,
                                                use_cov)
}

if(isTRUE(opts$predict)){
  print("BugBase analysis complete")
} else{
  print("Plotting thresholds...")
  #Plot thresholds
  #Two options - one with no mapping file, one with mapping file
  if(is.null(threshold_set)){
    if(isTRUE(opts$all)){
      #Required: predictions
      plot.thresholds.all(prediction_outputs$predictions)
    } else {
      #Required: predictions, map and map column
      plot.thresholds(prediction_outputs$predictions, 
                    loaded.inputs$map, 
                    loaded.inputs$map_column)
    }
  }

  print("Plotting predictions...")
  #Plot predictions
  #Three options: one without a mapping file, 
  #   one with a mapping file, continous
  #   one with a mapping file, discrete
  if(isTRUE(opts$all)){
    #Required: predictions
    plot.predictions.all(prediction_outputs$final_predictions)
  } else {
    if(isTRUE(opts$continuous)){
      #Required: predictions, map, map column
      plot.predictions.continuous(prediction_outputs$final_predictions, 
                                  loaded.inputs$map, 
                                  loaded.inputs$map_column)
    } else {
      #Required: predictions, map, map column
      plot.predictions.discrete(prediction_outputs$final_predictions, 
                                loaded.inputs$map, 
                                loaded.inputs$map_column)
    }
  }

  print("Plotting OTU contributions...")
  #Plot otu contributions (taxa summaries)
  #Two options, with a mapping file or without
  if(isTRUE(opts$wgs)){
    if(isTRUE(opts$all)){
      #Required: otu contributions, normalized otu table, taxonomy
      otu.contributions.all.r(prediction_outputs$otus_contributing,
                            prediction_outputs$otu_table_subset,
                            taxonomy, taxa_level)
    } else {
      #Required: otu contributions, normalized otu table, taxonomy
      #   map, map column, taxa_level
      otu.contributions(prediction_outputs$otus_contributing, 
                        prediction_outputs$otu_table_subset, 
                        taxonomy, 
                        loaded.inputs$map, 
                        loaded.inputs$map_column,
                        taxa_level)
    }
  } else {
    if(isTRUE(opts$all)){
      #Required: otu contributions, normalized otu table, taxonomy
      otu.contributions.all.r(prediction_outputs$otus_contributing,
                            prediction_outputs$otu_table_subset,
                            taxonomy, taxa_level)
    } else {
      #Required: otu contributions, normalized otu table, taxonomy
      #   map, map column, taxa_level
      otu.contributions(prediction_outputs$otus_contributing, 
                        prediction_outputs$otu_table_subset, 
                        taxonomy, 
                        loaded.inputs$map, 
                        loaded.inputs$map_column,
                        taxa_level)
    }
  }
print("BugBase analysis complete")
}
