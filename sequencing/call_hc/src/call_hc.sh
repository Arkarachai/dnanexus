#!/bin/bash
# call_hc 0.0.1
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
DX_RESOURCES_ID='project-BYpFk1Q0pB0xzQY8ZxgJFv1V'

set -x

# install GNU parallel!
#sudo sed -i 's/^# *\(deb .*backports.*\)$/\1/' /etc/apt/sources.list
sudo apt-get update
sudo apt-get install --yes parallel

# GATK 3.4 requires java-7, GATK 3.6 requires java-8
# Deleted from json:       { "name": "openjdk-7-jre-headless" },
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

function call_hc(){

	set -x

	bam_in=$1
	WKDIR=$2
	OUTDIR=$3
	N_PROC=$6
	RERUN_FILE=$7
	TARGET_FN=$8
	TARGET_CMD=""
	if test "$TARGET_FN"; then
		TARGET_CMD="-L $TARGET_FN"
	fi

	TOT_MEM=$(free -k | grep "Mem" | awk '{print $2}')
	#N_PROC=$(nproc --all)

	cd $WKDIR

	fn_base="$(echo $bam_in | sed -e 's/\.bam$//' -e 's|.*/||')"

	# If I don't have the bam_in, it must be on DNANexus...
	if test -z "$(ls $bam_in)"; then
		# get the bam
		fn_base=$(dx describe --name "$bam_in" | sed 's/\.bam$//')
		dx download "$bam_in" -o $fn_base.bam
	fi

	# if the index doesn't exist, create it
	if test -z "$(ls $fn_base.bai)"; then
		samtools index $fn_base.bam $fn_base.bai
	fi

	# If we have a BQSR table for this BAM, assume we want to apply BQSR
	BQSR_CMD=""
	if test "$(ls $fn_base.table)"; then
		BQSR_CMD="-BQSR $fn_base.table"
	fi

	LOG_FN=$(mktemp)

	# run HC to get a gVCF
	java -d64 -Xms512m -Xmx$((TOT_MEM * 19 / (N_PROC * 20) ))k -jar  /usr/share/GATK/GenomeAnalysisTK.jar \
	-T HaplotypeCaller \
	-R /usr/share/GATK/resources/build.fasta \
	--dbsnp /usr/share/GATK/resources/dbsnp.vcf.gz $TARGET_CMD $BQSR_CMD \
	-A AlleleBalanceBySample \
	-I $fn_base.bam \
	-o "${OUTDIR}/${fn_base}.g.vcf.gz" \
	-stand_call_conf 30.0 \
	-stand_emit_conf 10.0 \
	-ERC GVCF \
	-pairHMM VECTOR_LOGLESS_CACHING \
	-variant_index_type LINEAR \
	-variant_index_parameter 128000 >$LOG_FN 2>&1

	if test "$?" -eq 0; then
		# upload the results and put the resultant dx IDs into a file
		VCF_DXFN=$(dx upload "${OUTDIR}/${fn_base}.g.vcf.gz" --brief)
		echo "$VCF_DXFN" >> $4
		VCFIDX_DXFN=$(dx upload "${OUTDIR}/${fn_base}.g.vcf.gz.tbi" --brief)
		echo "$VCFIDX_DXFN" >> $5
	else
		echo "Error running sample ${fn_base} with $N_PROC simultaneous jobs" | dx-log-stream -l critical -s DX_APP
		echo "Error Running HaplotypeCaller, log follows"
		cat $LOG_FN
		echo "$bam_in" >> $RERUN_FILE
	fi

	# Go ahead and delete the BAM file to save space - we're done with it!
	rm $fn_base.bam

}

export -f call_hc

