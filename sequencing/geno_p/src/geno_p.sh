#!/bin/bash
# geno_p 0.0.1
# Generated by dx-app-wizard.
#
# Parallelized execution pattern: Your app will generate multiple jobs
# to perform some computation in parallel, followed by a final
# "postprocess" stage that will perform any additional computations as
# necessary.
#
# Your job's input variables (if any) will be loaded as environment
# variables before this script runs.  Any array inputs will be loaded
# as bash arrays.
#
# Any code outside of main() or any other entry point is ALWAYS
# executed, followed by running the entry point itself.
#
# See https://wiki.dnanexus.com/Developer-Portal for tutorials on how
# to modify this file.

set -x

# install GNU parallel!
sudo sed -i 's/^# *\(deb .*backports.*\)$/\1/' /etc/apt/sources.list
sudo apt-get update
sudo apt-get install --yes parallel

sudo pip install pytabix

function parallel_download() {
	set -x
	cd $2
	dx download "$1"
	cd -
}
export -f parallel_download

function parallel_name_dxid() {
	dx describe --json "$1" | jq -r ".name,.id" | tr '\n' '\t' | sed 's/\t$/\n/' >> $2
}
export -f parallel_name_dxid

function dl_part_index() {
	set -x
	echo "'$1', '$2', '$3', '$4'"
	cd "$2"
	fn_id=$(dx describe --json "$1" | jq -r ".name,.id" | tr '\n' '\t' | sed 's/\t$//')
	
	fn=$(echo "$fn_id" | cut -f1)
	fn_base=$(echo "$fn" | sed 's/.vcf.gz$//')
	file_dxid=$(echo "$fn_id" | cut -f2)
	idxfn=$(ls "$2/$fn.tbi")
	
	set -o 'pipefail'
	
	RERUN=1
	MAX_RETRY=5
	while test $RERUN -ne 0 -a $MAX_RETRY -gt 0; do
		download_part.py -f "$file_dxid" -i "$idxfn" -L "$3" -o "$4/$fn_base.$3.vcf.gz" -H
		RERUN="$?"
		MAX_RETRY=$((MAX_RETRY - 1))
	done
	
	# Make sure to cause problems downstream if we didn't succeed
	if test "$RERUN" -eq 0; then
		tabix -p vcf "$4/$fn_base.$3.vcf.gz"
	fi
}

export -f dl_part_index

function dl_index() {
 	set -x
	echo "'$1', '$2', '$3'"
 	cd "$2"
 	fn=$(dx describe --name "$1")
	dx download "$1" -o "$fn"
	if test -z "$(ls $fn.tbi)"; then
		tabix -p vcf $fn
	fi
	echo "$2/$fn" >> $3
}

export -f dl_index


