#!/usr/bin/env bash
export LC_ALL=en_US.UTF-8
export SHELL=bash

##########dDocent##########
VERSION='2.7.0'
#This script serves as an interactive bash wrapper to QC, assemble, map, and call SNPs from double digest RAD (SE or PE), ezRAD (SE or PE) data, or SE RAD data.
#It requires that your raw data are split up by tagged individual and follow the naming convention of:

#Pop_Sample1.F.fq and Pop_Sample1.R.fq

#Prints out title and contact info
echo -e "dDocent" $VERSION "\n"
echo -e "Contact jpuritz@uri.edu with any problems \n\n "

###Code to check for the required software for dDocent

echo "Checking for required software"
DEP=(freebayes mawk bwa samtools vcftools rainbow gnuplot seqtk cd-hit-est bamToBed bedtools parallel vcfcombine pearRM fastp)
NUMDEP=0
for i in "${DEP[@]}"
do
	if which $i &> /dev/null; then
		foo=0
	else
    		echo "The dependency" $i "is not installed or is not in your" '$PATH'"."
    		NUMDEP=$((NUMDEP + 1))
	fi
done


SAMV1=$(samtools 2>&1 >/dev/null | grep Ver | sed -e 's/Version://' | cut -f2 -d " " | sed -e 's/-.*//' | cut -c1)
SAMV2=$(samtools 2>&1 >/dev/null | grep Ver | sed -e 's/Version://' | cut -f2 -d " " | sed -e 's/-.*//' | cut -c3)
	if [ "$SAMV1"  -ge "1" ]; then
		if [ "$SAMV2"  -lt "3" ]; then
        	echo "The version of Samtools installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 1.3.0"
			echo -en "\007"
			echo -en "\007"
			exit 1
		fi
	
	else
		    echo "The version of Samtools installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 1.3.0"
			echo -en "\007"
			echo -en "\007"
			exit 1
	fi

RAINV=(`rainbow | head -1 | cut -f2 -d' ' `)	
	if [[ "$RAINV" != "2.0.2" && "$RAINV" != "2.0.3" && "$RAINV" != "2.0.4" ]]; then
        	echo "The version of Rainbow installed in your" '$PATH' "is not optimized for dDocent."
        	echo -en "\007"
			echo -en "\007"
			echo -en "\007"
        	echo "Is the version of rainbow installed newer than 2.0.2?  Enter yes or no."
			read TEST
			if [ "$TEST" != "yes" ]; then 
        		echo "Please install a version newer than 2.0.2"
        		exit 1
        	fi
        fi
FREEB=(`freebayes | grep -oh 'v[0-9].*' | cut -f1 -d "." | sed 's/v//' `)	
	if [ "$FREEB" != "1" ]; then
        	echo "The version of FreeBayes installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 1.0.0"
        	exit 1
        fi  
SEQTK=( `seqtk 2>&1  | grep Version | cut -f2 -d ":" |  sed 's/1.[1-9]-r//g' | sed 's/-dirty//g' `)
	if [ "$SEQTK" -lt "102" ]; then
		echo "The version of seqtk installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 1.2-r102-dirty"
        	exit 1
	fi
	
VCFTV=$(vcftools | grep VCF | grep -oh '[0-9]*[a-z]*)$' | sed 's/[a-z)]//')
	if [ "$VCFTV" -lt "10" ]; then
        	echo "The version of VCFtools installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 0.1.11"
        	exit 1
        elif [ "$VCFTV" == "11" ]; then
                VCFGTFLAG="--geno" 
        elif [ "$VCFTV" -ge "12" ]; then
                VCFGTFLAG="--max-missing"
	fi
BWAV=$(bwa 2>&1 | mawk '/Versi/' | sed 's/Version: //g' | sed 's/0.7.//g' | sed 's/-.*//g' | cut -c 1-2)
	if [ "$BWAV" -lt "13" ]; then
        	echo "The version of bwa installed in your" '$PATH' "is not optimized for dDocent."
        	echo "Please install at least version 0.7.13"
        	exit 1
	fi

BTC=$( bedtools --version | mawk '{print $2}' | sed 's/v//g' | cut -f1,2 -d"." | sed 's/2\.//g' )
	if [ "$BTC" -ge "26" ]; then
		BEDTOOLSFLAG="NEW"
		elif [ "$BTC" == "23" ]; then
		BEDTOOLSFLAG="OLD"
		elif [ "$BTC" != "23" ]; then
		echo "The version of bedtools installed in your" '$PATH' "is not optimized for dDocent."
		echo "Please install version 2.23.0 or version 2.26.0 and above"
		exit 1	
	fi
		
if ! sort --version | fgrep GNU &>/dev/null; then
	sort=gsort
else
	sort=sort
fi

if [ $NUMDEP -gt 0 ]; then
	echo -e "\nPlease install all required software before running dDocent again."
	exit 1
else
	echo -e "\nAll required software is installed!"
fi

#This code checks for individual fastq files follow the correct naming convention and are gziped
TEST=$(ls *.fq 2> /dev/null | wc -l )
if [ "$TEST" -gt 0 ]; then
echo -e "\ndDocent is now configured to work on compressed sequence files.  Please run gzip to compress your files."
echo "This is as simple as 'gzip *.fq'"
echo "Please rerun dDocent after compressing files."
exit 1
fi

#Count number of individuals in current directory
NumInd=$(ls *.F.fq.gz 2> /dev/null | wc -l)
NumInd=$(($NumInd - 0))

#Test for file limits for current user and reset if necessary

Flimit=$(ulimit -n)
export Flimit

if [ "$Flimit" != "unlimited" ]; then
        Nlimit=$(( $NumInd * 10 ))
        if [ "$Flimit" -lt "$Nlimit" ]; then
                ulimit -n $Nlimit
        fi
fi

#Create list of sample names
ls *.F.fq.gz > namelist 2> /dev/null
sed -i'' -e 's/.F.fq.gz//g' namelist
#Create an array of sample names
NUMNAMES=$(mawk '/_/' namelist | wc -l)

if [ "$NUMNAMES" -eq "$NumInd" ]; then
	NAMES=( `cat "namelist" `)
else
	echo "Individuals do not follow the dDocent naming convention."
	echo "Please rename individuals to: Locality_Individual.F.fq.gz"
	echo "For example: LocA_001.F.fq.gz"
	exit 1
fi

if [[ "$1" == "help" || "$1" == "-help" || "$1" == "--help" || "$1" == "-h" || "$1" == "--h" ]]; then

	echo -e "\nTo run dDocent, simply type '"dDocent"' and press [ENTER]"
	echo -e "\nAlternatively, dDocent can be run with a configuration file.  Usuage is:"
	echo -e "\ndDocent config_file\n\n"
	exit 0
fi

