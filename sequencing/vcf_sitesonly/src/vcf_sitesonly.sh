#!/bin/bash
# vcf_qc 0.0.1
# Generated by dx-app-wizard.
#
# Basic execution pattern: Your app will run on a single machine from
# beginning to end.
#
# Your job's input variables (if any) will be loaded as environment
# variables before this script runs.  Any array inputs will be loaded
# as bash arrays.
#
# Any code outside of main() (or any entry point you may add) is
# ALWAYS executed, followed by running the entry point itself.
#
# See https://wiki.dnanexus.com/Developer-Portal for tutorials on how
# to modify this file.

set -x

main() {


    echo "Value of vcf_fn: '$vcf_fn'"


	# first, we need to match up the VCF and tabix index files
	# To do that, we'll get files of filename -> dxfile ID
	VCF_LIST=$(mktemp)
	for i in "${!vcf_fn[@]}"; do	
		SUBJOB=$(dx-jobutil-new-job get_so -ivcf_fn="${vcf_fn[$i]}")
   		dx-jobutil-add-output vcf_out --array "$SUBJOB:vcf_out" --class=jobref
	    dx-jobutil-add-output vcfidx_out --array "$SUBJOB:vcfidx_out" --class=jobref	
	done
}


get_so() {

    echo "Value of vcf_fn: '$vcf_fn'"

    # The following line(s) use the dx command-line tool to download your file
    # inputs to the local file system using variable names for the filenames. To
    # recover the original filenames, you can use the output of "dx describe
    # "$variable" --name".

	OUTDIR=$(mktemp -d)
	PREFIX=$(dx describe --name "$vcf_fn" | sed 's/\.vcf.\(gz\)*$//')

    dx cat "$vcf_fn" | pigz -dc | cut -f 1-8 | bgzip -c > $OUTDIR/header.$PREFIX.vcf.gz	
    tabix -p vcf $OUTDIR/header.$PREFIX.vcf.gz
    
	vcf_hdr_out=$(dx upload "$OUTDIR/header.$PREFIX.vcf.gz" --brief)
    vcfidx_hdr_out=$(dx upload "$OUTDIR/header.$PREFIX.vcf.gz.tbi" --brief)
	dx-jobutil-add-output vcf_out "$vcf_hdr_out" --class=file
	dx-jobutil-add-output vcfidx_out "$vcfidx_hdr_out" --class=file
	
}