main() {

	# set the shell to work w/ GNU parallel
	export SHELL="/bin/bash"

    echo "Value of bam: '$bam'"
    echo "Value of bam_idx: '$bam_idx'"
    echo "Value of target: '$target'"

    # The following line(s) use the dx command-line tool to download your file
    # inputs to the local file system using variable names for the filenames. To
    # recover the original filenames, you can use the output of "dx describe
    # "$variable" --name".

    TARGET_FN=""

    if [ -n "$target" ]; then
    	TARGET_FN="$PWD/target.bed"
    	dx download "$target" -o target.bed
        if [ -n "$padding" ] && [ "$padding" -ne 0 ]; then
			cat target.bed | interval_pad.py $padding | tr ' ' '\t' > target.padded.bed
			TARGET_FN="$PWD/target.padded.bed"
		fi
    fi

	WKDIR=$(mktemp -d)
	OUTDIR=$(mktemp -d)
	DXBAM_LIST=$(mktemp)
	DXBAI_LIST=$(mktemp)
	DXBQSR_LIST=$(mktemp)
	DX_VCF_LIST=$(mktemp)
	DX_VCFIDX_LIST=$(mktemp)

	cd $WKDIR

	# Download all of the BAM index files (in parallel)
	for i in "${!bam_idx[@]}"; do
		echo "${bam_idx[$i]}" >> $DXBAI_LIST
	done

	parallel -j $(nproc --all) -u --gnu parallel_download :::: $DXBAI_LIST ::: $WKDIR

	# Ensure that the index for "foo.bam" is named "foo.bai" instead of "foo.bam.bai"
	for f in $(ls *.bai); do
		mv $f $(echo $f | sed 's/\.ba\(m\.ba\)*i$/.bai/') || true
	done

	# Download all of the BQSR tables (in parallel)
	for i in "${!bqsr_table[@]}"; do
		echo "${bqsr_table[$i]}" >> $DXBQSR_LIST
	done

	parallel -j $(nproc --all) -u --gnu parallel_download :::: $DXBQSR_LIST ::: $WKDIR

	# Get a list of the BAM files - we'll download them when calling the HC
	for i in "${!bam[@]}"; do
		echo "${bam[$i]}" >> $DXBAM_LIST
	done

	# get the resources we need in /usr/share/GATK
	sudo mkdir -p /usr/share/GATK/resources
	sudo chmod -R a+rwX /usr/share/GATK

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
		#dx download "$DX_RESOURCES_ID:/GATK/resources/Mills_and_1000G_gold_standard.indels.b37.vcf.gz" -o /usr/share/GATK/resources/Mills_and_1000G_gold_standard.indels.vcf.gz
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
			exit
		else
			dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.fa" -o /usr/share/GATK/resources/build.fasta
			dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.fa.fai" -o /usr/share/GATK/resources/build.fasta.fai
			dx download "$DX_RESOURCES_ID:/GATK/resources/h38flat.fasta-index.tar.gz.genome.dict" -o /usr/share/GATK/resources/build.dict

			dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz" -o /usr/share/GATK/resources/dbsnp.vcf.gz
			dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp.vcf.gz.tbi
			#dx download "$DX_RESOURCES_ID:/GATK/resources/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz" -o /usr/share/GATK/resources/Mills_and_1000G_gold_standard.indels.vcf.gz
		fi

	fi

	#dx download "$DX_RESOURCES_ID:/GATK/jar/GenomeAnalysisTK-3.4-46.jar" -o /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar
	#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta
	#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta.fai" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta.fai
	#dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.dict" -o /usr/share/GATK/resources/human_g1k_v37_decoy.dict

	#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz" -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz
	#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp_137.b37.vcf.gz.tbi

	N_CHUNKS=$(cat $DXBAM_LIST | wc -l)
	RERUN_FILE=$(mktemp)
	N_RUNS=1
	N_CORES=$(nproc)
	N_JOBS=1

	# each run, we will decrease the number of cores available until we're at a single core at a time (using ALL the memory)
	while test $N_CHUNKS -gt 0 -a $N_JOBS -gt 0; do

		N_JOBS=$(echo "$N_CORES/2^($N_RUNS - 1)" | bc)
		# make sure we have a minimum of 1 job, please!
		N_JOBS=$((N_JOBS > 0 ? N_JOBS : 1))

		parallel -j $N_JOBS -u --gnu call_hc :::: $DXBAM_LIST ::: $WKDIR ::: $OUTDIR ::: $DX_VCF_LIST ::: $DX_VCFIDX_LIST ::: $N_JOBS ::: $RERUN_FILE ::: $TARGET_FN

		#parallel -j $N_JOBS -u --gnu call_bqsr :::: $DXBAM_LIST ::: $WKDIR ::: $DX_BQSR_LIST ::: $N_JOBS ::: $RERUN_FILE ::: $TARGET_FN ::: $padding

		PREV_CHUNKS=$N_CHUNKS
		N_CHUNKS=$(cat $RERUN_FILE | wc -l)
		mv $RERUN_FILE $DXBAM_LIST
		RERUN_FILE=$(mktemp)
		N_RUNS=$((N_RUNS + 1))
		# just to make N_JOBS 0 at the conditional when we ran only a single job!
		N_JOBS=$((N_JOBS - 1))
	done

	if test $N_CHUNKS -ne 0; then
		echo "WARNING: Some samples not called, see CRITICAL log for details" | dx-log-stream -l critical -s DX_APP
	fi

	while read vcf_fn; do
		dx-jobutil-add-output vcf_fn "$vcf_fn" --class=array:file
	done < $DX_VCF_LIST

	while read vcfidx_fn; do
	    dx-jobutil-add-output vcfidx_fn "$vcfidx_fn" --class=array:file
	done <$DX_VCFIDX_LIST
}