#Wrapper for main program functions.  This allows the entire file to be read first before execution
main(){
##########User Input Section##########
#This code gets input from the user and assigns variables
######################################

#Sets a start time variable
STARTTIME=$(date)


echo -e "\ndDocent run started" $STARTTIME "\n"


#dDocent can now accept a configuration file instead of running interactively
#Checks if a configuration file is being used, if not asks for user input
if [ -n "$1" ]; then
	CONFIG=$1
	if [ ! -f $CONFIG ]; then
		echo -e "\nThe configuration file $CONFIG does not exist."
		exit 1
	fi
	
	NUMProc=$(grep -A1 Processor $CONFIG 2> /dev/null | tail -1 ) 
	if [[ $NUMProc -lt 999999 && $NUMProc -gt 1 ]]; then 
		MAXMemory1=$(grep -A1 Memory $CONFIG | sed 's/[g,G]//g' | tail -1)
	else
		echo -e "\nConfiguration file is not properly configured.  Please see example on dDocent.com or the dDocent GitHub page."
		exit 1
	fi
	MAXMemory=$(( $MAXMemory1 / $NUMProc ))G
	if [[ "$OSTYPE" == "darwin"* ]]; then
		MAXMemory=0
		MAXMemory1=0
	fi
	TRIM=$(grep -A1 Trim $CONFIG | tail -1)
	ASSEMBLY=$(grep -A1 '^Assembly' $CONFIG | tail -1)
	CUTOFF=$(grep -A1 'Minimum within' $CONFIG  2> /dev/null | tail -1)
	if [[ $CUTOFF -lt 9999 && $CUTOFF -gt 0 ]]; then 
		CUTOFF2=$(grep -A1 'Minimum number' $CONFIG | tail -1)
	else
		if [ "$ASSEMBLY" == "yes" ]; then
			echo -e "\nConfiguration file is not properly configured.  Please see example on dDocent.com or the dDocent GitHub page."
			exit 1
		fi
	fi
	ATYPE=$(grep -A1 Type $CONFIG | tail -1)
	simC=$(grep -A1 Simi $CONFIG | tail -1)
	MAP=$(grep -A1 Mapping_R $CONFIG | tail -1)
	optA=$(grep -A1 _Match $CONFIG | tail -1)
	optB=$(grep -A1 MisMatch $CONFIG | tail -1)
	optO=$(grep -A1 Gap $CONFIG | tail -1)
	SNP=$(grep -A1 SNP $CONFIG | tail -1)
	MAIL=$(grep -A1 Email $CONFIG | tail -1)
	
	if [ "$ASSEMBLY" == "yes" ] && [[ -z $CUTOFF || -z $CUTOFF2 ]]; then
		
		echo "dDocent will require input during the assembly stage.  Please wait until prompt says it is safe to move program to the background."	
	else	
		#Prints instructions on how to move analysis to background and disown process
		echo "At this point, all configuration information has been entered and dDocent may take several hours to run." 
		echo "It is recommended that you move this script to a background operation and disable terminal input and output."
		echo "All data and logfiles will still be recorded."
		echo "To do this:"
		echo "Press control and Z simultaneously"
		echo "Type 'bg' without the quotes and press enter"
		echo "Type 'disown -h' again without the quotes and press enter"
		echo ""
		echo "Now sit back, relax, and wait for your analysis to finish"
	
	fi

else
	GetInfo 
fi

#Creates (or appends to) a dDcoent run file recording variables
echo "Variables used in dDocent Run at" $STARTTIME >> dDocent.runs
echo "Number of Processors" >> dDocent.runs
echo $NUMProc >> dDocent.runs
echo "Maximum Memory" >> dDocent.runs
echo $MAXMemory1 | sed 's/[g,G]//g' >> dDocent.runs
echo "Trimming" >> dDocent.runs
echo $TRIM >> dDocent.runs
echo "Assembly?" >> dDocent.runs
echo $ASSEMBLY >> dDocent.runs
echo "Type_of_Assembly" >> dDocent.runs
echo $ATYPE >> dDocent.runs
echo "Clustering_Similarity%" >> dDocent.runs
echo $simC >> dDocent.runs
if [ -n "$CUTOFF" ]; then
	echo "Minimum within individaul coverage level to include a read for assembly (K1)" >> dDocent.runs
	echo $CUTOFF >> dDocent.runs
else
	echo "Minimum within individaul coverage level to include a read for assembly (K1)" >> dDocent.runs
	echo "CUTOFF1_NOTSET" >> dDocent.runs
fi
if [ -n "$CUTOFF2" ]; then
	echo "Minimum number of individuals a read must be present in to include for assembly (K2)" >> dDocent.runs
	echo $CUTOFF2 >> dDocent.runs
else
	echo "Minimum number of individuals a read must be present in to include for assembly (K2)" >> dDocent.runs
	echo "CUTOFF2_NOTSET" >> dDocent.runs
fi
echo "Mapping_Reads?" >> dDocent.runs
echo $MAP >> dDocent.runs
echo "Mapping_Match_Value" >> dDocent.runs
echo $optA >> dDocent.runs
echo "Mapping_MisMatch_Value" >> dDocent.runs
echo $optB >> dDocent.runs
echo "Mapping_GapOpen_Penalty" >> dDocent.runs
echo $optO >> dDocent.runs
echo "Calling_SNPs?" >> dDocent.runs
echo $SNP >> dDocent.runs
echo "Email" >> dDocent.runs
echo $MAIL >> dDocent.runs


##Section of logic statements that dictates the order and function of processing the pipeline

if [[ "$TRIM" == "yes" && "$ASSEMBLY" == "yes" ]]; then
        echo -e "\nTrimming reads and simultaneously assembling reference sequences"        
        TrimReads & 2> trim.log
        Assemble
        #setupRainbow 2> rainbow.log
        wait
fi

if [[ "$TRIM" == "yes" && "$ASSEMBLY" != "yes" ]]; then
        echo -e "\nTrimming reads"
        TrimReads 2> trim.log
fi                
                
if [[ "$TRIM" != "yes" && "$ASSEMBLY" == "yes" ]]; then                
        Assemble
        #setupRainbow 2> rainbow.log
fi

#Checks to see if reads will be mapped.
if [ "$MAP" != "no" ]; then
echo -e "\nUsing BWA to map reads"
	if [ reference.fasta -nt reference.fasta.fai ]; then
        samtools faidx reference.fasta &> index.log
        bwa index reference.fasta >> index.log 2>&1
	fi
#dDocent now checks for trimmed read files before attempting mapping
        if [[ "$MAP" != "no" && ! -f "${NAMES[@]:(-1)}".R1.fq.gz ]]; then
        	echo "dDocent cannot locate trimmed reads files"
        	echo "Please rerun dDocent with quality trimming"
        	exit 1
        fi
#This next section of code checks to see if the reference was assembled by dDocent 
#and if so, modifies the expected insert length distribution for BWA's metric for proper pairing
        if head -1 reference.fasta | grep -e 'dDocent_' reference.fasta 1>/dev/null; then
        	rm lengths.txt &> /dev/null
        	for i in "${NAMES[@]}";
        		do
        		if [ -f "$i.R.fq.gz" ]; then
        		gunzip -c $i.R.fq.gz | head -2 | tail -1 >> lengths.txt
        		fi
        		done	
        	if [ -f "lengths.txt" ]; then
        	MaxLen=$(mawk '{ print length() | "sort -rn" }' lengths.txt| head -1)
        	INSERT=$(($MaxLen * 2 ))
        	INSERTH=$(($INSERT + 100 ))
        	INSERTL=$(($INSERT - 100 ))
        	SD=$(($INSERT / 5))
        	fi
#BWA for mapping for all samples.  As of version 2.0 can handle SE or PE reads by checking for PE read files
        	for i in "${NAMES[@]}"
        	do
        	if [ -f "$i.R2.fq.gz" ]; then
        		bwa mem -L 20,5 -I $INSERT,$SD,$INSERTH,$INSERTL -t $NUMProc -a -M -T 10 -A $optA -B $optB -O $optO -R "@RG\tID:$i\tSM:$i\tPL:Illumina" reference.fasta $i.R1.fq.gz $i.R2.fq.gz  2> bwa.$i.log | mawk '$6 !~/[2-9].[SH]/ && $6 !~ /[1-9][0-9].[SH]/' | samtools view -@$NUMProc -q 1 -SbT reference.fasta - > $i.bam 2>$i.bam.log
        	else
        		bwa mem -L 20,5 -t $NUMProc -a -M -T 10 -A $optA -B $optB -O $optO -R "@RG\tID:$i\tSM:$i\tPL:Illumina" reference.fasta $i.R1.fq.gz 2> bwa.$i.log | mawk '$6 !~/[2-9].[SH]/ && $6 !~ /[1-9][0-9].[SH]/' | samtools view -@$NUMProc -q 1 -SbT reference.fasta - > $i.bam 2>$i.bam.log
        	fi
        	samtools sort -@$NUMProc $i.bam -o $i.bam 2>>$i.bam.log
		mv $i.bam $i-RG.bam
		samtools index $i-RG.bam
        	done
        else
        	for i in "${NAMES[@]}"
        	do
        	if [ -f "$i.R2.fq.gz" ]; then
        		bwa mem -L 20,5 -t $NUMProc -a -M -T 10 -A $optA -B $optB -O $optO -R "@RG\tID:$i\tSM:$i\tPL:Illumina" reference.fasta $i.R1.fq.gz $i.R2.fq.gz  2> bwa.$i.log | mawk '$6 !~/[2-9].[SH]/ && $6 !~ /[1-9][0-9].[SH]/' | samtools view -@$NUMProc -q 1 -SbT reference.fasta - > $i.bam 2>$i.bam.log
        	else
        		bwa mem -L 20,5 -t $NUMProc -a -M -T 10 -A $optA -B $optB -O $optO -R "@RG\tID:$i\tSM:$i\tPL:Illumina" reference.fasta $i.R1.fq.gz  2> bwa.$i.log | mawk '$6 !~/[2-9].[SH]/ && $6 !~ /[1-9][0-9].[SH]/' | samtools view -@$NUMProc -q 1 -SbT reference.fasta - > $i.bam 2>$i.bam.log
        	fi
        	samtools sort -@$NUMProc $i.bam -o $i.bam 2>>$i.bam.log
		mv $i.bam $i-RG.bam
		samtools index $i-RG.bam
        	done
        fi
fi

##Creating mapping intervals if needed, CreateIntervals function is defined later in script
#If mapping is being performed, intervals are created automatically

if [ "$MAP" != "no" ]; then
echo -e "\nCreating alignment intervals"
ls *-RG.bam >bamlist.list
CreateIntervals 
fi

##SNP Calling Section of code

if [ "$SNP" != "no" ]; then
	#Create list of BAM files
	ls *-RG.bam >bamlist.list
	#If mapping is not being performed, but intervals do not exist they are created
	if [[ "$MAP" == "no" && ! -f "cat-RRG.bam" ]]; then
		CreateIntervals 
	fi
	#Check for runs from older versions to ensure the recreation of cat-RRG.bam
	if [[ "$MAP" == "no" && -f "map.bed" ]]; then
		CreateIntervals 
	fi
	#Check to make sure interval files have been created
	if [[ "$MAP" == "no" && ! -f "mapped.bed" ]]; then
		bedtools merge -i cat-RRG.bam -bed >  mapped.bed
	fi
	#This code estimates the coverage of reference intervals and removes intervals in 0.01% of depth
	#This allows genotyping to be more effecient and eliminates extreme copy number loci from the data
	if [ "cat-RRG.bam" -nt "cov.stats" ]; then
		FB2=$(( $NUMProc / 2 ))
		if [ "$BEDTOOLSFLAG" == "OLD" ]; then
			cat namelist | parallel -j $FB2 "coverageBed -abam {}-RG.bam -b mapped.bed -counts > {}.cov.stats"
		else
			mawk -v OFS='\t' {'print $1,$2'} reference.fasta.fai > genome.file
			cat namelist | parallel -j $FB2 "bedtools coverage -b {}-RG.bam -a mapped.bed -counts -sorted -g genome.file > {}.cov.stats"
		fi
		cat *.cov.stats | $sort -k1,1 -k2,2n | bedtools merge -i - -c 4 -o sum > cov.stats
	fi
		
	if head -1 reference.fasta | grep -e 'dDocent' reference.fasta 1>/dev/null; then
	
		DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.001;@l=<>;print $l[int($d*@l)]')
		CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$NUMProc'"}')
	else
		DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.00005;@l=<>;print $l[int($d*@l)]')
		CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$NUMProc'"}')
	fi
	mawk -v x=$DP '$4 < x' cov.stats |$sort -V -k1,1 -k2,2 | mawk -v cutoff=$CC 'BEGIN{i=1} 
	{
	len=$3-$2;lc=len*$4;cov = cov + lc
	if ( cov < cutoff) {x="mapped."i".bed";print $1"\t"$2"\t"$3 > x}
	else {i=i+1; x="mapped."i".bed"; print $1"\t"$2"\t"$3 > x; cov=0}
	}' 
	
	FB2=$(( $NUMProc / 4 ))
	export FB2
	echo -e "\nUsing FreeBayes to call SNPs"

	#Creates a population file to use for more accurate genotype calling
	
	cut -f1 -d "_" namelist > p
	paste namelist p > popmap
	rm p
	


