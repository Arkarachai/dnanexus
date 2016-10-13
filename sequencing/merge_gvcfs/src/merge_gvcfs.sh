#!/bin/bash
# call_genotypes 0.0.1
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


# install GNU parallel!
#sudo sed -i 's/^# *\(deb .*backports.*\)$/\1/' /etc/apt/sources.list
sudo apt-get update
sudo apt-get install --yes parallel

if [ "$gatk_version" == "3.4-46" ]
then
	sudo apt-get install --yes openjdk-7-jre-headless
else
	echo "deb http://us.archive.ubuntu.com/ubuntu vivid main restricted universe multiverse " >> /etc/apt/sources.list
	sudo apt-get update
	sudo apt-get install --yes openjdk-8-jre-headless
fi

set -x

#mkfifo /LOG_SPLITTER
#stdbuf -oL tee /LOGS < /LOG_SPLITTER &

#splitter_pid=$!
#exec > /LOG_SPLITTER 2>&1

#save_logs() {
#	if test -f "$HOME/job_error.json" -a "$(cat $HOME/job_error.json | jq .error.type | sed 's/\"//g')" = "AppInternalError"; then
#	    dx upload --brief /LOGS --destination "${DX_PROJECT_CONTEXT_ID}:/${DX_JOB_ID}.log" >/dev/null
#   	echo "Full logs saved in ${DX_PROJECT_CONTEXT_ID}:/${DX_JOB_ID}.log"
#    fi
#}

#trap save_logs EXIT

function download_resources() {

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

		#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz" -o /usr/share/GATK/resources/dbsnp.vcf.gz
		#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_137.b37.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp.vcf.gz.tbi
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

			#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz" -o /usr/share/GATK/resources/dbsnp.vcf.gz
			#dx download "$DX_RESOURCES_ID:/GATK/resources/dbsnp_144.hg38.chr.vcf.gz.tbi"  -o /usr/share/GATK/resources/dbsnp.vcf.gz.tbi
			#dx download "$DX_RESOURCES_ID:/GATK/resources/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz" -o /usr/share/GATK/resources/Mills_and_1000G_gold_standard.indels.vcf.gz
		fi

	fi

}

function get_dxids() {
	dx describe "$1" --json | jq .id | sed 's/\"//g' >> $2
}
export -f get_dxids

function parallel_download() {
	#set -x
	cd $2
	dx download "$1"
	cd - >/dev/null
}
export -f parallel_download

function merge_gvcf() {
	#set -x
	f=$1

	WKDIR=$3
	CPWD="$PWD"
	cd $WKDIR

	GVCF_LIST=$(mktemp)

	TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
	N_PROC=$4
	ADDED_TBI=0

	while read dx_gvcf; do
		gvcf_fn=$(dx describe --name "$dx_gvcf")
		dx download "$dx_gvcf"

		if test "$(echo $gvcf_fn | grep '\.gz$')" -a -z "$(ls $gvcf_fn.tbi 2>/dev/null)"; then
			tabix -p vcf $gvcf_fn
			ADDED_TBI=1
		fi

		echo $PWD/$gvcf_fn >> $GVCF_LIST
	done < $f

	GATK_LOG=$(mktemp)
	java -d64 -Xms512m -Xmx$((TOT_MEM * 19 / (N_PROC * 20) ))m -XX:+UseSerialGC -jar /usr/share/GATK/GenomeAnalysisTK.jar \
	-T CombineGVCFs \
	-R /usr/share/GATK/resources/build.fasta \
	$(cat $GVCF_LIST | sed "s|^|-V |" | tr '\n' ' ') \
	-o "$f.vcf.gz" 2>$GATK_LOG

	if test "$?" -ne 0; then
		# Please add this to the list to be re-run
		echo $f >> $5
		echo "Error running GATK, log below:"
		cat $GATK_LOG
		rm $GATK_LOG
		sleep 5
		rm "$f.vcf.gz" || true
		rm "$f.vcf.gz.tbi" || true
	else
		echo "$f.vcf.gz" >> $2
	fi

	# clean up the working directory
	for tmpfn in $(cat $GVCF_LIST); do
		rm $tmpfn
		if test "$ADDED_TBI" -ne 0; then
			rm $tmpfn.tbi || true
		fi
	done

	rm $GVCF_LIST
	cd "$CPWD"
}
export -f merge_gvcf

