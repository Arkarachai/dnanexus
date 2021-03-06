<!-- dx-header -->
# sleeper (DNAnexus Platform App)

sleeper

This is the source code for an app that runs on the DNAnexus Platform.
For more information about how to run or modify it, see
https://wiki.dnanexus.com/.
<!-- /dx-header -->

This App provides some useful tools when working with data in DNANexus.  This
App is designed to be run on the command line with "dx run --ssh RL_Sleeper_App" 
in the project that you have data that you want to explore (use "dx select" to
switch projects as needed).

Currently, the tools that are provided are as follows:

 * PLINK (v. 1.07 and 1.9)
 * PLATO (2.1, regular and debug versions)
 * Impute2
 * SHAPEIT2
 * Eigensoft 6.0
 * R (3.0.2) libraries / scripts:

     * BiocInstaller
     * bitops
     * devtools
     * digest
     * doMC
     * evalueate
     * foreach
     * gdsfmt
     * getopt
     * httr
     * iterators
     * jsonlite
     * memoise
     * optparse
     * plyr
     * Rcpp
     * RCurl
     * reshape2
     * RUnit
     * SNPRelate
     * stringr
     * whisker

<!--
TODO: This app directory was automatically generated by dx-app-wizard;
please edit this Readme.md file to include essential documentation about
your app that would be helpful to users. (Also see the
Readme.developer.md.) Once you're done, you can remove these TODO
comments.

For more info, see https://wiki.dnanexus.com/Developer-Portal.
-->