###New implementation of SNP calling here to save on memory	
	call_genos(){
		samtools view -@$FB2 -b -1 -L mapped.$1.bed -o split.$1.bam cat-RRG.bam
		samtools index split.$1.bam
		freebayes -b split.$1.bam -t mapped.$1.bed -v raw.$1.vcf -f reference.fasta -m 5 -q 5 -E 3 --min-repeat-entropy 1 -V --populations popmap -n 10
		if [ $? -eq 0 ]; then
    			echo "freebayes instance $1 completed successfully." >> freebayes.log
		else
    			echo -e "\n\nERROR: freebayes instance DID NOT COMPLETE\n\nSee below:"
			echo $? > freebayes.error
			exit 1
		fi	
		rm split.$1.bam*
	}
	
	export -f call_genos
	
	rm freebayes.error freebayes.log &> /dev/null
	
	ls mapped.*.bed | sed 's/mapped.//g' | sed 's/.bed//g' | shuf | parallel --bar --halt now,fail=1 --env call_genos --memfree $MAXMemory -j $NUMProc --no-notice "call_genos {} 2> /dev/null"


	if [ -f "freebayes.error" ]; then
               	echo -e "\nA previous freebayes instance failed.  dDocent will now recalibrate run parameters to use less memory.\n"
		rm mapped.*.bed
		rm freebayes.error
		LIM=$(( $NUMProc * 2 ))
        	if head -1 reference.fasta | grep -e 'dDocent' reference.fasta 1>/dev/null; then

                	DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.001;@l=<>;print $l[int($d*@l)]')
                	CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$LIM'"}')
        	else
                	DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.00005;@l=<>;print $l[int($d*@l)]')
                	CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$LIM'"}')
        	fi
        	mawk -v x=$DP '$4 < x' cov.stats |$sort -V -k1,1 -k2,2 | mawk -v cutoff=$CC 'BEGIN{i=1}
        	{ len=$3-$2;lc=len*$4;cov = cov + lc
        	if ( cov < cutoff) {x="mapped."i".bed";print $1"\t"$2"\t"$3 > x}
        	else {i=i+1; x="mapped."i".bed"; print $1"\t"$2"\t"$3 > x; cov=0}
        	}'

        	FB2=$(( $NUMProc / 10 ))
        	export FB2
		echo "Using FreeBayes to call SNPs again"
		NumP=$(( $NUMProc / 4 ))
		NumP=$(( $NumP * 3 ))
		ls mapped.*.bed | sed 's/mapped.//g' | sed 's/.bed//g' | shuf | parallel --bar --halt now,fail=1 --env call_genos --memfree $MAXMemory -j $NumP --no-notice "call_genos {} 2> /dev/null" 
        fi

	if [ -f "freebayes.error" ]; then
		echo -e "\nA previous freebayes instance failed again.  dDocent will now recalibrate run parameters to use even less memory.\n"
                rm freebayes.error
		
		LIM=$(( $NUMProc * 4 ))
        	if head -1 reference.fasta | grep -e 'dDocent' reference.fasta 1>/dev/null; then

                	DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.001;@l=<>;print $l[int($d*@l)]')
                	CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$LIM'"}')
        	else
                	DP=$(mawk '{print $4}' cov.stats | $sort -rn | perl -e '$d=.00005;@l=<>;print $l[int($d*@l)]')
                	CC=$( mawk -v x=$DP '$4 < x' cov.stats | mawk '{len=$3-$2;lc=len*$4;tl=tl+lc} END {OFMT = "%.0f";print tl/"'$LIM'"}')
        	fi
        	mawk -v x=$DP '$4 < x' cov.stats |$sort -V -k1,1 -k2,2 | mawk -v cutoff=$CC 'BEGIN{i=1}
        	{ len=$3-$2;lc=len*$4;cov = cov + lc
        	if ( cov < cutoff) {x="mapped."i".bed";print $1"\t"$2"\t"$3 > x}
        	else {i=i+1; x="mapped."i".bed"; print $1"\t"$2"\t"$3 > x; cov=0}
        	}'
		
            	NumP=$(( $NumP / 4 ))
                NumP=$(( $NumP * 3 ))
		echo "Using FreeBayes to call SNPs again"
                ls mapped.*.bed | sed 's/mapped.//g' | sed 's/.bed//g' | shuf | parallel --bar --halt now,fail=1 --env call_genos --memfree $MAXMemory -j $NumP --no-notice "call_genos {} 2> /dev/null"
	fi

	if [ -f "freebayes.error" ]; then
		echo -e "\n\n\nFreeBayes has now failed a third  time, likely because of memory issues.  More resources must be allocated to finish this analysis."
		ERROR3=1
		export ERROR3
	else
            	ERROR3=0
		export ERROR3
        fi

	rm mapped.*.bed  

	mv raw.1.vcf raw.01.vcf 2>/dev/null
	mv raw.2.vcf raw.02.vcf 2>/dev/null
	mv raw.3.vcf raw.03.vcf 2>/dev/null
	mv raw.4.vcf raw.04.vcf 2>/dev/null
	mv raw.5.vcf raw.05.vcf 2>/dev/null
	mv raw.6.vcf raw.06.vcf 2>/dev/null
	mv raw.7.vcf raw.07.vcf 2>/dev/null
	mv raw.8.vcf raw.08.vcf 2>/dev/null
	mv raw.9.vcf raw.09.vcf 2>/dev/null

	vcfcombine raw.*.vcf | sed -e 's/	\.\:/	\.\/\.\:/g' > TotalRawSNPs.vcf

	if [ ! -d "raw.vcf" ]; then
		mkdir raw.vcf
	fi

	mv raw.*.vcf ./raw.vcf

	echo -e "\nUsing VCFtools to parse TotalRawSNPS.vcf for SNPs that are called in at least 90% of individuals"
	vcftools --vcf TotalRawSNPs.vcf $VCFGTFLAG 0.9 --out Final --recode --non-ref-af 0.001 --max-non-ref-af 0.9999 --mac 1 --minQ 30 --recode-INFO-all &>VCFtools.log
