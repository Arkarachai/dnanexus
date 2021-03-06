#!/bin/bash
# vcf_summary 0.0.1
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

	if test "$variant" = "false" -a "$sample" = "false"; then
		dx-jobutil-report-error "No Summary stats requested; what's the point?"
	fi

    echo "Value of vcf_fn: '$vcf_fn'"
    
    if test -z "$prefix"; then
    	prefix=$(dx describe --name "$vcf_fn" | sed 's/\.vcf\(\.gz\)*$//')
    fi

	WKDIR=$(mktemp -d)
	cd $WKDIR
	OUTDIR=$(mktemp -d)
	
	ext=$(dx describe --name "$vcf_fn" | sed 's/.*\.\([^.]*\)$/\1/')
	cat_cmd="cat"
	LOCALFN="input.vcf"
	if test "$ext" = "gz"; then
		ext="vcf.gz"
		cat_cmd="zcat"
		LOCALFN="input.vcf.gz"
	fi

    dx download "$vcf_fn" -o $LOCALFN
    
    if test "$sample" = "true"; then
		# download biofilter + loki
		sudo mkdir /usr/share/biofilter
		sudo chmod a+rwx /usr/share/biofilter
		
		dx download -r "$DX_RESOURCES_ID:/biofilter/*" -o /usr/share/biofilter
		dx download "$DX_RESOURCES_ID:/LOKI/loki-20150427-nosnps.db" -o /usr/share/biofilter/loki.db
		
		# convert the chrom/pos of each position in the VCF into a biofilter-compatible chrom/pos input
		$cat_cmd $LOCALFN | grep -v '^#' | cut -f1,2 | tee bf_chrpos | wc -l
		
		python /usr/share/biofilter/biofilter.py -k /usr/share/biofilter/loki.db -P bf_chrpos --annotate position gene --gbv 37 --stdout > bf_raw
		
		cat bf_raw | \
			tail -n+2 | cut -f2,4 | \
			awk 'BEGIN{pv=""; pl="";} {if($1 != pv){ if(length(pv)){ print pv "\t" pl}; pv=$1; pl=$2;} else {pl=(pl "," $2);}}  END {print pv "\t" pl;}' | \
			sed -e 's/^chr//' -e's/:/\t/' | tee bf_geneout | wc -l
			
		# Now, bf_geneout should be a 3-column file with chrom, pos, gene(s) (comma-separated)
		# pass that and the unzipped VCF to our python script to calculate sample-level stats
		sample_summary.py bf_geneout <($cat_cmd $LOCALFN) | tee $OUTDIR/$prefix.sample | wc -l
	   
		sample_status=$(dx upload $OUTDIR/$prefix.sample --brief)
    	dx-jobutil-add-output sample_status "$sample_status" --class=file
    fi
    
    # Use Marta's variant script to get by-variant summary stats here	
    if test "$variant" = "true"; then

		touch $OUTDIR/$prefix.variants

		variant_stats=$(dx upload $OUTDIR/$prefix.variants --brief)
	    dx-jobutil-add-output variant_stats "$variant_stats" --class=file
   	fi

    # The following line(s) use the utility dx-jobutil-add-output to format and
    # add output variables to your job's output as appropriate for the output
    # class.  Run "dx-jobutil-add-output -h" for more information on what it
    # does.

 

}
