#!/bin/bash
# vcf_concordance 0.0.1
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

function download_resources() {

	# get the resources we need in /usr/share/GATK
	sudo mkdir -p /usr/share/GATK/resources
	sudo chmod -R a+rwX /usr/share/GATK

		
	dx download "$DX_RESOURCES_ID:/GATK/jar/GenomeAnalysisTK-3.4-46.jar" -o /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar
	dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta
	dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.fasta.fai" -o /usr/share/GATK/resources/human_g1k_v37_decoy.fasta.fai
	dx download "$DX_RESOURCES_ID:/GATK/resources/human_g1k_v37_decoy.dict" -o /usr/share/GATK/resources/human_g1k_v37_decoy.dict
	
}

function renameVCFIDs() {

	OLD_VCF_FILE="$1"
	if [ -z "$3" ]; then
		NEW_VCF_FILE="$(echo $OLD_VCF_FILE | sed 's/\.vcf\.gz$/.renamed.vcf.gz/')"
	else
		NEW_VCF_FILE="$3" 
	fi

	# File of id -> new id (tab separated)
	ID_TRANS="$2"

	vcf_header=$(mktemp)
	vcf_newheader=$(mktemp)

	id_t=$(mktemp)
	if [ -n "$UNIQUE" ] && [ "$UNIQUE" -ne 0 ]; then
		cat $ID_TRANS | sort -k 2,2 -u > $id_t
	else
		cat $ID_TRANS > $id_t
	fi

	#cut -f1 $id_t

	# We should filter the VCF to include only those IDs in the idlist
	zcat "$OLD_VCF_FILE" | head -5000 | grep -E '^#' > $vcf_header
	# In this case, we need to filter
	if test $(join -1 2 -2 1 <(grep '#CHROM' $vcf_header | cut -f10- | tr '\t' '\n' | grep -n '.' | tr ':' '\t' | sort -k2) <(cat "$id_t" | sort) | wc -l) -ne $(grep '#CHROM' $vcf_header | cut -f10- | tr '\t' '\n' | wc -l); then
		echo "Filtering VCF..."

		TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')
		vcf_filtered="$(mktemp).vcf.gz"
		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar GenomeAnalysisTK-3.4-46.jar -T SelectVariants -R  /usr/share/GATK/resources/human_g1k_v37_decoy.fasta -V $OLD_VCF_FILE --sample_file <(cut -f1 $id_t) -o $vcf_filtered -nt 4
		tabix -p vcf $vcf_filtered
		OLD_VCF_FILE=$vcf_filtered
		zcat "$OLD_VCF_FILE" | head -5000 | grep -E '^#' > $vcf_header
	fi

	cat <(grep -Ev '#CHROM' $vcf_header) <(paste <(echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT") <(join -1 2 -2 1 <(grep '#CHROM' $vcf_header | cut -f10- | tr '\t' '\n' | grep -n '.' | tr ':' '\t' | sort -k2) <(cat "$id_t" | sort) | tr ' ' '\t' | sort -g -k2,2 | cut -f 3 | tr '\n' '\t' | sed 's/\t$//') ) > $vcf_newheader

	if test "$(tail -1 $vcf_header | tr '\t' '\n' | wc -l)" -ne "$(tail -1 $vcf_newheader | tr '\t' '\n' | wc -l)"; then
		echo "Some columns not mapped.. exiting"
		exit
	fi

	tabix -r $vcf_newheader "$OLD_VCF_FILE" > "$NEW_VCF_FILE"
	tabix -p vcf "$NEW_VCF_FILE"

	rm $vcf_header
	rm $vcf_newheader
	rm $id_t

	if test ! -z "$vcf_filtered"; then
		rm $vcf_filtered
		rm $vcf_filtered.tbi
	fi
}

function calc_NRS(){
	echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$17+$22+$23)/($10+$11+$16+$17+$22+$23+$4+$5+$28+$29)}' 2>/dev/null
}	

function calc_NRS_Reverse(){
	echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$17+$22+$23)/($15+$21+$16+$17+$22+$23+$14+$20+$18+$24)}' 2>/dev/null
}