fi

##Checking for possible errors

if [ "$MAP" != "no" ]; then
	ERROR1=$(mawk '/developer/' bwa* 2>/dev/null | wc -l 2>/dev/null) 
fi
ERROR2=$(mawk '/error/' *.bam.log 2>/dev/null | wc -l 2>/dev/null)
if [ "$SNP" == "no" ]; then
	ERROR3=0
fi
ERRORS=$(($ERROR1 + $ERROR2 + $ERROR3))

#Move various log files to own directory
if [ ! -d "logfiles" ]; then
mkdir logfiles
fi
mv *.txt *.log log ./logfiles 2> /dev/null

#Sending a completion email

if [ $ERRORS -gt 0 ]; then
        echo -e "dDocent has finished with errors in" `pwd` "\n\ndDocent started" $STARTTIME "\n\ndDocent finished" `date` "\n\nPlease check log files\n\n" `mawk '/After filtering, kept .* out of a possible/' ./logfiles/VCFtools.log` "\n\ndDocent" $VERSION "\nThe 'd' is silent, hillbilly." | mailx -s "dDocent has finished with ERRORS!" $MAIL
else
        echo -e "dDocent has finished with an analysis in" `pwd` "\n\ndDocent started" $STARTTIME "\n\ndDocent finished" `date` "\n\n" `mawk '/After filtering, kept .* out of a possible/' ./logfiles/VCFtools.log` "\n\ndDocent" $VERSION "\nThe 'd' is silent, hillbilly." | mailx -s "dDocent has finished" $MAIL
fi


}

##Function definitions

#Function for trimming reads using trimmomatic
trim_reads(){

	if [ -f $1.R.fq.gz ]; then	
		fastp -i $1.F.fq.gz -I $1.R.fq.gz -o $1.R1.fq.gz -O $1.R2.fq.gz -j $1 &> $1.trim.log
	else 
		fastp -i $1.F.fq.gz -o $1.R1.fq.gz -j $1 &> $1.trim.log
	fi 
}
	
	export -f trim_reads

TrimReads () { 
	#STACKS adds a strange _1 or _2 character to the end of processed reads, this looks for checks for errant characters and replaces them.
	#This functionality is now parallelized and will run if only SE sequences are used.
	NAMES=( `cat "namelist" `)
	STACKS=$(cat namelist| parallel -j $NUMProc --no-notice "gunzip -c {}.F.fq.gz | head -1" | mawk '$0 !~ /\/1$/ && $0 !~ /\/1[ ,	]/ && $0 !~ / 1:.*[A-Z]*/' | wc -l )
	FB1=$(( $NUMProc / 2 ))
	if [ $STACKS -gt 0 ]; then
		
		echo "Removing the _1 character and replacing with /1 in the name of every sequence"
		cat namelist | parallel -j $FB1 --no-notice "gunzip -c {}.F.fq.gz | sed -e 's:_1$:/1:g' > {}.F.fq"
		rm -f *.F.fq.gz
		cat namelist | parallel -j $FB1 --no-notice "gzip {}.F.fq"
	fi

	if [ -f "${NAMES[@]:(-1)}".R.fq.gz ]; then
	
		STACKS=$(cat namelist| parallel -j $NUMProc --no-notice "gunzip -c {}.R.fq.gz | head -1" | mawk '$0 !~ /\/2$/ && $0 !~ /\/2[ ,	]/ && $0 !~ / 2:.*[A-Z]*/'| wc -l )

		if [ $STACKS -gt 0 ]; then
			echo "Removing the _2 character and replacing with /2 in the name of every sequence"
			cat namelist | parallel -j $FB1 --no-notice "gunzip -c {}.R.fq.gz | sed -e 's:_2$:/2:g' > {}.R.fq"
			rm -f *.R.fq.gz
			cat namelist | parallel -j $FB1 --no-notice "gzip {}.R.fq"
		fi
	fi

	cat namelist | parallel -j $NUMProc "gunzip -c {}.F.fq.gz | head -2 | tail -1 >> lengths.txt"
	MLen=$(mawk '{ print length() | "sort -rn" }' lengths.txt| head -1)
    	MLen=$(($MLen / 2))
	TW="MINLEN:$MLen"
	cat namelist | parallel --env trim_reads -j $FB1 trim_reads {}	
	mkdir unpaired &>/dev/null
	mv *unpaired*.gz ./unpaired &>/dev/null	
}