main() {

	export SHELL="/bin/bash"
	ADDL_CMD=""

	PADDED=0

	SUBJOB_ARGS=""
	if test "$target_file"; then
		tgt_id=$(dx describe "$target_file" --json | jq .id | sed 's/"//g')
		SUBJOB_ARGS="$SUBJOB_ARGS -itarget_file:file=$tgt_id"
		
		if [ -n "$padding" ] && [ "$padding" -ne 0 ] ; then 
			SUBJOB_ARGS="$SUBJOB_ARGS -ipadding:int=$padding"
			PADDED=1
		fi
	fi
	
	if test -z "$PREFIX"; then
		PREFIX="combined"
	fi
	
	WKDIR=$(mktemp -d)
	GVCF_SPLITDIR=$(mktemp -d)
	DXGVCF_LIST=$(mktemp)
	DXGVCFIDX_LIST=$(mktemp)
	
	cd $WKDIR
	
	# Get a list of chromosomes 
	
	# Let's first download all of the tabix indices
	for i in "${!gvcfidxs[@]}"; do	
		echo "${gvcfidxs[$i]}" >> $DXGVCFIDX_LIST
	done

	parallel -u -j $(nproc) --gnu parallel_download :::: $DXGVCFIDX_LIST ::: $WKDIR
	
	CHR_VCF_LIST=$(mktemp)
	for f in $( ls $WKDIR/*.tbi); do
		VCF_FN="$(echo $f | sed -e 's/\.tbi//' -e 's|.*/||')"
		#echo -en "$(echo $VCF_FN | sed 's|.*/||')\t:"
		tabix -l $VCF_FN | sed "s|$|\t$VCF_FN|"
	done | awk '{arr[$1]=arr[$1] "\t" $2} END {for (x in arr){ print x arr[x]}}' > $CHR_VCF_LIST
	
	echo "CHR_VCF_LIST:"
	cat $CHR_VCF_LIST
	
	# OK, now $VCF_CHR_LIST is a list of chromosome <tab> VCF_FN <tab> VCF_FN ...

	CHROM_LIST=$(mktemp)
		
	#dx download "${gvcfidxs[0]}" -o test.vcf.gz.tbi

	#tabix -l test.vcf.gz > $CHROM_LIST
	for i in "${!gvcfs[@]}"; do
		echo "${gvcfs[$i]}" >> $DXGVCF_LIST
	done
		
	VCF_ID_LIST=$(mktemp)
	VCFIDX_ID_LIST=$(mktemp)
	
	parallel -u -j $(nproc) --gnu parallel_name_dxid :::: $DXGVCF_LIST ::: $VCF_ID_LIST
	parallel -u -j $(nproc) --gnu parallel_name_dxid :::: $DXGVCFIDX_LIST ::: $VCFIDX_ID_LIST
	
	# remove the tbi extension on the VCFIDX list
	sed -i 's/\.tbi\t/\t/' $VCFIDX_ID_LIST
	
	#OK, now join everything together
	JOINT_ID_LIST=$(mktemp)
	join -t$'\t' -j1 <(sort -k1,1 $VCF_ID_LIST) <(sort -k1,1 $VCFIDX_ID_LIST) > $JOINT_ID_LIST
	
	# sanity check, should have same # of lines!
	if test "$(cat $VCF_ID_LIST | wc -l)" -ne "$(cat $VCFIDX_ID_LIST | wc -l)" -o "$(cat $JOINT_ID_LIST | wc -l)" -ne "$(cat $VCF_ID_LIST | wc -l)"; then
		dx-jobutil-report-error "ERROR: VCF and VCF Index arrays do not match!"
	fi
	
	echo "JOINT_ID_LIST:"
	cat $JOINT_ID_LIST
		
	# Kick off each of those subjobs
	CIDX=0
	pparg=""
	pp_hdr_arg=""
	pp_pad_arg=""
	pp_pad_hdr_arg=""
	while read chrom; do
		# get the filename of the 
		CHR_FN_LIST=$(mktemp)
		echo "$chrom" | cut -f2- | tr '\t' '\n' > $CHR_FN_LIST
		CHR=$(echo "$chrom" | cut -f1)
		SINGLE_VCF_LIST=$(mktemp)
		join -t$'\t' -j1 <(sort -k1,1 $CHR_FN_LIST) <(sort -k1,1 $JOINT_ID_LIST) | cut -f2 > $SINGLE_VCF_LIST
		SINGLE_VCFIDX_LIST=$(mktemp)
		join -t$'\t' -j1 <(sort -k1,1 $CHR_FN_LIST) <(sort -k1,1 $JOINT_ID_LIST) | cut -f3 > $SINGLE_VCFIDX_LIST
		
		echo "CHR_FN_LIST":
		cat $CHR_FN_LIST
		
		echo "SINGLE_VCF_LIST:"
		cat $SINGLE_VCF_LIST
		
		echo "SINGLE_VCFIDX_LIST:"
		cat $SINGLE_VCFIDX_LIST
		
		DX_VCF_LIST=$(dx upload $SINGLE_VCF_LIST --brief)
		DX_VCFIDX_LIST=$(dx upload $SINGLE_VCFIDX_LIST --brief)
		
		rm $CHR_FN_LIST
		rm $SINGLE_VCF_LIST
		rm $SINGLE_VCFIDX_LIST
	
		process_job=$(dx-jobutil-new-job genotype_gvcfs -iPREFIX=$PREFIX.$CHR -ichrom=$CHR -ivcf_files:file="$DX_VCF_LIST" -ivcfidx_files:file="$DX_VCFIDX_LIST" $SUBJOB_ARGS)
		#pparg="$pparg -ivcfs=${process_jobs[$CIDX]}:vcf_out -ivcfidxs=${process_jobs[$CIDX]}:vcfidx_out"
		#pp_hdr_arg="$pp_hdr_arg -ivcfs=${process_jobs[$CIDX]}:vcf_hdr_out -ivcfidxs=${process_jobs[$CIDX]}:vcfidx_hdr_out"
		#pp_pad_arg="$pp_pad_arg -ivcfs=${process_jobs[$CIDX]}:vcf_pad_out -ivcfidxs=${process_jobs[$CIDX]}:vcfidx_pad_out"
		#pp_pad_hdr_arg="$pp_pad_hdr_arg -ivcfs=${process_jobs[$CIDX]}:vcf_pad_hdr_out -ivcfidxs=${process_jobs[$CIDX]}:vcfidx_pad_hdr_out"
		
		# We'll just return an array of VCF files here
		dx-jobutil-add-output vcf --array "${process_job}:vcf_out" --class=jobref
		dx-jobutil-add-output vcfidx --array "${process_job}:vcfidx_out" --class=jobref
	    dx-jobutil-add-output vcf_header --array "${process_job}:vcf_hdr_out" --class=jobref
    	dx-jobutil-add-output vcfidx_header --array "${process_job}:vcfidx_hdr_out" --class=jobref
    
    	# If we're padded, add the pads, o/w just duplicate
	    if test "$PADDED" -ne 0; then
			dx-jobutil-add-output vcf_pad --array "${process_job}:vcf_pad_out" --class=jobref
			dx-jobutil-add-output vcfidx_pad --array "${process_job}:vcfidx_pad_out" --class=jobref
	    	dx-jobutil-add-output vcf_pad_header --array "${process_job}:vcf_pad_hdr_out" --class=jobref
	    	dx-jobutil-add-output vcfidx_pad_header --array "${process_job}:vcfidx_pad_hdr_out" --class=jobref
		fi
			
		CIDX=$((CIDX + 1))
		
	done < $CHR_VCF_LIST
	
	# Don't merge here, do it elsewhere in the pipeline
	# OK, now we simply have to merge all of the VCF files together
	
	#postprocess=$(dx run combine_variants $pparg -iprefix="$PREFIX" --brief)
	#dx-jobutil-add-output vcf "$postprocess:vcf_out" --class=jobref
	#dx-jobutil-add-output vcfidx "$postprocess:vcfidx_out" --class=jobref
	#postprocess_hdr=$(dx run combine_variants $pp_hdr_arg -iprefix="$PREFIX.header" --brief)
    #dx-jobutil-add-output vcf_header "$postprocess_hdr:vcf_out" --class=jobref
    #dx-jobutil-add-output vcfidx_header "$postprocess_hdr:vcfidx_out" --class=jobref
    
    #if test "$PADDED" -ne 0; then
   	#	postprocess_pad=$(dx run combine_variants $pp_pad_arg -iprefix="$PREFIX.padded" --brief)
	#	dx-jobutil-add-output vcf_pad "$postprocess_pad:vcf_out" --class=jobref
	#	dx-jobutil-add-output vcfidx_pad "$postprocess_pad:vcfidx_out" --class=jobref
    #	postprocess_pad_hdr=$(dx run combine_variants $pp_pad_hdr_arg -iprefix="$PREFIX.padded.header" --brief)
    #	dx-jobutil-add-output vcf_pad_header "$postprocess_pad_hdr:vcf_out" --class=jobref
    #	dx-jobutil-add-output vcfidx_pad_header "$postprocess_pad_hdr:vcfidx_out" --class=jobref
    #else
	#	dx-jobutil-add-output vcf_pad "$postprocess:vcf_out" --class=jobref
	#	dx-jobutil-add-output vcfidx_pad "$postprocess:vcfidx_out" --class=jobref
    #	dx-jobutil-add-output vcf_pad_header "$postprocess_hdr:vcf_out" --class=jobref
    #	dx-jobutil-add-output vcfidx_pad_header "$postprocess_hdr:vcfidx_out" --class=jobref
    #fi
    	
}

genotype_gvcfs() {

	export SHELL="/bin/bash"
	ADDL_CMD=""
	
	PADDED=0

	if test "$target_file"; then
		dx download "$target_file" -o targets_raw.bed
		sed -n "/^$chrom[ \t].*/p" targets_raw.bed > targets.bed
		if test "$padding"; then
			cat targets.bed | interval_pad.py $padding | tr ' ' '\t' | sort -n -k2,3 > targets.padded.bed
			ADDL_CMD="-L $PWD/targets.padded.bed"
			PADDED=1
		else
			ADDL_CMD="-L $PWD/targets.bed"
		fi

	else
		ADDL_CMD="-L $chrom"
	fi
	
	if test -z "$PREFIX"; then
		PREFIX="combined"
	fi
	
	WKDIR=$(mktemp -d)
	OUTDIR=$(mktemp -d)
	GVCF_LIST=$(mktemp)
	DXGVCF_LIST=$(mktemp)
	DXGVCFIDX_LIST=$(mktemp)
	
	cd $WKDIR
	
	dx download "${vcfidx_files}" -f -o $DXGVCFIDX_LIST
	parallel -u -j $(nproc --all) --gnu parallel_download :::: $DXGVCFIDX_LIST ::: $WKDIR
	
	dx download "${vcf_files}" -f -o $DXGVCF_LIST
	
	# Now, download and index in parallel, please
	parallel -u -j $(nproc --all) --gnu dl_part_index :::: $DXGVCF_LIST ::: $WKDIR ::: $chrom ::: $OUTDIR
	
	echo "Contents of WKDIR:"
	ls -alh $WKDIR
	
	echo "Contents of OUTDIR:"
	ls -alh $OUTDIR
	
	sleep 10	
		
	# get the resources we need in /usr/share/GATK
	sudo mkdir -p /usr/share/GATK/resources
	sudo chmod -R a+rwX /usr/share/GATK
		
	dx download $(dx find data --name "GenomeAnalysisTK-3.4-46.jar" --project $DX_RESOURCES_ID --brief) -o /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar
#	dx download $(dx find data --name "GenomeAnalysisTK-3.3-0-custom.jar" --project $DX_RESOURCES_ID --brief) -o /usr/share/GATK/GenomeAnalysisTK-3.3-0-custom.jar
	dx download $(dx find data --name "dbsnp_137.b37.vcf.gz" --project $DX_RESOURCES_ID --folder /resources --brief) -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz
	dx download $(dx find data --name "dbsnp_137.b37.vcf.gz.tbi" --project $DX_RESOURCES_ID --folder /resources --brief) -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz.tbi
	dx download $(dx find data --name "human_g1k_v37_decoy.fasta" --project $DX_RESOURCES_ID --folder /resources --brief) -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta
	dx download $(dx find data --name "human_g1k_v37_decoy.fasta.fai" --project $DX_RESOURCES_ID --folder /resources --brief) -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta.fai
	dx download $(dx find data --name "human_g1k_v37_decoy.dict" --project $DX_RESOURCES_ID --folder /resources --brief) -o /usr/share/GATK/resources/human_g1k_v37_decoy.dict
	
    TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
    # only ask for 90% of total system memory
    TOT_MEM=$((TOT_MEM * 9 / 10))
	VCF_TMPDIR=$(mktemp -d)
	# OK, now we can call the GATK genotypeGVCFs
	java -d64 -Xms512m -Xmx${TOT_MEM}m -XX:+UseSerialGC -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
	-T GenotypeGVCFs \
	-A QualByDepth \
	-A HaplotypeScore \
	-A MappingQualityRankSumTest \
	-A ReadPosRankSumTest \
	-A FisherStrand \
	-A GCContent \
	-A AlleleBalance \
	-A InbreedingCoeff \
	-A StrandOddsRatio \
	-A HardyWeinberg \
	-A ChromosomeCounts \
	-A VariantType \
	-A GenotypeSummaries $ADDL_CMD \
	-nt $(nproc --all) \
	-R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
	$(ls $OUTDIR/*.vcf.gz | sed 's/^/-V /' | tr '\n' ' ') \
	--dbsnp /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz \
	-o "$VCF_TMPDIR/$PREFIX.vcf.gz"
	  
    # Now, if we padded the intervals, get an on-target VCF through the use of SelectVariants
    if test "$PADDED" -ne 0; then
    	mv "$VCF_TMPDIR/$PREFIX.vcf.gz" "$VCF_TMPDIR/padded.$PREFIX.vcf.gz"
    	mv "$VCF_TMPDIR/$PREFIX.vcf.gz.tbi" "$VCF_TMPDIR/padded.$PREFIX.vcf.gz.tbi"
    
    	java -d64 -Xms512m -XX:+UseSerialGC -Xmx${TOT_MEM}m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants $(echo $ADDL_CMD | sed 's|^\(.*\)/[^/]*$|\1/targets.bed|') \
			-R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
			-nt $(nproc --all) \
			-V "$VCF_TMPDIR/padded.$PREFIX.vcf.gz" \
			-o "$VCF_TMPDIR/$PREFIX.vcf.gz" 
			
		# get only the 1st 8 (summary) columns - will be helpful when running VQSR or other variant-level information
		pigz -dc "$VCF_TMPDIR/padded.$PREFIX.vcf.gz" | cut -f1-8 | bgzip -c > "$VCF_TMPDIR/padded.header.$PREFIX.vcf.gz"
		tabix -p vcf "$VCF_TMPDIR/padded.header.$PREFIX.vcf.gz"
		
		# upload all of the padded files
		
		vcf_pad_fn=$(dx upload "$VCF_TMPDIR/padded.$PREFIX.vcf.gz" --brief)
	    vcf_idx_pad_fn=$(dx upload "$VCF_TMPDIR/padded.$PREFIX.vcf.gz.tbi" --brief)

		dx-jobutil-add-output vcf_pad_out "$vcf_pad_fn" --class=file
		dx-jobutil-add-output vcfidx_pad_out "$vcf_idx_pad_fn" --class=file
		
	   	vcf_pad_hdr_fn=$(dx upload "$VCF_TMPDIR/padded.header.$PREFIX.vcf.gz" --brief)
		vcf_idx_pad_hdr_fn=$(dx upload "$VCF_TMPDIR/padded.header.$PREFIX.vcf.gz.tbi" --brief)

		dx-jobutil-add-output vcf_pad_hdr_out "$vcf_pad_hdr_fn" --class=file
		dx-jobutil-add-output vcfidx_pad_hdr_out "$vcf_idx_pad_hdr_fn" --class=file
	fi
	  	
   	# get only the 1st 8 (summary) columns - will be helpful when running VQSR or other variant-level information
	pigz -dc "$VCF_TMPDIR/$PREFIX.vcf.gz" | cut -f1-8 | bgzip -c > "$VCF_TMPDIR/header.$PREFIX.vcf.gz"
	tabix -p vcf "$VCF_TMPDIR/header.$PREFIX.vcf.gz"	
	
	vcf_fn=$(dx upload "$VCF_TMPDIR/$PREFIX.vcf.gz" --brief)
    vcf_idx_fn=$(dx upload "$VCF_TMPDIR/$PREFIX.vcf.gz.tbi" --brief)

    dx-jobutil-add-output vcf_out "$vcf_fn" --class=file
    dx-jobutil-add-output vcfidx_out "$vcf_idx_fn" --class=file
    
   	vcf_hdr_fn=$(dx upload "$VCF_TMPDIR/header.$PREFIX.vcf.gz" --brief)
    vcf_idx_hdr_fn=$(dx upload "$VCF_TMPDIR/header.$PREFIX.vcf.gz.tbi" --brief)

    dx-jobutil-add-output vcf_hdr_out "$vcf_hdr_fn" --class=file
    dx-jobutil-add-output vcfidx_hdr_out "$vcf_idx_hdr_fn" --class=file


}