function dl_index() {
	#set -x
	cd "$2"
	fn=$(dx describe --name "$1")
	dx download "$1" -o "$fn"
	if test -z "$(ls $fn.tbi)"; then
		tabix -p vcf $fn
	fi
	echo "$2/$fn" >> $3
}
export -f dl_index

function upload_files() {
	#set -x
	fn_list=$1

	VCF_TMPF=$(mktemp)
	VCFIDX_TMPF=$(mktemp)
	for f in $(cat $fn_list); do
		vcf_fn=$(dx upload --brief $f)
		echo $vcf_fn >> $VCF_TMPF
		vcfidx_fn=$(dx upload --brief $f.tbi)
		echo $vcfidx_fn >> $VCFIDX_TMPF
	done

	echo $VCF_TMPF >> $2
	echo $VCFIDX_TMPF >> $3
}

export -f upload_files

function dl_merge_interval() {
	set -x
	INTERVAL_FILE=$1

	# If we have no intervals, just exit
	if test "$(cat $INTERVAL_FILE | wc -l)" -eq 0; then
		exit 0
	fi

	#echo "Interval File Contents:"
	#cat $INTERVAL_FILE

	# $INTERVAL holds the overall interval from 1st to last
	INTERVAL="$(head -1 $INTERVAL_FILE | cut -f1-2 | tr '\t' '.')_$(tail -1 $INTERVAL_FILE | cut -f3)"
	if test "$(echo $INTERVAL | grep -v '\.')"; then
		#If we're here, we're parallelizing by chromosome, not by regions
		INTERVAL=$(head -1 $INTERVAL_FILE | cut -f1)
	fi
	echo "Interval: $INTERVAL"
	INTERVAL_STR="$(echo $INTERVAL | tr '.' ':' | tr '_' '-' | sed 's/[:-]*$//')"
	CHR="$(echo $INTERVAL | sed 's/\..*//')"
	DX_GVCF_FILES=$2
	INDEX_DIR=$3
	PREFIX=$4
	N_PROC=$5
	RERUN_FILE=$6

	IDX_NAMES=$(mktemp)
	ls $INDEX_DIR/*.tbi | sed -e 's|.*/\(.*\)\.tbi$|\1\t&|' | sort -k1,1 > $IDX_NAMES

	WKDIR=$(mktemp -d)
	cd $WKDIR

	set -o 'pipefail'

	GVCF_IDX_MAPPING=$(mktemp)
	# First, match up the GVCF to its index
	while read dxfn; do
		GVCF_NAME=$(dx describe --name "$dxfn")
		GVCF_DXID=$(dx describe --json "$dxfn" | jq -r .id)
		GVCF_BASE=$(echo "$GVCF_NAME" | sed 's/.vcf\.gz$//')
		GVCF_IDX=$(join -o '2.2' -j1 <(echo "$GVCF_NAME") $IDX_NAMES)


		#GVCF_URL=$(dx make_download_url "$dxfn")

		#GVCF_URL=$(dx describe --json "$dxfn" | jq .id | sed 's/"//g')
		# I had some issues w/ unsorted VCFs, so take a shortcus and sort by the
		# 2nd column - no need to sort on 1st, as these MUST all be on the
		# same chromosome
		RERUN=1
		MAX_RETRY=5
		while test $RERUN -ne 0 -a $MAX_RETRY -gt 0; do
			download_part.py -f "$GVCF_DXID" -i "$GVCF_IDX" -L "$INTERVAL_STR" -o $GVCF_BASE.$INTERVAL.vcf.gz -H
			RERUN="$?"
			MAX_RETRY=$((MAX_RETRY - 1))
		done

		# only do the tabix indexing if we succeeded.  This should cause a
		# failure downstream if an issue occurs
		if test $RERUN -eq 0; then
			tabix -p vcf $WKDIR/$GVCF_BASE.$INTERVAL.vcf.gz
		fi
	done < $DX_GVCF_FILES

	TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
	#N_PROC=$(nproc --all)

	GATK_LOG=$(mktemp)

	# Ask for 95% of total per-core memory
	java -d64 -Xms512m -Xmx$((TOT_MEM * 19 / (N_PROC * 20) ))m -XX:+UseSerialGC -jar /usr/share/GATK/GenomeAnalysisTK.jar \
	-T CombineGVCFs \
	-R /usr/share/GATK/resources/build.fasta -L $CHR\
	$(ls *.vcf.gz | sed "s|^|-V |" | tr '\n' ' ') \
	-o "$PREFIX.$INTERVAL.vcf.gz" 2>$GATK_LOG

	# If GATK failed for any reason, add this interval file to the re-run list
	if test "$?" -ne 0; then
		echo "GATK Failed: Log below"
		cat $GATK_LOG
		echo "$1" >> $RERUN_FILE
	fi

	# I need to clean up the working directory here - no longer needed!
	cd - >/dev/null
	rm -rf $WKDIR
}
export -f dl_merge_interval