getAssemblyInfo(){
#Have user estimate/enter assembly parameters if unentered

if [ -z "$CUTOFF" ]; then

	for i in {2..20};
	do 
	echo $i >> pfile
	done
	cat pfile | parallel -j $NUMProc --no-notice "echo -n {}xxx && mawk -v x={} '\$1 >= x' uniq.seqs | wc -l" | mawk  '{gsub("xxx","\t",$0); print;}'| $sort -g > uniqseq.data
	rm pfile


	#Plot graph of above data
	gnuplot << \EOF 
	set terminal dumb size 120, 30
	set autoscale
	set xrange [2:20] 
	unset label
	set title "Number of Unique Sequences with More than X Coverage (Counted within individuals)"
	set xlabel "Coverage"
	set ylabel "Number of Unique Sequences"
	plot 'uniqseq.data' with lines notitle
	pause -1
EOF


	echo -en "\007"
	echo -en "\007"
	echo -en "\007"
	echo -e "Please choose data cutoff.  In essence, you are picking a minimum (within individual) coverage level for a read (allele) to be used in the reference assembly"
	
	read CUTOFF
fi



special_uniq(){
	mawk -v x=$1 '$1 >= x' $2  |cut -f2 | sed -e 's/NNNNNNNNNN/	/g' | cut -f1 | uniq
}
export -f special_uniq


if [[ "$ATYPE" == "RPE" || "$ATYPE" == "ROL" ]]; then
  	parallel --no-notice -j $NUMProc --env special_uniq special_uniq $CUTOFF {} ::: *.uniq.seqs  | $sort --parallel=$NUMProc -S 2G | uniq -c > uniqCperindv
else
	parallel --no-notice -j $NUMProc mawk -v x=$CUTOFF \''$1 >= x'\' ::: *.uniq.seqs | cut -f2 | perl -e 'while (<>) {chomp; $z{$_}++;} while(($k,$v) = each(%z)) {print "$v\t$k\n";}' > uniqCperindv
fi


if [ -z "$CUTOFF2" ]; then
	if [ "$NumInd" -gt 10 ]; then
		NUM=$(($NumInd / 2))
	else
		NUM=$NumInd
	fi
 
	for ((i = 2; i <= $NUM; i++));
	do
	echo $i >> ufile
	done

	cat ufile | parallel -j $NUMProc --no-notice "echo -n {}xxx && mawk -v x={} '\$1 >= x' uniqCperindv | wc -l" | mawk  '{gsub("xxx","\t",$0); print;}'| $sort -g > uniqseq.peri.data
	rm ufile

	
	#Plot graph of above data
	
	gnuplot << \EOF 
	set terminal dumb size 120, 30
	set autoscale 
	unset label
	set title "Number of Unique Sequences present in more than X Individuals"
	set xlabel "Number of Individuals"
	set ylabel "Number of Unique Sequences"
	plot 'uniqseq.peri.data' with lines notitle
	pause -1
EOF
	
	echo -en "\007"
	echo -en "\007"
	echo -en "\007"
	echo -e "Please choose data cutoff.  Pick point right before the assymptote. A good starting cutoff might be 10% of the total number of individuals"
	
	read CUTOFF2

fi


#Prints instructions on how to move analysis to background and disown process

sed -i 's/CUTOFF1_NOTSET/'$CUTOFF'/g' dDocent.runs
sed -i 's/CUTOFF2_NOTSET/'$CUTOFF2'/g' dDocent.runs

echo "At this point, all configuration information has been entered and dDocent may take several hours to run." 
echo "It is recommended that you move this script to a background operation and disable terminal input and output."
echo "All data and logfiles will still be recorded."
echo "To do this:"
echo "Press control and Z simultaneously"
echo "Type 'bg' without the quotes and press enter"
echo "Type 'disown -h' again without the quotes and press enter"
echo ""
echo "Now sit back, relax, and wait for your analysis to finish"


}

