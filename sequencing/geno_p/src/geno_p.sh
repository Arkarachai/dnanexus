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
#sudo sed -i 's/^# *\(deb .*backports.*\)$/\1/' /etc/apt/sources.list
#sudo apt-get update
#sudo apt-get install --yes parallel

if [ "$gatk_version" == "3.4-46" ]
then
	sudo apt-get install --yes openjdk-7-jre-headless
else
	echo "deb http://us.archive.ubuntu.com/ubuntu vivid main restricted universe multiverse " >> /etc/apt/sources.list
	sudo apt-get update
	sudo apt-get install --yes openjdk-8-jre-headless
fi

function parallel_download() {
	set -x
	cd $2
	dx download "$1"
	cd -
}
export -f parallel_download

#function parallel_name_dxid() {
#	dx describe --json "$1" | jq -r ".name,.id" | tr '\n' '\t' | sed 's/\t$/\n/' >> $2
#}
#export -f parallel_name_dxid

function dl_part_index() {
	set -x
	echo "'$1', '$2', '$3', '$4'"
	cd "$2"
	fn_id="$1"
	#$(dx describe --json "$1" | jq -r ".name,.id" | tr '\n' '\t' | sed 's/\t$//')

	fn=$(echo "$fn_id" | cut -f1)
	fn_base=$(echo "$fn" | sed 's/.vcf.gz$//')
	file_dxid=$(echo "$fn_id" | cut -f2 | jq -r '.["$dnanexus_link"]')
	idxfn=$(ls "$2/$fn.tbi")

	set -o 'pipefail'

	INTV="$(echo "$3" | tr ':-' '._')"

	RERUN=1
	MAX_RETRY=5
	while test $RERUN -ne 0 -a $MAX_RETRY -gt 0; do
		download_part.py -f "$file_dxid" -i "$idxfn" -L "$3" -o "$4/$fn_base.$INTV.vcf.gz" -H
		RERUN="$?"
		MAX_RETRY=$((MAX_RETRY - 1))
	done

	# Make sure to cause problems downstream if we didn't succeed
	if test "$RERUN" -eq 0; then
		tabix -p vcf "$4/$fn_base.$INTV.vcf.gz"
	fi
	cd -
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

	SUBJOB_ARGS="-igatk_version=$gatk_version -ibuild_version=$build_version"
	if test "$target_file"; then
		tgt_id=$(dx describe "$target_file" --json | jq -r .id )
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

    for i in "${!gvcfs[@]}"; do
		echo -e "${gvcfs_name[$i]}\t${gvcfs[$i]}"
	done > $VCF_ID_LIST
#	parallel -u -j $(nproc) --gnu parallel_name_dxid :::: $DXGVCF_LIST ::: $VCF_ID_LIST

	
	for i in "${!gvcfidxs[@]}"; do
		echo -e "${gvcfidxs_name[$i]}\t${gvcfidxs[$i]}"
	done > $VCFIDX_ID_LIST
#	parallel -u -j $(nproc) --gnu parallel_name_dxid :::: $DXGVCFIDX_LIST ::: $VCFIDX_ID_LIST

	# remove the tbi extension on the VCFIDX list
	sed -i 's/\.tbi\t/\t/' $VCFIDX_ID_LIST

	#OK, now join everything together
	JOINT_ID_LIST=$(mktemp)
	join -t$'\t' -j1 <(sort -t$'\t' -k1,1 $VCF_ID_LIST) <(sort -t$'\t' -k1,1 $VCFIDX_ID_LIST) > $JOINT_ID_LIST

	# sanity check, should have same # of lines!
	if test "$(cat $VCF_ID_LIST | wc -l)" -ne "$(cat $VCFIDX_ID_LIST | wc -l)" -o "$(cat $JOINT_ID_LIST | wc -l)" -ne "$(cat $VCF_ID_LIST | wc -l)"; then
		echo "Files in VCF list not in index list:"
		join -v1 -t$'\t' -j1 <(sort -k1,1 $VCF_ID_LIST) <(sort -k1,1 $VCFIDX_ID_LIST)
		echo "Files in VCF index list not in VCF list:"
		join -v2 -t$'\t' -j1 <(sort -k1,1 $VCF_ID_LIST) <(sort -k1,1 $VCFIDX_ID_LIST)
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
		join -t$'\t' -j1 <(sort -t$'\t' -k1,1 $CHR_FN_LIST) <(sort -t$'\t' -k1,1 $JOINT_ID_LIST) | cut -f2 > $SINGLE_VCF_LIST
		#SINGLE_VCFIDX_LIST=$(mktemp)
		#join -t$'\t' -j1 <(sort -t$'\t' -k1,1 $CHR_FN_LIST) <(sort -t$'\t' -k1,1 $JOINT_ID_LIST) | cut -f3 > $SINGLE_VCFIDX_LIST

		echo "CHR_FN_LIST":
		cat $CHR_FN_LIST
		
		echo "SINGLE_VCF_LIST:"
		cat $SINGLE_VCF_LIST

		echo "SINGLE_VCFIDX_LIST:"
		cat $SINGLE_VCFIDX_LIST
		
		# Create a tarball of the VCFidx files
		TARDIR=$(mktemp -d)
		cd $WKDIR
		while read f; do 
		    tar --append -f $TARDIR/gvcfidx.$chrom.tar $f.tbi
		done < $CHR_FN_LIST
		cd -
		
		DX_VCFIDX_TARBALL=$(dx upload --brief $TARDIR/gvcfidx.$chrom.tar $f.tbi)
		
	    DX_VCF_ARGS=""
		while read f; do
		    DX_VCF_ARGS="-ivcf_files:array:file='$f' $DX_VCF_ARGS"
		done < $SINGLE_VCF_LIST
		
		#DX_VCF_LIST=$(dx upload $SINGLE_VCF_LIST --brief)
		#DX_VCFIDX_LIST=$(dx upload $SINGLE_VCFIDX_LIST --brief)

        rm -rf $TARDIR
		rm $CHR_FN_LIST
		rm $SINGLE_VCF_LIST
		#rm $SINGLE_VCFIDX_LIST

		process_job=$(eval dx-jobutil-new-job genotype_gvcfs -iPREFIX=$PREFIX.$CHR -ichrom=$CHR "DX_VCF_ARGS" -ivcfidx_tarball:file="$DX_VCFIDX_TARBALL" "$SUBJOB_ARGS")
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
		TGT_FN="targets.bed"
		RAW_TGT_FN="$PWD/targets.bed"
		if test "$padding"; then
			cat targets.bed | interval_pad.py $padding | tr ' ' '\t' | sort -n -k2,3 > targets.padded.bed
			TGT_FN="targets.padded.bed"
			PADDED=1
		else
			padding=0
		fi

		ADDL_CMD="-L $PWD/$TGT_FN"

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
	TARDIR=$(mktemp -d)

    cd $TARDIR
   	dx download "${vcfidx_tarball}" -f -o vcfidx.tar	
   	tar -xf vcfidx.tar -C $WKDIR

	cd $WKDIR
	rm -rf $TARDIR

	#parallel -u -j $(nproc --all) --gnu parallel_download :::: $DXGVCFIDX_LIST ::: $WKDIR

	# Let's first check to ensure that we have enough room for the VCF sections, with 10% leftover
	# only really possible in a targeted analysis, as we're already broken down by chrom!
	N_JOBS=1


	INTERVAL="$chrom"

	if test "$target_file"; then
		bytes_avail=$(( 1024 * $( df | grep rootfs | awk '{print $4}' ) * 6 / 10 ))
		INTERVAL="$(head -1 $RAW_TGT_FN | cut -f1-2 | tr '\t' ':')-$(tail -1 $RAW_TGT_FN | cut -f3)"

		EST_SZ=0
		if test "$(echo $INTERVAL | grep ':')" -a "$(cat $RAW_TGT_FN | wc -l)" -gt 1; then
			#If we're here, we're parallelizing by regions and we have more than one
			for f in $(ls $WKDIR/*.vcf.gz.tbi); do
				EST_SZ=$(( EST_SZ + $(estimate_size.py -i $f -L $INTERVAL -H) ))
			done

			# get the numer of jobs needed here:
			N_JOBS=$((1 + EST_SZ / bytes_avail ))
		fi

		# If we have more than one job, we need to split the target file into the number of jobs
		# and then attempt to re-run this function
		if test $N_JOBS -gt 1; then

			# let's give a wider allowance for bytes_avail (70%)
			bytes_avail=$(( 1024 * $( df | grep rootfs | awk '{print $4}' ) * 5 / 10 ))
			N_JOBS=$((1 + EST_SZ / bytes_avail ))

			INTV_SPLIT_FN=$(mktemp)

			SPLIT_DIR=$(mktemp -d)

			cat $RAW_TGT_FN | interval_pad.py $padding $N_JOBS > $INTV_SPLIT_FN

			CONCAT_ARGS=""
			CONCAT_HDR_ARGS=""
			CONCAT_PAD_ARGS=""
			CONCAT_PAD_HDR_ARGS=""

			DX_VCF_LIST=$(dx describe --json "${vcf_files}" | jq -r .id)
			DX_VCFIDX_LIST=$(dx describe --json "${vcfidx_files}" | jq -r .id)

        	SUBJOB_ARGS="-igatk_version=$gatk_version -ibuild_version=$build_version"
			if test $PADDED -ne 0; then
				SUBJOB_ARGS="-ipadding:int=$padding"
			fi



			for n in $(cut -d: -f1 $INTV_SPLIT_FN | uniq); do
				grep "^$n:" $INTV_SPLIT_FN | cut -d: -f2 > "$SPLIT_DIR/target_split.$n.bed"

				echo "Split $n:"
				cat "$SPLIT_DIR/target_split.$n.bed"

				# and upload the file
				DX_TGT_FN=$(dx upload "$SPLIT_DIR/target_split.$n.bed" --brief)

				#start this section anew
				subchr_job=$(dx-jobutil-new-job genotype_gvcfs -isubchrom:string=true -iPREFIX=$PREFIX.$n -ichrom=$chrom -ivcfidx_tarball="${vcfidx_tarball}" -ivcf_files="${vcf_files}" -itarget_file:file=$DX_TGT_FN $SUBJOB_ARGS)

				# add the args to the concatenator
				CONCAT_ARGS="$CONCAT_ARGS -ivcfidxs:array:file=${subchr_job}:vcfidx_out -ivcfs:array:file=${subchr_job}:vcf_out"
				CONCAT_HDR_ARGS="$CONCAT_HDR_ARGS -ivcfidxs:array:file=${subchr_job}:vcfidx_hdr_out -ivcfs:array:file=${subchr_job}:vcf_hdr_out"

				if test $PADDED -ne 0; then
					CONCAT_PAD_ARGS="$CONCAT_PAD_ARGS -ivcfidxs:array:file=${subchr_job}:vcfidx_pad_out -ivcfs:array:file=${subchr_job}:vcf_pad_out"
					CONCAT_PAD_HDR_ARGS="$CONCAT_PAD_HDR_ARGS -ivcfidxs:array:file=${subchr_job}:vcfidx_pad_hdr_out -ivcfs:array:file=${subchr_job}:vcf_pad_hdr_out"
				fi

			done

			# OK, now start a concatenation job (or 4)
			cat_job=$(dx run cat_variants -iprefix="$PREFIX" $CONCAT_ARGS --brief --instance-type mem2_hdd2_x2)
			cat_hdr_job=$( dx run cat_variants -iprefix="header.$PREFIX" $CONCAT_HDR_ARGS --brief --instance-type mem1_ssd1_x2)

			# add those to our output
			dx-jobutil-add-output vcf_out --array "$cat_job:vcf_out" --class=jobref
			dx-jobutil-add-output vcfidx_out --array "$cat_job:vcfidx_out" --class=jobref
			dx-jobutil-add-output vcf_hdr_out --array "$cat_hdr_job:vcf_out" --class=jobref
			dx-jobutil-add-output vcfidx_hdr_out --array "$cat_hdr_job:vcfidx_out" --class=jobref


			if test $PADDED -ne 0; then
				cat_pad_job=$(dx run cat_variants -iprefix="padded.$PREFIX" $CONCAT_PAD_ARGS --brief --instance-type mem2_hdd2_x2)
				cat_pad_hdr_job=$(dx run cat_variants -iprefix="padded.header.$PREFIX" $CONCAT_PAD_HDR_ARGS --brief --instance-type mem1_ssd1_x2)

				dx-jobutil-add-output vcf_pad_out --array "$cat_pad_job:vcf_out" --class=jobref
				dx-jobutil-add-output vcfidx_pad_out --array "$cat_pad_job:vcfidx_out" --class=jobref
				dx-jobutil-add-output vcf_pad_hdr_out --array "$cat_pad_hdr_job:vcf_out" --class=jobref
				dx-jobutil-add-output vcfidx_pad_hdr_out --array "$cat_pad_hdr_job:vcfidx_out" --class=jobref

			fi
		fi
	fi

	# if N_JOBS > 1, we're already done (run in a subjob)
	if test $N_JOBS -eq 1; then
	
	    for i in "${!vcf_files[@]}"; do
    		echo -e "${vcf_files_name[$i]}\t${vcf_files[$i]}"
	    done > $DXGVCF_LIST
		#dx download "${vcf_files}" -f -o $DXGVCF_LIST

		TODL=$chrom
		if test "$subchrom"; then
			TODL=$INTERVAL
		fi

		# Now, download and index in parallel, please
		parallel -u -j $(nproc --all) --gnu dl_part_index :::: $DXGVCF_LIST ::: $WKDIR ::: $TODL ::: $OUTDIR

		echo "Contents of WKDIR:"
		ls -alh $WKDIR

		echo "Contents of OUTDIR:"
		ls -alh $OUTDIR

		# get the resources we need in /usr/share/GATK
		sudo mkdir -p /usr/share/GATK/resources
		sudo chmod -R a+rwX /usr/share/GATK

		#dx download "$DX_RESOURCES_ID:/GATK/jar/GenomeAnalysisTK-3.4-46.jar" -o /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar
		#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta
		#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta.fai" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta.fai
		#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.dict" -o /usr/share/GATK/resources/human_g1k_v37_decoy.dict

		#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz" -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz
		#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz.tbi

		if [ "$gatk_version" == "3.4-46" ]
		then
			dx download "$DX_RESOURCES_ID:/GATK/jar/GenomeAnalysisTK-3.4-46.jar" -o /usr/share/GATK/GenomeAnalysisTK.jar
		else
			dx download "$DX_RESOURCES_ID:/GATK/jar/GenomeAnalysisTK-3.6.jar" -o /usr/share/GATK/GenomeAnalysisTK.jar
		fi

		if [ "$build_version" == "b37_decoy" ]
		then
			dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta" -o /usr/share/GATK/resources/build.fasta
			dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta.fai" -o /usr/share/GATK/resources/build.fasta.fai
			dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.dict" -o /usr/share/GATK/resources/build.dict

			dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz" -o /usr/share/GATK/resources/dbsnp.vcf.gz
			dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp.vcf.gz.tbi

		else
			if [ "$gatk_version" == "3.4-46" ]
			then
				dx-jobutil-report-error "GATK verison 3.4-46 will not run b38!"
				echo "ERROR!"
				echo "ERROR!"
				echo "GATK verison 3.4-46 will not run b38"
				echo "ERROR!"
				echo "ERROR!"
				exit
			else
				dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.fa" -o /usr/share/GATK/resources/build.fasta
				dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.fa.fai" -o /usr/share/GATK/resources/build.fasta.fai
				dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.dict" -o /usr/share/GATK/resources/build.dict

				dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz" -o /usr/share/GATK/resources/dbsnp.vcf.gz
				dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp.vcf.gz.tbi

			fi

		fi

		TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
		# only ask for 90% of total system memory
		TOT_MEM=$((TOT_MEM * 9 / 10))
		VCF_TMPDIR=$(mktemp -d)
		# OK, now we can call the GATK genotypeGVCFs
		java -d64 -Xms512m -Xmx${TOT_MEM}m -XX:+UseSerialGC -jar /usr/share/GATK/GenomeAnalysisTK.jar \
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
		-R /usr/share/GATK/resources/build.fasta \
		$(ls $OUTDIR/*.vcf.gz | sed 's/^/-V /' | tr '\n' ' ') \
		--dbsnp /usr/share/GATK/resources/dbsnp.vcf.gz \
		-o "$VCF_TMPDIR/$PREFIX.vcf.gz"

		# Now, if we padded the intervals, get an on-target VCF through the use of SelectVariants
		if test "$PADDED" -ne 0; then
			mv "$VCF_TMPDIR/$PREFIX.vcf.gz" "$VCF_TMPDIR/padded.$PREFIX.vcf.gz"
			mv "$VCF_TMPDIR/$PREFIX.vcf.gz.tbi" "$VCF_TMPDIR/padded.$PREFIX.vcf.gz.tbi"

			java -d64 -Xms512m -XX:+UseSerialGC -Xmx${TOT_MEM}m -jar /usr/share/GATK/GenomeAnalysisTK.jar \
				-T SelectVariants $(echo $ADDL_CMD | sed 's|^\(.*\)/[^/]*$|\1/targets.bed|') \
				-R /usr/share/GATK/resources/build.fasta \
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

	fi

}