function calc_NRD(){
	 echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print (1-($23+$16)/($10+$11+$15+$16+$17+$21+$22+$23))}' 2>/dev/null
}

function calc_OGC(){
	echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($9+$16+$23)/($9+$10+$11+$15+$16+$17+$21+$22+$23)}' 2>/dev/null
}	

function calc_OGCM(){
	echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($9+$16+$23+$2)/($9+$10+$11+$8+$15+$16+$17+$14+$21+$22+$23+$20+$3+$4+$5+$2)}' 2>/dev/null
}

function calc_OGCMU(){
	echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($9+$16+$23+$2+$30+$26+$6)/($9+$10+$11+$8+$12+$15+$16+$17+$14+$18+$21+$22+$23+$20+$24+$3+$4+$5+$2+$6+$27+$28+$29+$26+$30)}' 2>/dev/null
}

function calc_HETHET(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16)/($16+$17+$10+$22+$15)}' 2>/dev/null
}

function calc_HETMissing(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16)/($15+$16+$17+$14+$10+$22+$4)}' 2>/dev/null
}

function calc_NRC(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$23)/($15+$16+$17+$21+$22+$23)} ' 2>/dev/null
}

function calc_RNRC(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$23)/($10+$11+$16+$17+$22+$23)} ' 2>/dev/null
}

function calc_Recall(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$23)/($10+$11+$16+$17+$22+$23+$4+$5+$28+$29)} ' 2>/dev/null
}

function calc_RevRecall(){
        echo $1 | awk 'BEGIN{OFMT = "%.5f"} { print ($16+$23)/($15+$21+$16+$17+$22+$23+$14+$20+$18+$24)} ' 2>/dev/null
}
function print_stats(){
	paste <(calc_NRS "$1") <(calc_NRS_Reverse "$1") <(calc_NRD "$1") <(calc_OGC "$1") <(calc_OGCM "$1") <(calc_OGCMU "$1") <(calc_HETHET "$1") <(calc_HETMissing "$1") <(calc_NRC "$1") <(calc_RNRC "$1") <(calc_Recall "$1") <(calc_RevRecall "$1")
}