#Main function for assembly
Assemble()
{
AWK1='BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}'
AWK2='!/>/'
AWK3='!/NNN/'
AWK4='{for(i=0;i<$1;i++)print}'
PERLT='while (<>) {chomp; $z{$_}++;} while(($k,$v) = each(%z)) {print "$v\t$k\n";}'
SED1='s/^[ \t]*//'
SED2='s/\s/\t/g'
FRL=$(gunzip -c ${NAMES[0]}.F.fq.gz | mawk '{ print length() | "sort -rn" }' | head -1)

special_uniq(){
	mawk -v x=$1 '$1 >= x' $2  |cut -f2 | sed -e 's/NNNNNNNNNN/	/g' | cut -f1 | uniq
}
export -f special_uniq

if [ ${NAMES[@]:(-1)}.F.fq.gz -nt ${NAMES[@]:(-1)}.uniq.seqs ];then
	if [[ "$ATYPE" == "PE" || "$ATYPE" == "RPE" ]]; then
	#If PE assembly, creates a concatenated file of every unique for each individual in parallel
		cat namelist | parallel --no-notice -j $NUMProc "gunzip -c {}.F.fq.gz | mawk '$AWK1' | mawk '$AWK2' > {}.forward"
		cat namelist | parallel --no-notice -j $NUMProc "gunzip -c {}.R.fq.gz | mawk '$AWK1' | mawk '$AWK2' > {}.reverse"
		if [ "$ATYPE" = "RPE" ]; then
			cat namelist | parallel --no-notice -j $NUMProc "paste {}.forward {}.reverse | $sort -k1 -S 200M > {}.fr"
			cat namelist | parallel --no-notice -j $NUMProc "cut -f1 {}.fr | uniq -c > {}.f.uniq && cut -f2 {}.fr > {}.r"
			cat namelist | parallel --no-notice -j $NUMProc "mawk '$AWK4' {}.f.uniq > {}.f.uniq.e" 
			cat namelist | parallel --no-notice -j $NUMProc "paste -d '-' {}.f.uniq.e {}.r | mawk '$AWK3'| sed 's/-/NNNNNNNNNN/' | sed -e '$SED1' | sed -e '$SED2'> {}.uniq.seqs"
			rm *.f.uniq.e *.f.uniq *.r *.fr
		else
			cat namelist | parallel --no-notice -j $NUMProc "paste -d '-' {}.forward {}.reverse | mawk '$AWK3'| sed 's/-/NNNNNNNNNN/' | perl -e '$PERLT' > {}.uniq.seqs"
		fi
		rm *.forward
		rm *.reverse
	fi
	
	if [ "$ATYPE" == "SE" ]; then
	#if SE assembly, creates files of every unique read for each individual in parallel
		cat namelist | parallel --no-notice -j $NUMProc "gunzip -c {}.F.fq.gz | mawk '$AWK1' | mawk '$AWK2' | perl -e '$PERLT' > {}.uniq.seqs"
	fi
	
	if [ "$ATYPE" == "OL" ]; then
	#If OL assembly, dDocent assumes that the marjority of PE reads will overlap, so the software PEAR is used to merge paired reads into single reads
		for i in "${NAMES[@]}";
        		do
        		gunzip -c $i.R.fq.gz | head -2 | tail -1 >> lengths.txt
        		done	
        	MaxLen=$(mawk '{ print length() | "sort -rn" }' lengths.txt| head -1)
		LENGTH=$(( $MaxLen / 3))
		for i in "${NAMES[@]}"
			do
			pearRM -f $i.F.fq.gz -r $i.R.fq.gz -o $i -j $NUMProc -n $LENGTH 
			done
		cat namelist | parallel --no-notice -j $NUMProc "mawk '$AWK1' {}.assembled.fastq | mawk '$AWK2' | perl -e '$PERLT' > {}.uniq.seqs"
	fi
	if [ "$ATYPE" == "HYB" ]; then
	#If HYB assembly, dDocent assumes some PE reads will overlap but that some will not, so the OL method performed and remaining reads are then put through PE method
		for i in "${NAMES[@]}";
      		do
      		gunzip -c $i.R.fq.gz | head -2 | tail -1 >> lengths.txt
      		done	
    		MaxLen=$(mawk '{ print length() | "sort -rn" }' lengths.txt| head -1)
    		LENGTH=$(( $MaxLen / 3))
		for i in "${NAMES[@]}"
			do
			pearRM -f $i.F.fq.gz -r $i.R.fq.gz -o $i -j $NUMProc -n $LENGTH &>kopt.log
			done
		cat namelist | parallel --no-notice -j $NUMProc "mawk '$AWK1' {}.assembled.fastq | mawk '$AWK2' | perl -e '$PERLT' > {}.uniq.seqs"
		
		cat namelist | parallel --no-notice -j $NUMProc "cat {}.unassembled.forward.fastq | mawk '$AWK1' | mawk '$AWK2' > {}.forward"
		cat namelist | parallel --no-notice -j $NUMProc "cat {}.unassembled.reverse.fastq | mawk '$AWK1' | mawk '$AWK2' > {}.reverse"
		cat namelist | parallel --no-notice -j $NUMProc "paste -d '-' {}.forward {}.reverse | mawk '$AWK3'| sed 's/-/NNNNNNNNNN/' | perl -e '$PERLT' > {}.uniq.ua.seqs"
		rm *.forward
		rm *.reverse
	fi	
	
fi

#Create a data file with the number of unique sequences and the number of occurrences

if [ -f "uniq.seqs.gz" ]; then
	if [ uniq.seqs.gz -nt uniq.seqs ]; then
	gunzip uniq.seqs.gz 2>/dev/null
	fi
fi

if [ ! -f "uniq.seqs" ]; then
	cat *.uniq.seqs > uniq.seqs
fi
	
if [[ -z $CUTOFF || -z $CUTOFF2 ]]; then
getAssemblyInfo
fi

if [[ "$ATYPE" == "RPE" || "$ATYPE" == "ROL" ]]; then
  	parallel --no-notice -j $NUMProc --env special_uniq special_uniq $CUTOFF {} ::: *.uniq.seqs  | $sort --parallel=$NUMProc -S 2G | uniq -c > uniqCperindv
else
	parallel --no-notice -j $NUMProc mawk -v x=$CUTOFF \''$1 >= x'\' ::: *.uniq.seqs | cut -f2 | perl -e 'while (<>) {chomp; $z{$_}++;} while(($k,$v) = each(%z)) {print "$v\t$k\n";}' > uniqCperindv
fi

#Now that data cutoffs have been chosen, reduce data set to specified set of unique reads, convert to FASTA format,
#and remove reads with substantial amounts of adapters

if [[ "$ATYPE" == "RPE" || "$ATYPE" == "ROL" ]]; then
  parallel --no-notice -j $NUMProc mawk -v x=$CUTOFF \''$1 >= x'\' ::: *.uniq.seqs | cut -f2 | sed 's/NNNNNNNNNN/-/' >  total.uniqs
  cut -f 1 -d "-" total.uniqs > total.u.F
  cut -f 2 -d "-" total.uniqs > total.u.R
  paste total.u.F total.u.R | $sort -k1 --parallel=$NUMProc -S 2G > total.fr
 
  parallel --no-notice --env special_uniq special_uniq $CUTOFF {} ::: *.uniq.seqs  | $sort --parallel=$NUMProc -S 2G | uniq -c > total.f.uniq
  join -1 2 -2 1 -o 1.1,1.2,2.2 total.f.uniq total.fr | mawk '{print $1 "\t" $2 "NNNNNNNNNN" $3}' | mawk -v x=$CUTOFF2 '$1 >= x' > uniq.k.$CUTOFF.c.$CUTOFF2.seqs
  rm total.uniqs total.u.* total.fr total.f.uniq* 
  
else
	parallel --no-notice mawk -v x=$CUTOFF \''$1 >= x'\' ::: *.uniq.seqs | cut -f2 | perl -e 'while (<>) {chomp; $z{$_}++;} while(($k,$v) = each(%z)) {print "$v\t$k\n";}' | mawk -v x=$CUTOFF2 '$1 >= x' > uniq.k.$CUTOFF.c.$CUTOFF2.seqs
fi
$sort -k1 -r -n uniq.k.$CUTOFF.c.$CUTOFF2.seqs | cut -f 2 > totaluniqseq
mawk '{c= c + 1; print ">dDocent_Contig_" c "\n" $1}' totaluniqseq > uniq.full.fasta
LENGTH=$(mawk '!/>/' uniq.full.fasta  | mawk '(NR==1||length<shortest){shortest=length} END {print shortest}')
LENGTH=$(($LENGTH * 3 / 4))
seqtk seq -F I uniq.full.fasta > uniq.fq
if [ "$NUMProc" -gt 8 ]; then
	NP=8
else
	NP=$NumProc
fi
fastp -i uniq.fq -o uniq.fq1 -w $NP -Q &> assemble.trim.log
mawk 'BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}' uniq.fq1 > uniq.fasta
mawk '!/>/' uniq.fasta > totaluniqseq
rm uniq.fq*

if [[ "$ATYPE" == "PE" || "$ATYPE" == "RPE" ]]; then
	pmerge(){
		num=$( echo $1 | sed 's/^0*//g')
		if [ "$num" -le 100 ]; then
			j=$num
			k=$(($num -1))
		else
			num=$(($num - 99))
           		j=$(python -c "print ("$num" * 100)")
                	k=$(python -c "print ("$j" - 100)")
		fi
                mawk -v x="$j" -v y="$k" '$5 <= x && $5 > y'  rbdiv.out > rbdiv.out.$1
	   
	   	if [ -s "rbdiv.out.$1" ]; then
           		rainbow merge -o rbasm.out.$1 -a -i rbdiv.out.$1 -r 2 -N10000 -R10000 -l 20 -f 0.75
           	fi
        }
	
	export -f pmerge
	
        #Reads are first clustered using only the Forward reads using CD-hit instead of rainbow
        if [ "$ATYPE" == "PE" ]; then
		sed -e 's/NNNNNNNNNN/	/g' uniq.fasta | cut -f1 > uniq.F.fasta
	  	CDHIT=$(python -c "print (max("$simC" - 0.1,0.8))")
	  	cd-hit-est -i uniq.F.fasta -o xxx -c $CDHIT -T $NUMProc -M 0 -g 1 -d 100 &>cdhit.log
	  	mawk '{if ($1 ~ /Cl/) clus = clus + 1; else  print $3 "\t" clus}' xxx.clstr | sed 's/[>dDocent_Contig_,...]//g' | $sort -g -k1 -S 2G --parallel=$NUMProc > sort.contig.cluster.ids
	  	paste sort.contig.cluster.ids totaluniqseq > contig.cluster.totaluniqseq
          
     	else
        	sed -e 's/NNNNNNNNNN/	/g' totaluniqseq | cut -f1 | $sort --parallel=$NUMProc -S 2G| uniq | mawk '{c= c + 1; print ">dDocent_Contig_" c "\n" $1}' > uniq.F.fasta
		CDHIT=$(python -c "print (max("$simC" - 0.1,0.8))")
		cd-hit-est -i uniq.F.fasta -o xxx -c $CDHIT -T $NUMProc -M 0 -g 1 -d 100 &>cdhit.log
  		mawk '{if ($1 ~ /Cl/) clus = clus + 1; else  print $3 "\t" clus}' xxx.clstr | sed 's/[>dDocent_Contig_,...]//g' | $sort -g -k1 -S 2G --parallel=$NUMProc > sort.contig.cluster.ids
  		paste sort.contig.cluster.ids <(mawk '!/>/' uniq.F.fasta) > contig.cluster.Funiq
  		sed -e 's/NNNNNNNNNN/	/g' totaluniqseq | $sort --parallel=$NUMProc -k1 -S 2G | mawk '{print $0 "\t" NR}'  > totaluniqseq.CN
  		join -t $'\t' -1 3 -2 1 contig.cluster.Funiq totaluniqseq.CN -o 2.3,1.2,2.1,2.2 > contig.cluster.totaluniqseq
	fi	
	
	#CD-hit output is converted to rainbow format
	$sort -k2,2 -g contig.cluster.totaluniqseq -S 2G --parallel=$NUMProc | sed -e 's/NNNNNNNNNN/	/g' > rcluster
	rainbow div -i rcluster -o rbdiv.out -f 0.5 -K 10
        CLUST=(`tail -1 rbdiv.out | cut -f5`)
	CLUST1=$(( $CLUST / 100 + 1))
	CLUST2=$(( $CLUST1 + 100 ))
	
	seq -w 1 $CLUST2 | parallel --no-notice -j $NUMProc --env pmerge pmerge {}
	
        cat rbasm.out.[0-9]* > rbasm.out
        rm rbasm.out.[0-9]* rbdiv.out.[0-9]*

	#This AWK code replaces rainbow's contig selection perl script
  	cat rbasm.out <(echo "E") |sed 's/[0-9]*:[0-9]*://g' | mawk ' {
		if (NR == 1) e=$2;
		else if ($1 ~/E/ && lenp > len1) {c=c+1; print ">dDocent_Contig_" e "\n" seq2 "NNNNNNNNNN" seq1; seq1=0; seq2=0;lenp=0;e=$2;fclus=0;len1=0;freqp=0;lenf=0}
		else if ($1 ~/E/ && lenp <= len1) {c=c+1; print ">dDocent_Contig_" e "\n" seq1; seq1=0; seq2=0;lenp=0;e=$2;fclus=0;len1=0;freqp=0;lenf=0}
		else if ($1 ~/C/) clus=$2;
		else if ($1 ~/L/) len=$2;
		else if ($1 ~/S/) seq=$2;
		else if ($1 ~/N/) freq=$2;
		else if ($1 ~/R/ && $0 ~/0/ && $0 !~/1/ && len > lenf) {seq1 = seq; fclus=clus;lenf=len}
		else if ($1 ~/R/ && $0 ~/0/ && $0 ~/1/) {seq1 = seq; fclus=clus; len1=len}
		else if ($1 ~/R/ && $0 ~!/0/ && freq > freqp && len >= lenp || $1 ~/R/ && $0 ~!/0/ && freq == freqp && len > lenp) {seq2 = seq; lenp = len; freqp=freq}
		}' > rainbow.fasta

	seqtk seq -r rainbow.fasta > rainbow.RC.fasta
	mv rainbow.RC.fasta rainbow.fasta

	#The rainbow assembly is checked for overlap between newly assembled Forward and Reverse reads using the software PEAR
	sed -e 's/NNNNNNNNNN/	/g' rainbow.fasta | cut -f1 | seqtk seq -F I - > ref.F.fq
	sed -e 's/NNNNNNNNNN/	/g' rainbow.fasta | cut -f2 | seqtk seq -F I - > ref.R.fq

	seqtk seq -r ref.R.fq > ref.RC.fq
	mv ref.RC.fq ref.R.fq
	LENGTH=$(mawk '!/>/' rainbow.fasta | mawk '(NR==1||length<shortest){shortest=length} END {print shortest}')
	LENGTH=$(( $LENGTH * 5 / 4))
	
	pearRM -f ref.F.fq -r ref.R.fq -o overlap -p 0.001 -j $NUMProc -n $LENGTH &>kopt.log

	rm ref.F.fq ref.R.fq

	mawk 'BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}' overlap.assembled.fastq > overlap.fasta
	mawk '/>/' overlap.fasta > overlap.loci.names
	mawk 'BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}' overlap.unassembled.forward.fastq > other.F
	mawk 'BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}' overlap.unassembled.reverse.fastq > other.R
	paste other.F other.R | mawk '{if ($1 ~ />/) print $1; else print $0}' | sed 's/	/NNNNNNNNNN/g' > other.FR

	cat other.FR overlap.fasta > totalover.fasta

	rm *.F *.R