function merge_intervals(){

	echo "Resources: $DX_RESOURCES_ID"

	# set the shell to work w/ GNU parallel
	export SHELL="/bin/bash"

	# arguments:
	# gvcfidxs - single file containing all gvcf indexes we MIGHT need, one per line
	# gvcfs - single file, containing all gvcfs
	# PREFIX - the prefix of the gvcf to use (final name will be $PREFIX.$CHR.vcf.gz)

	# I will have an array of files, each containing all of the gvcfs to merge
	# for a single chromosome

	# Also, I'll have a single file with all of the gvcfidxs created - just
	# download ALL of them, even if they don't apply!

	download_resources

	INDEX_DIR=$(mktemp -d)

	# download ALL of the indexes (in parallel!)
	GVCFIDX_FN=$(mktemp)
	for i in "${!gvcfidx[@]}"; do
		echo "${gvcfidx[$i]}"
	done > $GVCFIDX_FN

	dx download "$gvcfidxs" -f -o $GVCFIDX_FN
	parallel --gnu -j $(nproc --all) parallel_download :::: $GVCFIDX_FN ::: $INDEX_DIR

	# download the target file and the list of GVCFs
	TARGET_FILE=$(mktemp)
	dx download "$target" -f -o $TARGET_FILE

	GVCF_FN=$(mktemp)
	for i in "${!gvcf[@]}"; do
		echo "${gvcf[$i]}"
	done > $GVCF_FN
	#dx download "$gvcfs" -f -o $GVCF_FN

	# To reduce startup overhead of GATK, let's do multiple intervals at a time
	# This variable tells us to use $OVERSUB * $(nproc) different GATK runs
	SPLIT_DIR=$(mktemp -d)
	cd $SPLIT_DIR
	NPROC=$(nproc --all)

	# if we are given a list of intervals, "targeted" will be defined, o/w, we assume the target list will be by chromosome
	# and in that case, we only want one line per file
	if test "$targeted"; then
		# split the target files into the number of processors available
		split -a 2 -d -n l/$NPROC $TARGET_FILE "interval_split."
	else
		# if we have >1,000 chromosomes, we're in a bad way
		split -a 3 -d -l 1 $TARGET_FILE "interval_split."
	fi

	cd - >/dev/null
	MASTER_TARGET_LIST=$(mktemp)
	ls -1 $SPLIT_DIR/interval_split.* > $MASTER_TARGET_LIST

	# iterate over the intervals in TARGET_FILE, downloading only what is needed
	OUTDIR=$(mktemp -d)
	OUTDIR_PREF="$OUTDIR/$PREFIX"

	N_CHUNKS=$(cat $MASTER_TARGET_LIST | wc -l)
	RERUN_FILE=$(mktemp)
	N_RUNS=1
	N_CORES=$(nproc)
	N_JOBS=1

	# each run, we will decrease the number of cores available until we're at a single core at a time (using ALL the memory)
	while test $N_CHUNKS -gt 0 -a $N_JOBS -gt 0; do

		N_JOBS=$(echo "$N_CORES/2^($N_RUNS - 1)" | bc)
		# make sure we have a minimum of 1 job, please!
		N_JOBS=$((N_JOBS > 0 ? N_JOBS : 1))

		parallel --gnu -j $N_JOBS dl_merge_interval :::: $MASTER_TARGET_LIST ::: $GVCF_FN ::: $INDEX_DIR ::: $OUTDIR_PREF ::: $N_JOBS ::: $RERUN_FILE

		PREV_CHUNKS=$N_CHUNKS
		N_CHUNKS=$(cat $RERUN_FILE | wc -l)
		mv $RERUN_FILE $MASTER_TARGET_LIST
		RERUN_FILE=$(mktemp)
		N_RUNS=$((N_RUNS + 1))
		# just to make N_JOBS 0 at the conditional when we ran only a single job!
		N_JOBS=$((N_JOBS - 1))
	done

	# We need to be certain that nothing remains to be merged!
	if test "$N_CHUNKS" -ne 0; then
		dx-jobutil-report-error "ERROR: Could not merge one or more interval chunks; try an instance with more memory!"
	fi

	# No merging! just upload the pieces individually - we'll reassemble them later!
	if test -z "$targeted" ; then
		for f in $(ls $OUTDIR/*.vcf.gz); do
			VCF_OUT=$(dx upload $f --brief)
			VCFIDX_OUT=$(dx upload $f.tbi --brief)

			dx-jobutil-add-output vcf --array "$VCF_OUT"
			dx-jobutil-add-output vcfidx --array "$VCFIDX_OUT"

		done
	else
		# jk, we want to merge when working with targeted files
		NEW_OUTDIR=$(mktemp -d)

		# Note, since everything's on the same chromosome, we don't have to worry about mis-sorting, so no need for the custom jar
		TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
		java -d64 -Xms512m -Xmx$((TOT_MEM * 9 / 10))m  -cp /usr/share/GATK/GenomeAnalysisTK.jar org.broadinstitute.gatk.tools.CatVariants \
		    -R /usr/share/GATK/resources/build.fasta \
		    $(ls -1 $OUTDIR/*.vcf.gz | sed 's/^/-V /' | tr '\n' ' ') \
		    -out $NEW_OUTDIR/$PREFIX.vcf.gz

		VCF_OUT=$(dx upload $NEW_OUTDIR/$PREFIX.vcf.gz --brief)
		VCFIDX_OUT=$(dx upload $NEW_OUTDIR/$PREFIX.vcf.gz.tbi --brief)

		dx-jobutil-add-output vcf --array "$VCF_OUT"
		dx-jobutil-add-output vcfidx --array "$VCFIDX_OUT"

	fi


}

# entry point for merging into a single gVCF
function single_merge_subjob() {

	echo "Resources: $DX_RESOURCES_ID"

	# set the shell to work w/ GNU parallel
	export SHELL="/bin/bash"

	# If we are working with both GVCFs and their index files, let's break it up by interval
	# If no interval given, just break up by chromosome

	INTERVAL_LIST=$(mktemp)
	ORIG_INTERVALS=$(mktemp)
	SPLIT_DIR=$(mktemp -d)
	MERGE_ARGS=""

	JOB_ARGS=""
	for i in "${!gvcf[@]}"; do
		JOB_ARGS="$JOB_ARGS -igvcf='${gvcf[$i]}'"
	done

	for i in "${!gvcfidx[@]}"; do
		JOB_ARGS="$JOB_ARGS -igvcfidx='${gvcfidx[$i]}'"
	done
	
	# start setting up logging here
	set -x

	if test "$target"; then
		MERGE_ARGS="$MERGE_ARGS -itargeted:int=1"

		TARGET_FILE=$(mktemp)
		dx download "$target" -f -o $TARGET_FILE
		CHROM_LIST=$(mktemp)
		cut -f1 $TARGET_FILE  | sort -u > $CHROM_LIST
		# first, do the numeric chromosomes, in order
		for chr in $(grep '^[0-9]' $CHROM_LIST | sort -n); do
			grep "^$chr\W" $TARGET_FILE | interval_pad.py $padding | tr ' ' '\t' | sort -n -k2,3 >> $INTERVAL_LIST
		done

		# Now do the non-numeric chromosomes in order
		for chr in $(grep '^[^0-9]' $CHROM_LIST | sort); do
			grep "^$chr\W" $TARGET_FILE | interval_pad.py $padding | tr ' ' '\t' | sort -n -k2,3 >> $INTERVAL_LIST
		done

		rm $CHROM_LIST
		rm $TARGET_FILE

		# OK, now split the interval list into files of OVER_SUB * # proc
		cd $SPLIT_DIR
		NPROC=$(nproc --all)

		# Let's merge each chromosome independently.  merging sections of chroms
		# doesn't seem to be necessary for <5,000 samples
		for CHR in $(cut -f1 $INTERVAL_LIST | uniq); do
			CHR_LIST=$(mktemp)
			cat $INTERVAL_LIST | sed -n "/^$CHR[ \t].*/p" > $CHR_LIST
			int_fn=$(dx upload $CHR_LIST --brief)
			merge_jobid=$(dx-jobutil-new-job merge_intervals $MERGE_ARGS $JOB_ARGS -itarget:file="$int_fn" -iPREFIX:string="$PREFIX.$CHR" -iconcat:int=1)

			dx-jobutil-add-output gvcf --array "$merge_jobid:vcf" --class=jobref
			dx-jobutil-add-output gvcfidx --array "$merge_jobid:vcfidx" --class=jobref

			rm $CHR_LIST

		done

	else
		TMPWKDIR=$(mktemp -d)
		cd $TMPWKDIR
		idxfn=$(dx cat "$gvcfidxs" | head -1)
		vcf_name=$(dx describe --name "$idxfn" | sed 's/\.tbi$//')
		dx download "$idxfn"
		# get a list of chromosomes, but randomize
		tabix -l $vcf_name | shuf > $INTERVAL_LIST
		N_CHR=$(cat $INTERVAL_LIST | wc -l)
		cd -

		cd $SPLIT_DIR
		NPROC=$(nproc --all)

		N_BATCHES=$((N_CHR / (NPROC) + 1 ))

		split -a $(echo "scale=0; 1+l($N_BATCHES)/l(10)" | bc -l) -d -l $NPROC $INTERVAL_LIST "interval_split."
		CONCAT_ARGS=""
		for f in interval_split.*; do
			echo "interval file:"
			cat $f
			int_fn=$(dx upload $f --brief)
			# run a subjob that merges the input VCFs on the given target file
			merge_jobid=$(dx-jobutil-new-job merge_intervals $MERGE_ARGS $JOB_ARGS -itarget:file="$int_fn" -iPREFIX="$PREFIX" -iconcat:int=0)
			dx-jobutil-add-output gvcf --array "${merge_jobid}:vcf" --class=jobref
			dx-jobutil-add-output gvcfidx --array "${merge_jobid}:vcfidx" --class=jobref

		done

		rm -rf $TMPWKDIR
	fi
}

# entry point for merging VCFs
function merge_subjob() {

	echo "Resources: $DX_RESOURCES_ID"

	# set the shell to work w/ GNU parallel
	export SHELL="/bin/bash"

	# Get the prefix from the project, subbing _ for spaces
	if test -z "$PREFIX"; then
		PREFIX="$(dx describe --name $project | sed 's/  */_/g')"
	fi

	LIST_DIR=$(mktemp -d)

	N_BATCHES=$nbatch
	N_CORES=$(nproc --all)

	PREFIX="$PREFIX.$jobidx"

	download_resources

	GVCF_TMP=$(mktemp)
	GVCF_TMPDIR=$(mktemp -d)

	chmod a+rw $GVCF_TMP

	# we need to make the $LIST_DIR/GVCF_LIST and the GVCFIDX_LIST from the array input here
	for i in "${!gvcf[@]}"; do
		echo "${gvcf[$i]}"
	done > $LIST_DIR/GVCF_LIST

	DX_GVCFIDX_LIST=$(mktemp)
	for i in "${!gvcfidx[@]}"; do
		echo "${gvcfidx[$i]}"
	done > $DX_GVCFIDX_LIST

	parallel --gnu -j $(nproc --all) parallel_download :::: $DX_GVCFIDX_LIST ::: $GVCF_TMPDIR

	cd  $GVCF_TMPDIR
	GVCF_LIST_SHUF=$(mktemp)
	cat $LIST_DIR/GVCF_LIST | shuf  > $GVCF_LIST_SHUF
	split -a $(echo "scale=0; 1+l($N_BATCHES)/l(10)" | bc -l) -n r/$N_BATCHES -d $GVCF_LIST_SHUF "gvcflist."
	cd -

	chmod -R a+rwX $GVCF_TMPDIR

	TMP_GVCF_LIST=$(mktemp)
	ls -1 ${GVCF_TMPDIR}/gvcflist.* > $TMP_GVCF_LIST

	N_CHUNKS=$(cat $TMP_GVCF_LIST | wc -l)
	RERUN_FILE=$(mktemp)
	N_RUNS=1
	N_CORES=$(nproc)
	N_JOBS=1

	# each run, we will decrease the number of cores available until we're at a single core at a time (using ALL the memory)
	while test $N_CHUNKS -gt 0 -a $N_JOBS -gt 0; do

		N_JOBS=$(echo "$N_CORES/2^($N_RUNS - 1)" | bc)
		# make sure we have a minimum of 1 job, please!
		N_JOBS=$((N_JOBS > 0 ? N_JOBS : 1))

		parallel -u -j $N_JOBS --gnu merge_gvcf :::: $TMP_GVCF_LIST ::: $GVCF_TMP ::: $GVCF_TMPDIR ::: $N_JOBS ::: $RERUN_FILE

		PREV_CHUNKS=$N_CHUNKS
		N_CHUNKS=$(cat $RERUN_FILE | wc -l)
		mv $RERUN_FILE $TMP_GVCF_LIST
		RERUN_FILE=$(mktemp)
		N_RUNS=$((N_RUNS + 1))
		# just to make N_JOBS 0 at the conditional when we ran only a single job!
		N_JOBS=$((N_JOBS - 1))
	done

	# We need to be certain that nothing remains to be merged!
	if test "$N_CHUNKS" -ne 0; then
		dx-jobutil-report-error "ERROR: Could not merge one or more interval chunks; try an instance with more memory!"
	fi

	CIDX=1

	FINAL_DIR=$(mktemp -d)

	#GVCF_SORTED=$(mktemp)
	#sed -i 's|^.*/gvcflist\.\([^.]*\)\.vcf\.gz$|\1\t&|' $GVCF_TMP
	#sort -k1,1 -n $GVCF_TMP | cut -f2 > $GVCF_SORTED

	while read l; do
		mv "$l" ${FINAL_DIR}/$PREFIX.$CIDX.vcf.gz
		mv "$l.tbi" ${FINAL_DIR}/$PREFIX.$CIDX.vcf.gz.tbi

		VCF_DXFN=$(dx upload ${FINAL_DIR}/$PREFIX.$CIDX.vcf.gz --brief)
		VCFIDX_DXFN=$(dx upload ${FINAL_DIR}/$PREFIX.$CIDX.vcf.gz.tbi --brief)

		dx-jobutil-add-output gvcf_out "$VCF_DXFN" --array --class=file
		dx-jobutil-add-output gvcfidx_out "$VCFIDX_DXFN" --array --class=file

		CIDX=$((CIDX + 1))
	done < $GVCF_TMP
}


main() {

	if test -z "$project"; then
		project=$DX_PROJECT_CONTEXT_ID
	fi

	echo "Resources: $DX_RESOURCES_ID"

	export SHELL="/bin/bash"

    echo "Value of project: '$project'"
    echo "Value of folder: '$folder'"
	echo "Value of N_BATCHES: '$N_BATCHES'"

	N_GVCF="${#gvcfs[@]}"
    GVCF_LIST=$(mktemp)
   	JOINT_LIST=$(mktemp)
    GVCFIDX_LIST=$(mktemp)

    SUBJOB_ARGS=""
	if test "$N_GVCF" -gt 0 ; then

		# use the gvcf list provided
		for i in "${!gvcfs[@]}"; do
			dx describe --json "${gvcfs[$i]}" | jq -r '.name,.id' | tr '\n' '\t' | sed 's/\t$/\n/' >> $GVCF_LIST
		done

		# also, pass the gvcf index list as well!
		if test "${#gvcfidxs[@]}" -gt 0; then

			for i in "${!gvcfidxs[@]}"; do
				dx describe --json "${gvcfidxs[$i]}" | jq -r '.name,.id' | tr '\n' '\t' | sed -e 's/\t$/\n/' -e 's/\.tbi\t/\t/' >> $GVCFIDX_LIST
			done

			join -j1 -t$'\t' <(sort -k1,1 -t$'\t' $GVCF_LIST)  <(sort -k1,1 -t$'\t' $GVCFIDX_LIST) > $JOINT_LIST

			if test "$(cat $JOINT_LIST | wc -l)" -ne "$(cat $GVCF_LIST | wc -l)"; then
				dx-jobutil-report-error "ERROR: Number of gvcf files and tabix indexes do not match"
			fi

		fi

	elif test "$folder"; then
		FOLDER_LIST=$(mktemp)
		dx ls -l --delim $'\t' "$project:$folder" | cut -f4,5  > $FOLDER_LIST
		grep $'\.gz\t' $FOLDER_LIST > $GVCF_LIST
		grep $'\.gz\.tbi\t' $FOLDER_LIST | sed 's/\.tbi\t/\t/' > $GVCFIDX_LIST

		join -j1 -t$'\t' <(sort -k1,1 -t$'\t' $GVCF_LIST)  <(sort -k1,1 -t$'\t' $GVCFIDX_LIST) > $JOINT_LIST
		if test "$(cat $GVCFIDX_LIST | wc -l)" -gt 0 -a "$(cat $JOINT_LIST | wc -l)" -ne "$(cat $GVCF_LIST | wc -l)"; then
			dx-jobutil-report-error "ERROR: Number of gvcf files and tabix indexes do not match"
		fi
	else
		dx-jobutil-report-error "ERROR: you must provide either a list of gvcfs OR a directory containing gvcfs"
	fi

    if test "$target"; then
    	SUBJOB_ARGS="$SUBJOB_ARGS -itarget:file=$(dx describe --json "$target" | jq -r .id)"
    	if test "$padding"; then
    		SUBJOB_ARGS="$SUBJOB_ARGS -ipadding:int=$padding"
    	fi
    fi

    N_GVCF=$(cat $GVCF_LIST | wc -l)
    echo "# GVCF: $N_GVCF"

    if test $N_GVCF -le $N_BATCHES; then
    	dx-jobutil-report-error "ERROR: The number of input gVCFs is <= the number of requested output gVCFs, nothing to do!"
    fi

	# assume that the master instance will filter down to the children
   	N_CORE_SUBJOB=$(nproc --all)
    N_SUBJOB=$((N_BATCHES / N_CORE_SUBJOB))
    if test $N_SUBJOB -eq 0; then
    	# minimum of 1 subjob, please!
        N_SUBJOB=1
        N_CORE_SUBJOB=$N_BATCHES
    fi

    # move the special logic testing N_BATCHES==1 here
    if test "$split_merge" = "true" -a \( $N_BATCHES -eq 1 -o "$force_single" = "true" \) ; then

    	SPLIT_IN=$GVCF_LIST
    	IDX_GIVEN=0
    	if test "$(cat $JOINT_LIST | wc -l)" -gt 0; then
    		SPLIT_IN=$JOINT_LIST
    		IDX_GIVEN=1
    	fi

    	# split the gvcflist into the number of batches
    	SPLIT_DIR=$(mktemp -d)
    	split -a 3 -d -n r/$N_BATCHES $SPLIT_IN $SPLIT_DIR/gvcflist.

    	cd $SPLIT_DIR

    	FILE_DIR=$(mktemp -d)

    	for f in $(ls gvcflist.*); do


    		#cut -f2 $f > $FILE_DIR/$f
			#dx_gvcflist=$(dx upload $FILE_DIR/$f --brief)

			#if test $IDX_GIVEN -gt 0; then
			#	cut -f3 $f > $FILE_DIR/$f.idx
			#	dx_gvcfidxlist=$(dx upload $FILE_DIR/$f.idx --brief)
			#	JOB_ARGS="-igvcfidxs:file=$dx_gvcfidxlist"
			#fi

			JOB_ARGS=""
			while read l; do
				fn=$(echo "$l" | cut -f2)
				idxfn=$(echo "$l" | cut -f3)
				JOB_ARGS="$JOB_ARGS -igvcf:array:file=$fn -igvcfidx:array:file=$idxfn"
			done < $f

			single_job=$(dx-jobutil-new-job single_merge_subjob -iPREFIX="$PREFIX.$(echo $f | cut -d. -f2)" $JOB_ARGS $SUBJOB_ARGS)

			# If we wanted a single VCF, we now need to merge all of the output
			if test "$by_chrom" = "false"; then
				merge_subjob=$(dx run cat_variants -iprefix="$PREFIX" -ivcfidxs:array:file=${single_job}:gvcfidx -ivcfs:array:file=${single_job}:gvcf --brief)
				dx-jobutil-add-output vcf_fn --array "$merge_subjob:vcf_out" --class=jobref
				dx-jobutil-add-output vcf_idx_fn --array "$merge_subjob:vcfidx_out" --class=jobref
			else
				# and upload it and we're done!
				dx-jobutil-add-output vcf_fn --array "$single_job:gvcf" --class=jobref
				dx-jobutil-add-output vcf_idx_fn --array "$single_job:gvcfidx" --class=jobref
			fi

		done


    else

		GVCF_TMPDIR=$(mktemp -d)
		cd  $GVCF_TMPDIR
		SPLIT_IN_SHUF=$(mktemp)

    	SPLIT_IN=$GVCF_LIST
    	IDX_GIVEN=0
    	if test "$(cat $JOINT_LIST | wc -l)" -gt 0; then
    		SPLIT_IN=$JOINT_LIST
    		IDX_GIVEN=1
    	fi

		cat $SPLIT_IN | shuf > $SPLIT_IN_SHUF
		split -a $(echo "scale=0; 1+l($N_SUBJOB)/l(10)" | bc -l) -n l/$N_SUBJOB -d $SPLIT_IN_SHUF "gvcflist."

		CIDX=1
		# Now, kick off the subjobs for every file!
		FILE_DIR=$(mktemp -d)
		for f in $(ls -1 gvcflist.*); do

			FILE_ARGS=""
			while read l; do
				fn=$(echo "$l" | cut -f2)
				idxfn=$(echo "$l" | cut -f3)
				FILE_ARGS="$FILE_ARGS -igvcf:array:file=$fn -igvcfidx:array:file=$idxfn"
			done < $f

			# upload the gvcflist
	   		#cut -f2 $f > $FILE_DIR/$f
			#dx_gvcflist=$(dx upload $FILE_DIR/$f --brief)
			#JOB_ARGS=""
			#if test $IDX_GIVEN -gt 0; then
			#	cut -f3 $f > $FILE_DIR/$f.idx
			#	dx_gvcfidxlist=$(dx upload $FILE_DIR/$f.idx --brief)
			#	JOB_ARGS="-igvcfidxs:file=$dx_gvcfidxlist"
			#fi


			#GVCF_DXFN=$(dx upload $FILE_DIR/$f --brief)

			# start the sub-job with the project, folder and gvcf list

			subjob=$(dx-jobutil-new-job merge_subjob -iproject="$project" -ifolder="$folder" -iPREFIX="$PREFIX" -ijobidx=$CIDX -inbatch=$N_CORE_SUBJOB $FILE_ARGS $SUBJOB_ARGS)

			# the output of the subjob will be gvcfN and gvcfidxN, for N=1:#cores
			#for c in $(seq 1 $N_CORE_SUBJOB); do
			dx-jobutil-add-output vcf_fn --array "${subjob}:gvcf_out" --class=jobref
			dx-jobutil-add-output vcf_idx_fn --array "${subjob}:gvcfidx_out" --class=jobref
			#done

			CIDX=$((CIDX + 1))

			# reap the array of gvcf/gvcf_index and add it to the output of this job
		done

	fi
}