main() {

    echo "Value of vcf1: '$vcf1'"
    echo "Value of vcf1_idx: '$vcf1_idx'"
    echo "Value of vcf2: '$vcf2'"
    echo "Value of vcf2_idx: '$vcf2_idx'"
    echo "Value of id_mapping: '$id_mapping'"
    echo "Value of PREFIX: '$PREFIX'"

    # The following line(s) use the dx command-line tool to download your file
    # inputs to the local file system using variable names for the filenames. To
    # recover the original filenames, you can use the output of "dx describe
    # "$variable" --name".

	INPUTDIR=$(mktemp -d)
	cd $INPUTDIR

	if test -n "$vcf2" -a -z "$vcf2_idx"; then
		dx-jobutil-report-error "ERROR: If Truth VCF is given, a tabix index must be provided"
	fi
	
	
	dx download "$vcf1"
	dx download "$vcf1_idx"
    
	INPUT1_NAME=$(dx describe --name "$vcf1")
    
    
    CAT1_CMD="cat"
	if test "$(echo $INPUT1_NAME | grep '.gz$')"; then
		CAT1_CMD="zcat"
	fi

	INPUT2_NAME="id_mapping.txt"
    if [ -n "$vcf2" ]; then
   		INPUT2_NAME=$(dx describe --name "$vcf2")
        dx download "$vcf2"
      	dx download "$vcf2_idx"
    elif [ -n "$id_mapping" ]; then
        dx download "$id_mapping" -o id_mapping.txt
    else
    	# OK, here attempt to create the GHS_PTN_M -> PT_N mapping dynamically
    	$CAT1_CMD $INPUTDIR/$INPUT1_NAME | head -5000 | grep '#CHROM' | cut -f10- | tr '\t' '\n' | sed 's/^GHS_\([^_]*\)_.*/&\t\1/' > id_mapping.txt
    	
    	if test $(cat id_mapping.txt | wc -l) -eq 0; then
    		dx-jobutil-report-error "ERROR: Could not dynamically determine identity mapping, and none provided.  Cannot continue!"
    	fi
    fi

	download_resources
	
	# OK, at this point I have VCF1.vcf.gz and either an ID mapping OR a second 
	# VCF, which is in "$INPUT2_NAME"
		
	CAT_CMD="cat"
	if test "$(echo $INPUT2_NAME | grep '.gz$')"; then
		CAT_CMD="zcat"
	fi

	# create an empty working directory and go there
	WKDIR=$(mktemp -d)
	cd $WKDIR

	ID_LIST_ALL=$(mktemp)

	PARALLEL_ARGS="-nt $(nproc --all)"
	TOT_MEM=$(free -m | grep "Mem" | awk '{print $2}')

	if test "$($CAT_CMD $INPUTDIR/$INPUT2_NAME | head -1 | grep '^##fileformat=VCF')"; then
		ID_LIST1=$(mktemp)
		ID_LIST2=$(mktemp)
	
		$CAT1_CMD $INPUTDIR/$INPUT1_NAME | head -5000 | grep '^#CHR' | cut -f10- | tr '\t' '\n' | sort > $ID_LIST1
		$CAT_CMD $INPUTDIR/$INPUT2_NAME | head -5000 | grep '^#CHR' | cut -f10- | tr '\t' '\n' | sort > $ID_LIST2
	
		join $ID_LIST1 $ID_LIST2 > $ID_LIST_ALL
	
		if test $(cat $ID_LIST_ALL | wc -l) -eq 0; then
			dx-jobutil-report-error "ERROR: No overlapping samples, nothing to compare!!"
		fi
	
	
		# at this point, we need to subset our 2 VCFs to only overlapping IDs

		#TODO: only perform this step if we really, truly NEED to!
		# Now, let's SelectVariants up in here!
		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta $PARALLEL_ARGS \
			-V $INPUTDIR/$INPUT1_NAME -sf $ID_LIST_ALL -o VCF1.renamed.vcf.gz

		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta $PARALLEL_ARGS \
			-V $INPUTDIR/$INPUT2_NAME -sf $ID_LIST_ALL -o VCF2.renamed.vcf.gz

		rm $ID_LIST1
		rm $ID_LIST2

	else
		# First, let's get a listing of all IDs that are duplicated
		$CAT_CMD $INPUTDIR/$INPUT2_NAME | cut -f2 | sort | uniq -d > $ID_LIST_ALL
		if test $(cat $ID_LIST_ALL | wc -l) -eq 0; then
			dx-jobutil-report-error "ERROR: No duplicated samples, nothing to compare!!"
		fi
	
		ID_LIST1=$(mktemp)
		ID_LIST2=$(mktemp)
	
		# This command selects one duplicate to go to stderr and one to stdout (the shuf combined w/ stable sort randomizes it!)
		$CAT_CMD $INPUTDIR/$INPUT2_NAME | shuf | sort -k2,2 -s | uniq -f1 -d -D | awk 'BEGIN {pv=""; nl=0;} {if($2!=pv){print $0; pv=$2; nl=1;}else if(nl==1){print $0 > "/dev/stderr"; nl=0;}}' >$ID_LIST1 2>$ID_LIST2
	
		ORIG_IDLIST1=$(mktemp)
		cut -f1 $ID_LIST1 > $ORIG_IDLIST1
	
		ORIG_IDLIST2=$(mktemp)
		cut -f1 $ID_LIST2 > $ORIG_IDLIST2
		
		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta $PARALLEL_ARGS \
			-V $INPUTDIR/$INPUT1_NAME -sf <(cat $ORIG_IDLIST1 $ORIG_IDLIST2) -o combined_orig.vcf.gz	
	
		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta $PARALLEL_ARGS \
			-V combined_orig.vcf.gz -sf $ORIG_IDLIST1 -o VCF1_orig.vcf.gz

		java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
			-T SelectVariants -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta $PARALLEL_ARGS \
			-V combined_orig.vcf.gz -sf $ORIG_IDLIST2 -o VCF2_orig.vcf.gz

		renameVCFIDs "$WKDIR/VCF1_orig.vcf.gz" "$ID_LIST1" "$WKDIR/VCF1.renamed.vcf.gz"
		renameVCFIDs "$WKDIR/VCF2_orig.vcf.gz" "$ID_LIST2" "$WKDIR/VCF2.renamed.vcf.gz"
	
		rm $ID_LIST1
		rm $ID_LIST2
		rm $ORIG_IDLIST1
		rm $ORIG_IDLIST2

	fi

	#RUN GATK GENOTYPE CONCORDANCE ALL
	#GATK Genotype Concordance (raw)
	#this uses all records, so the filters will be ignored
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.vcf.gz --comp VCF2.renamed.vcf.gz \
		--ignoreFilters --out ${PREFIX}.raw.txt

	#GATK Genotype Concordance (all_filter)
	#gfe This will apply Genotype filters to EVAL set (anything true in the expression will be a no call
	#gfc This will apply Genotype filters to the Comp set (anything true in the expression will be a no call)
	#Add FT expression in gfc and gfe
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.vcf.gz --comp VCF2.renamed.vcf.gz \
		-gfc 'FT!="PASS"' -gfe  'FT!="PASS"' --out ${PREFIX}.filtered.txt

	# get SNP-only VCFs
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T SelectVariants -selectType SNP -V VCF1.renamed.vcf.gz -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		-o VCF1.renamed.SNP.vcf.gz $PARALLEL_ARGS -l ERROR
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T SelectVariants -selectType SNP -V VCF2.renamed.vcf.gz -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		-o VCF2.renamed.SNP.vcf.gz $PARALLEL_ARGS -l ERROR


	#RUN GATK GENOTYPE CONCORDANCE SNP ONLY
	#GATK Genotype Concordance (raw)
	#this uses all records, so the filters will be ignored
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.SNP.vcf.gz --comp VCF2.renamed.SNP.vcf.gz \
		--ignoreFilters --out ${PREFIX}.raw.SNP.txt

	#GATK Genotype Concordance (all_filter)
	#gfe This will apply Genotype filters to EVAL set (anything true in the expression will be a no call
	#gfc This will apply Genotype filters to the Comp set (anything true in the expression will be a no call)
	#Add FT expression in gfc and gfe
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.SNP.vcf.gz --comp VCF2.renamed.SNP.vcf.gz \
		-gfc 'FT!="PASS"' -gfe 'FT!="PASS"'  --out ${PREFIX}.filtered.SNP.txt

	# get INDEL-only VCF
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T SelectVariants -selectType INDEL -selectType MIXED -selectType MNP \
		-V VCF1.renamed.vcf.gz $PARALLEL_ARGS -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta -o VCF1.renamed.INDEL.vcf.gz -l ERROR
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T SelectVariants -selectType INDEL -selectType MIXED -selectType MNP \
		-V VCF2.renamed.vcf.gz $PARALLEL_ARGS -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta -o VCF2.renamed.INDEL.vcf.gz -l ERROR

	#RUN GATK GENOTYPE CONCORDANCE INDEL ONLY
	#GATK Genotype Concordance (raw)
	#this uses all records, so the filters will be ignored
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.INDEL.vcf.gz --comp VCF2.renamed.INDEL.vcf.gz \
		--ignoreFilters --out ${PREFIX}.raw.INDEL.txt
	#GATK Genotype Concordance (all_filter)
	#gfe This will apply Genotype filters to EVAL set (anything true in the expression will be a no call
	#gfc This will apply Genotype filters to the Comp set (anything true in the expression will be a no call)
	#Add FT expression in gfc and gfe
	java -d64 -Xms512m -Xmx$(( (TOT_MEM * 9) / 10))m -jar /usr/share/GATK/GenomeAnalysisTK-3.4-46.jar \
		-T GenotypeConcordance -R /usr/share/GATK/resources/human_g1k_v37_decoy.fasta \
		--eval VCF1.renamed.INDEL.vcf.gz --comp VCF2.renamed.INDEL.vcf.gz \
		-gfc 'FT!="PASS"' -gfe 'FT!="PASS"' --out ${PREFIX}.filtered.INDEL.txt

	#RUN ALL METRICS ON RAW AND FILTERS FOR  ALL AND SNP ONLY 
	# Extract only the info and lines from #:GATKTable:GenotypeConcordance_Counts 

	#Create Conconordance metrics output files with columns:  sample NRD NRS NRS_Reverse OGC OGCM
	N_SAMPLES=$(cat $ID_LIST_ALL | wc -l)
	
	touch ${PREFIX}_summary.txt

	paste <(printf "%-16s" $(echo "Metric:")) \
	      <(echo "NRS") \
	      <(echo "NRS-R") \
	      <(echo "NRD") \
	      <(echo "OGC") \
	      <(echo "OGC-M") \
	      <(echo "OGC-MU") \
	      <(echo "HHC") \
	      <(echo "HHC-M") \
	      <(echo "NRC") \
	      <(echo "NRC-R") \
	      <(echo "REC") \
	      <(echo "REC-R") > ${PREFIX}_summary.txt

	for f in filtered raw filtered.SNP raw.SNP filtered.INDEL raw.INDEL; do

		FN="$PREFIX.$f.txt"
		detail_dxid=$(dx upload --brief "$FN")
	    dx-jobutil-add-output detail_output "$detail_dxid" --class=array:file
		
		START_LINE=$(grep -n "^ALL" $FN | head -n 2 | tail -1 | cut -d':' -f1)
		SAMPL_LINE=$(grep -n "^Sample" $FN | head -n 2 | tail -1 | cut -d':' -f1)
	
		paste <(printf "%-16s" $(echo "$f:") ) <(print_stats "$(head -n$START_LINE $FN | tail -1)" ) >> ${PREFIX}_summary.txt
	
	
		touch $FN.by_sample	
		RAW_SAMP=$(mktemp)
		head -n$((SAMPL_LINE+N_SAMPLES+1)) $FN | tail -n $((N_SAMPLES+1)) | grep -v '^ALL' > $RAW_SAMP
	
		while read l; do
			paste <(printf "%-16s" $(echo "$l" | sed -e 's/^[ \t]*//' -e 's/[ \t].*/:/')) <(print_stats "$l") >> $FN.by_sample
		done < $RAW_SAMP
		rm $RAW_SAMP
	done
	
	echo >> ${PREFIX}_summary.txt
	echo "Filtered" >> ${PREFIX}_summary.txt
	echo "========" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.filtered.txt.by_sample >> ${PREFIX}_summary.txt
	echo >> ${PREFIX}_summary.txt
	echo "Raw" >> ${PREFIX}_summary.txt
	echo "========" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.raw.txt.by_sample >> ${PREFIX}_summary.txt
	echo >> ${PREFIX}_summary.txt
	echo "Filtered (SNP only)" >> ${PREFIX}_summary.txt
	echo "===================" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.filtered.SNP.txt.by_sample >> ${PREFIX}_summary.txt
	echo >> ${PREFIX}_summary.txt
	echo "Raw (SNP only)" >> ${PREFIX}_summary.txt
	echo "==============" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.raw.SNP.txt.by_sample >> ${PREFIX}_summary.txt
	echo >> ${PREFIX}_summary.txt
	echo "Filtered (INDEL only)" >> ${PREFIX}_summary.txt
	echo "===================" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.filtered.INDEL.txt.by_sample >> ${PREFIX}_summary.txt
	echo >> ${PREFIX}_summary.txt
	echo "Raw (INDEL only)" >> ${PREFIX}_summary.txt
	echo "===================" >> ${PREFIX}_summary.txt
	cat ${PREFIX}.raw.INDEL.txt.by_sample >> ${PREFIX}_summary.txt

	summary_dxid=$(dx upload --brief ${PREFIX}_summary.txt)
	dx-jobutil-add-output summary_output "$summary_dxid" --class=file

	# and please clean up after yourself like a good little boy or girl!
	# but we're in DNANexus, so we can be sloppy!
}