fi

if [[ "$ATYPE" == "HYB" ]];then
	parallel --no-notice mawk -v x=$CUTOFF \''$1 >= x'\' ::: *.uniq.ua.seqs | cut -f2 | perl -e 'while (<>) {chomp; $z{$_}++;} while(($k,$v) = each(%z)) {print "$v\t$k\n";}' | mawk -v x=$2 '$1 >= x' > uniq.k.$CUTOFF.c.$CUTOFF2.ua.seqs
	AS=$(cat uniq.k.$CUTOFF.c.$CUTOFF2.ua.seqs | wc -l)
	if [ "$AS" -gt 1 ]; then
		cut -f2 uniq.k.$CUTOFF.c.$CUTOFF2.ua.seqs > totaluniqseq.ua
		mawk '{c= c + 1; print ">dDocent_Contig_" c "\n" $1}' totaluniqseq.ua > uniq.full.ua.fasta
		LENGTH=$(mawk '!/>/' uniq.full.ua.fasta  | mawk '(NR==1||length<shortest){shortest=length} END {print shortest}')
		LENGTH=$(($LENGTH * 3 / 4))
		seqtk seq -F I uniq.full.ua.fasta > uniq.ua.fq
		if [ "$NUMProc" -gt 8 ]; then
			NP=8
		else
			NP=$NumProc
		fi
		fastp -i uniq.ua.fq -o uniq.ua.fq1 -w $NP -Q &>/dev/null
		mawk 'BEGIN{P=1}{if(P==1||P==2){gsub(/^[@]/,">");print}; if(P==4)P=0; P++}' uniq.ua.fq1 > uniq.ua.fasta
		mawk '!/>/' uniq.ua.fasta > totaluniqseq.ua
		rm uniq.ua.fq*
		#Reads are first clustered using only the Forward reads using CD-hit instead of rainbow
		sed -e 's/NNNNNNNNNN/	/g' uniq.ua.fasta | cut -f1 > uniq.F.ua.fasta
		CDHIT=$(python -c "print(max("$simC" - 0.1,0.8))")
		cd-hit-est -i uniq.F.ua.fasta -o xxx -c $CDHIT -T 0 -M 0 -g 1 -d 100 &>cdhit.log
		mawk '{if ($1 ~ /Cl/) clus = clus + 1; else  print $3 "\t" clus}' xxx.clstr | sed 's/[>dDocent_Contig_,...]//g' | $sort -g -k1 -S 2G --parallel=$NUMProc > sort.contig.cluster.ids.ua
		paste sort.contig.cluster.ids.ua totaluniqseq.ua > contig.cluster.totaluniqseq.ua
		$sort -k2,2 -g -S 2G --parallel=$NUMProc contig.cluster.totaluniqseq.ua | sed -e 's/NNNNNNNNNN/	/g' > rcluster.ua
		#CD-hit output is converted to rainbow format
		rainbow div -i rcluster.ua -o rbdiv.ua.out -f 0.5 -K 10
		if [ "$ATYPE" == "PE" ]; then
			rainbow merge -o rbasm.ua.out -a -i rbdiv.ua.out -r 2 -N10000 -R10000 -l 20 -f 0.75
		else
			rainbow merge -o rbasm.ua.out -a -i rbdiv.ua.out -r 2 -N10000 -R10000 -l 20 -f 0.75
		fi
		
		#This AWK code replaces rainbow's contig selection perl script
		cat rbasm.ua.out <(echo "E") |sed 's/[0-9]*:[0-9]*://g' | mawk ' {
			if (NR == 1) e=$2;
			else if ($1 ~/E/ && lenp > len1) {c=c+1; print ">dDocent_Contig_UA_" e "\n" seq2 "NNNNNNNNNN" seq1; seq1=0; seq2=0;lenp=0;e=$2;fclus=0;len1=0;freqp=0;lenf=0}
			else if ($1 ~/E/ && lenp <= len1) {c=c+1; print ">dDocent_Contig_UA_" e "\n" seq1; seq1=0; seq2=0;lenp=0;e=$2;fclus=0;len1=0;freqp=0;lenf=0}
			else if ($1 ~/C/) clus=$2;
			else if ($1 ~/L/) len=$2;
			else if ($1 ~/S/) seq=$2;
			else if ($1 ~/N/) freq=$2;
			else if ($1 ~/R/ && $0 ~/0/ && $0 !~/1/ && len > lenf) {seq1 = seq; fclus=clus;lenf=len}
			else if ($1 ~/R/ && $0 ~/0/ && $0 ~/1/) {seq1 = seq; fclus=clus; len1=len}
			else if ($1 ~/R/ && $0 ~!/0/ && freq > freqp && len >= lenp || $1 ~/R/ && $0 ~!/0/ && freq == freqp && len > lenp) {seq2 = seq; lenp = len; freqp=freq}
			}' > rainbow.ua.fasta
	
		seqtk seq -r rainbow.ua.fasta > rainbow.RC.fasta
		mv rainbow.RC.fasta rainbow.ua.fasta
	
		cat rainbow.ua.fasta uniq.fasta > totalover.fasta

	fi
fi

if [[ "$ATYPE" != "PE" && "$ATYPE" != "RPE" && "$ATYPE" != "HYB" ]]; then
	cp uniq.fasta totalover.fasta
fi
cd-hit-est -i totalover.fasta -o reference.fasta.original -M 0 -T 0 -c $simC &>cdhit2.log

sed -e 's/^C/NC/g' -e 's/^A/NA/g' -e 's/^G/NG/g' -e 's/^T/NT/g' -e 's/T$/TN/g' -e 's/A$/AN/g' -e 's/C$/CN/g' -e 's/G$/GN/g' reference.fasta.original > reference.fasta

if [[ "$ATYPE" == "RPE" || "$ATYPE" == "ROL" ]]; then
	sed -i 's/dDocent/dDocentR/g' reference.fasta
fi

samtools faidx reference.fasta &> index.log
bwa index reference.fasta >> index.log 2>&1

SEQS=$(mawk 'END {print NR}' uniq.k.$CUTOFF.c.$CUTOFF2.seqs)
TIGS=$(grep ">" -c reference.fasta)

echo -e "\ndDocent assembled $SEQS sequences (after cutoffs) into $TIGS contigs"

}

##Create alignment intervals
##This takes advantage of the fact that RAD loci are very discrete.  Instead of calculating intervals for every BAM file,
##this function merges all BAM files together.  This overall BAM file 
##is used to create a single list of intervals, saving a large amount of computational time.

CreateIntervals()
{
samtools merge -@$NUMProc -b bamlist.list -f cat-RRG.bam &>/dev/null
samtools index cat-RRG.bam 
wait
bedtools merge -i cat-RRG.bam -bed >  mapped.bed
}

#This checks that dDocent has detected the proper number of individuals and exits if incorrect
GetInfo(){
echo "$NumInd individuals are detected. Is this correct? Enter yes or no and press [ENTER]"

read Indcorrect

if [ "$Indcorrect" == "no" ]; then
        echo "Please double check that all fastq files are named PopA_001.F.fq.gz and PopA_001.R.fq.gz"
        exit 1
elif [ "$Indcorrect" == "yes" ]; then
            echo "Proceeding with $NumInd individuals"
else
        echo "Incorrect Input"
        exit 1
fi

#Tries to get number of processors, if not asks user

if [[ "$OSTYPE" == "darwin"* ]]; then
	NUMProc=( `sysctl hw.ncpu | cut -f2 -d " " `)
else
	NUMProc=( `grep -c ^processor /proc/cpuinfo 2> /dev/null` ) 
fi

NUMProc=$(($NUMProc + 0)) 

echo "dDocent detects $NUMProc processors available on this system."
echo "Please enter the maximum number of processors to use for this analysis."
        read NUMProc
        
if [ $NUMProc -lt 1 ]; then
        echo "Incorrect. Please enter the number of processing cores on this computer"
        read NUMProc
fi                
if [ $NUMProc -lt 1 ]; then
        echo "Incorrect input, exiting"
        exit 1
fi

#Tries to get maximum system memory, if not asks user
if [[ "$OSTYPE" == "darwin"* ]]; then
	MAXMemory=0
else
	MAXMemory=$(($(grep -Po '(?<=^MemTotal:)\s*[0-9]+' /proc/meminfo | tr -d " ") / 1048576))


echo "dDocent detects $MAXMemory gigabytes of maximum memory available on this system."
echo "Please enter the maximum memory to use for this analysis in gigabytes"
echo "For example, to limit dDocent to ten gigabytes, enter 10"
echo -e "This option does not work with all distributions of Linux.  If runs are hanging at variant calling, enter 0"
echo -e "Then press [ENTER]"
        read MAXMemory1
	MAXMemory1=$( echo $MAXMemory1 | sed 's/[g,G]//g' )
	MAXMemory=$(( $MAXMemory1 / $NUMProc ))G

while [[ -z $MAXMemory ]];
	do
	echo "Incorrect input"
	echo -e "Please enter the maximum memory to use for this analysis in gigabytes." 
	echo -e "This option does not work with all distributions of Linux.  If runs are hanging at variant calling, enter 0"
	echo -e "Then press [ENTER]"
	read MAXMemory1
	MAXMemory=$(( $MAXMemory1 / $NUMProc ))G
	done
fi
#Asks if user wants to trim reads.  This allows this part of the pipeline to be skipped during subsequent analyses
echo -e "\nDo you want to quality trim your reads?" 
echo "Type yes or no and press [ENTER]?"

read TRIM

#Asks if user wants to perform an assembly.  This allows this part of the pipeline to be skipped during subsequent analyses

echo -e "\nDo you want to perform an assembly?"
echo "Type yes or no and press [ENTER]."

read ASSEMBLY

if [ "$ASSEMBLY" == "no" ]; then
        echo -e "\nReference contigs need to be in a file named reference.fasta\n"
        sleep 1
else
	echo -e "What type of assembly would you like to perform?  Enter SE for single end, PE for paired-end, RPE for paired-end sequencing for RAD protocols with random shearing, or OL for paired-end sequencing that has substantial overlap."
	echo -e "Then press [ENTER]"
	read ATYPE

	while [[ $ATYPE != "SE" && $ATYPE != "PE" && $ATYPE != "OL" && $ATYPE != "RPE" ]];
	do
	echo "Incorrect input"
	echo -e "What type of assembly would you like to perform?  Enter SE for single end, PE for paired-end, RPE for paired-end sequencing for RAD protocols with random shearing, or OL for paired-end sequencing that has substantial overlap."
	echo -e "Then press [ENTER]"
	read ATYPE
	done
fi
#If performing de novo assembly, asks if the user wants to enter a different -c value
if [ "$ASSEMBLY" == "yes" ]; then
    echo "Reads will be assembled with Rainbow"
    echo "CD-HIT will cluster reference sequences by similarity. The -c parameter (% similarity to cluster) may need to be changed for your taxa."
    echo "Would you like to enter a new c parameter now? Type yes or no and press [ENTER]"
    read optC
    if [ "$optC" == "no" ]; then
            echo "Proceeding with default 0.9 value."
            simC=0.9
        elif [ "$optC" == "yes" ]; then
            echo "Please enter new value for c. Enter in decimal form (For 90%, enter 0.9)"
            read newC
            simC=$newC
        else
            echo "Incorrect input. Proceeding with the default value."
            simC=0.9
        fi
fi

#Asks if user wants to map reads and change default mapping variables for BWA
echo "Do you want to map reads?  Type yes or no and press [ENTER]"
read MAP
if [ "$MAP" == "no" ]; then
        echo "Mapping will not be performed"
        optA=1
    	optB=4
    	optO=6
        else
                echo "BWA will be used to map reads.  You may need to adjust -A -B and -O parameters for your taxa."
                echo "Would you like to enter a new parameters now? Type yes or no and press [ENTER]"
                read optq

        if [ "$optq" == "yes" ]; then
        echo "Please enter new value for A (match score).  It should be an integer.  Default is 1."
        read newA
        optA=$newA
                echo "Please enter new value for B (mismatch score).  It should be an integer.  Default is 4."
        read newB
        optB=$newB
                echo "Please enter new value for O (gap penalty).  It should be an integer.  Default is 6."
        read newO
        optO=$newO
        else
                echo "Proceeding with default values for BWA read mapping."
                optA=1
                optB=4
                optO=6
        fi
fi

#Does user wish to call SNPs?
echo "Do you want to use FreeBayes to call SNPs?  Please type yes or no and press [ENTER]"
read SNP

while [[ $SNP != "yes" && $SNP != "no" ]];
	do
	echo "Incorrect input"
	echo -e "Do you want to use FreeBayes to call SNPs?  Please type yes or no and press [ENTER]"
	read SNP
	done

#Asks user for email address to notify when analysis is complete
echo ""
echo "Please enter your email address.  dDocent will email you when it is finished running."
echo "Don't worry; dDocent has no financial need to sell your email address to spammers."
read MAIL
echo ""
echo ""

if [ "$ASSEMBLY" == "no" ]; then
#Prints instructions on how to move analysis to background and disown process
echo "At this point, all configuration information has been entered and dDocent may take several hours to run." 
echo "It is recommended that you move this script to a background operation and disable terminal input and output."
echo "All data and logfiles will still be recorded."
echo "To do this:"
echo "Press control and Z simultaneously"
echo "Type 'bg' without the quotes and press enter"
echo "Type 'disown -h' again without the quotes and press enter"
echo ""
echo "Now sit back, relax, and wait for your analysis to finish"
fi

if [ "$ASSEMBLY" == "yes" ]; then
echo "dDocent will require input during the assembly stage.  Please wait until prompt says it is safe to move program to the background."
fi
}

#Actually starts program
if [ -n "$1" ]; then
	main $1 2>&1 | tee -a dDocent_main.LOG #Log all output
else
	main 2>&1 | tee -a dDocent_main.LOG  #Log all output
fi


#Compress Large Leftover files
gzip -f concat.fasta concat.seq rcluster rbdiv.out rbasm.out rainbow.fasta reference.fasta.original uniq.seqs uniq.fasta totaluniqseq uniq.F.fasta uniq.RC.fasta 2> /dev/null &